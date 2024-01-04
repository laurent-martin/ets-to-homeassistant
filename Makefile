# cspell:ignore pubkey gemdir firstword

# DIR_TOP: main folder of this project (with trailing slash)
# if "" (empty) or "./" : execute "make" inside the main folder
# alternatively : $(shell dirname "$(realpath $(firstword $(MAKEFILE_LIST)))")/
DIR_TOP=

# must be first target
all::
ETS_EXT=.knxproj
HA_EXT=.ha.yaml
LK_EXT=.linknx.xml
XK_EXT=.xknx.yaml

# just the name of the command line tool as in bin folder
CLI_NAME=ets_to_hass

# define common variables to be used in other Makefile
# required: DIR_TOP (can be empty if cwd)
DIR_BIN=$(DIR_TOP)bin/
DIR_LIB=$(DIR_TOP)lib/
DIR_TMP=$(DIR_TOP)tmp/
DIR_PRIV=$(DIR_TOP)local/
DIR_DOC=$(DIR_TOP)docs/
DIR_SAMPLES=$(DIR_TOP)examples

# path to CLI for execution (not using PATH)
CLI_PATH=$(DIR_BIN)$(CLI_NAME)
# create Makefile file with macros GEM_NAME and GEM_VERSION
NAME_VERSION=$(DIR_TMP)name_version.mak
VERSION_FILE=$(DIR_LIB)ets_to_hass/info.rb
$(NAME_VERSION): $(DIR_TMP).exists $(VERSION_FILE)
	sed -n "s/.*NAME = '\([^']*\)'.*/GEM_NAME=\1/p" $(VERSION_FILE) > $@
	sed -n "s/.*VERSION = '\([^']*\)'.*/GEM_VERSION=\1/p" $(VERSION_FILE) >> $@
include $(NAME_VERSION)
GEMSPEC=$(DIR_TOP)$(GEM_NAME).gemspec
PATH_GEMFILE=$(DIR_TOP)$(GEM_NAME)-$(GEM_VERSION).gem
# override GEM_VERSION with beta version
BETA_VERSION_FILE=$(DIR_TMP)beta_version
MAKE_BETA=GEM_VERSION=$$(cat $(BETA_VERSION_FILE)) make -e
$(BETA_VERSION_FILE):
	echo $(GEM_VERSION).$$(date +%Y%m%d%H%M) > $(BETA_VERSION_FILE)
# gem file is generated in top folder
clean::
	rm -f $(NAME_VERSION)
$(DIR_TMP).exists:
	mkdir -p $(DIR_TMP)
	@touch $@
# Ensure required ruby gems are installed
$(DIR_TOP).gems_checked: $(DIR_TOP)Gemfile
	cd $(DIR_TOP). && bundle config set --local with development
	cd $(DIR_TOP). && bundle install
	touch $@
clean:: clean_gems_installed
clean_gems_installed:
	rm -f $(DIR_TOP).gems_checked $(DIR_TOP)Gemfile.lock

all:: $(DIR_TOP).gems_checked signed_gem
clean::
	rm -fr $(DIR_TMP)
	rm -f Gemfile.lock
clean_doc::
	cd $(DIR_DOC) && make clean_doc
##################################
# Gem build
$(PATH_GEMFILE): $(DIR_TOP).gems_checked
	gem build $(GEMSPEC)
	gem specification $(PATH_GEMFILE) version
# check that the signing key is present
gem_check_signing_key:
	@echo "Checking env var: SIGNING_KEY"
	@if test -z "$$SIGNING_KEY";then echo "Error: Missing env var SIGNING_KEY" 1>&2;exit 1;fi
	@if test ! -e "$$SIGNING_KEY";then echo "Error: No such file: $$SIGNING_KEY" 1>&2;exit 1;fi
# force rebuild of gem and sign it, then check signature
signed_gem: clean_gem gem_check_signing_key $(PATH_GEMFILE)
	@tar tf $(PATH_GEMFILE)|grep '\.gz\.sig$$'
	@echo "Ok: gem is signed"
# build gem without signature for development and test
unsigned_gem: $(PATH_GEMFILE)
beta_gem:
	rm -f $(BETA_VERSION_FILE)
	make build_beta_gem
build_beta_gem: $(BETA_VERSION_FILE)
	$(MAKE_BETA) unsigned_gem
clean_gem:
	rm -f $(PATH_GEMFILE)
	rm -f $(DIR_TOP)$(GEM_NAME)-*.gem
install: $(PATH_GEMFILE)
	gem install $(PATH_GEMFILE)
clean_gems: clean_gems_installed
	if ls $$(gem env gemdir)/gems/* > /dev/null 2>&1; then gem uninstall -axI $$(ls $$(gem env gemdir)/gems/|sed -e 's/-[0-9].*$$//'|sort -u);fi
# gems that require native build are made optional
OPTIONAL_GEMS=grpc mimemagic rmagick
clean_optional_gems:
	gem uninstall $(OPTIONAL_GEMS)
install_gems: $(DIR_TOP).gems_checked
# grpc is installed on the side , if needed
install_optional_gems: install_gems
	gem install $(OPTIONAL_GEMS)
clean:: clean_gem
##################################
# Gem certificate
# Update the existing certificate, keeping the maintainer email
update-cert: gem_check_signing_key
	cert_chain=$(DIR_TOP)$$(sed -nEe "s/ *spec.cert_chain.+'(.+)'.*/\1/p" < $(GEMSPEC))&&\
	gem cert \
	--re-sign \
	--certificate $$cert_chain \
	--private-key $$SIGNING_KEY \
	--days 1100
# Create a new certificate, taking the maintainer email from gemspec
new-cert: gem_check_signing_key
	mkdir -p $(DIR_TOP)certs
	maintainer_email=$$(sed -nEe "s/ *spec.email.+'(.+)'.*/\1/p" < $(GEMSPEC))&&\
	gem cert \
	--build $$maintainer_email \
	--private-key $$SIGNING_KEY \
	--days 1100
	cert_chain=$(DIR_TOP)$$(sed -nEe "s/ *spec.cert_chain.+'(.+)'.*/\1/p" < $(GEMSPEC))&&\
	mv gem-public_cert.pem $$cert_chain
show-cert:
	cert_chain=$(DIR_TOP)$$(sed -nEe "s/ *spec.cert_chain.+'(.+)'.*/\1/p" < $(GEMSPEC))&&\
	openssl x509 -noout -text -in $$cert_chain|head -n 13
check-cert-key: $(DIR_TMP).exists gem_check_signing_key
	@cert_chain=$(DIR_TOP)$$(sed -nEe "s/ *spec.cert_chain.+'(.+)'.*/\1/p" < $(GEMSPEC))&&\
	openssl x509 -noout -pubkey -in $$cert_chain > $(DIR_TMP)cert.pub
	@openssl rsa -pubout -passin pass:_value_ -in $$SIGNING_KEY > $(DIR_TMP)sign.pub
	@if cmp -s $(DIR_TMP)cert.pub $(DIR_TMP)sign.pub;then echo "Ok: certificate and key match";else echo "Error: certificate and key do not match" 1>&2;exit 1;fi
##################################
# Gem publish
release: all
	gem push $(PATH_GEMFILE)
version:
	@echo $(GEM_VERSION)
# in case of big problem on released gem version, it can be deleted from rubygems
# gem yank -v $(GEM_VERSION) $(GEM_NAME) 

##################################
# GIT
changes:
	@latest_tag=$$(git describe --tags --abbrev=0);\
	echo "Changes since [$$latest_tag]";\
	git log $$latest_tag..HEAD --oneline

##################################
# Docker image
DOCKER_REPO=martinlaurent/ets-to-homeassistant
DOCKER_IMG_VERSION=$(GEM_VERSION)
DOCKER_TAG_VERSION=$(DOCKER_REPO):$(DOCKER_IMG_VERSION)
DOCKER_TAG_LATEST=$(DOCKER_REPO):latest
DOCKER_FILE_TEMPLATE=sed -Ee 's/^\#erb:(.*)/<%\1%>/' < Dockerfile.tmpl.erb | erb -T 2
# Refer to section "build" in CONTRIBUTING.md
# no dependency: always re-generate
dockerfile_release:
	$(DOCKER_FILE_TEMPLATE) arg_gem=$(GEM_NAME):$(GEM_VERSION) > Dockerfile
docker: dockerfile_release
	docker build --squash --tag $(DOCKER_TAG_VERSION) --tag $(DOCKER_TAG_LATEST) .
dockerfile_beta:
	$(DOCKER_FILE_TEMPLATE) arg_gem=$(PATH_GEMFILE) > Dockerfile
docker_beta_build: dockerfile_beta $(PATH_GEMFILE)
	docker build --squash --tag $(DOCKER_TAG_VERSION) .
docker_beta: $(BETA_VERSION_FILE)
	$(MAKE_BETA) docker_beta_build
docker_push_beta: $(BETA_VERSION_FILE)
	$(MAKE_BETA) docker_push_version
docker_test:
	docker run --tty --interactive --rm $(DOCKER_TAG_VERSION)
docker_push: docker_push_version docker_push_latest
docker_push_version:
	docker push $(DOCKER_TAG_VERSION)
docker_push_latest:
	docker push $(DOCKER_TAG_LATEST)
clean::
	rm -f Dockerfile
##################################
# utils
tidy:
	rubocop $(DIR_LIB).
ETS_FILE=private/laurent/Beverly Mai - Maison.knxproj
CODE=$(DIR_LIB)ets_to_hass/specific/
SPECIAL=$(CODE)laurent.rb
# --sort-by-name 
laurent:
	$(CLI_PATH) --format homeass --full-name --fix $(SPECIAL) --output "$$(echo "$(ETS_FILE)" | sed 's|$(ETS_EXT)$$|$(HA_EXT)|')" "$(ETS_FILE)"
laurent2:
	$(CLI_PATH) --format linknx  --fix $(SPECIAL) --output "$$(echo "$(ETS_FILE)" | sed 's|$(ETS_EXT)$$|$(LK_EXT)|')" "$(ETS_FILE)"
clean::
	rm -f *$(HA_EXT) *$(LK_EXT) *$(XK_EXT)
test: unsigned_gem
	$(CLI_PATH) --fix $(CODE)/generic.rb $(DIR_SAMPLES)/Style1.knxproj
	$(CLI_PATH) --fix $(CODE)/generic.rb $(DIR_SAMPLES)/Style2.knxproj
	$(CLI_PATH) --fix $(CODE)/generic.rb $(DIR_SAMPLES)/Style3.knxproj
	$(CLI_PATH) --fix $(CODE)/generic.rb $(DIR_SAMPLES)/Style3.knxproj --addr Free
