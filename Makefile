ETS_EXT=.knxproj
HA_EXT=.ha.yaml
LK_EXT=.linknx.xml
XK_EXT=.xknx.yaml
PROJ_DIR=./
TESTFILES=$(PROJ_DIR)examples
TOOL=$(PROJ_DIR)bin/ets_to_hass
all::
	@echo "nothing to build, do: make laurent"
ETS_FILE=private/laurent/Beverly Mai - Maison.knxproj
SPECIAL=$(PROJ_DIR)examples/laurent_specific.rb
laurent:
	$(TOOL) --format homeass --specific $(SPECIAL) --full-name "$(ETS_FILE)" --output "$$(echo "$(ETS_FILE)" | sed 's|$(ETS_EXT)$$|$(HA_EXT)|')"
	$(TOOL) --format linknx  --specific $(SPECIAL) "$(ETS_FILE)" --output "$$(echo "$(ETS_FILE)" | sed 's|$(ETS_EXT)$$|$(LK_EXT)|')"
clean:
	rm -f *$(HA_EXT) *$(LK_EXT) *$(XK_EXT)
test:
	$(TOOL) $(TESTFILES)/Style1.knxproj
	$(TOOL) $(TESTFILES)/Style2.knxproj
	$(TOOL) $(TESTFILES)/Style3.knxproj
setup:
	gem install bundler
	bundle install
clean_gems:
	if ls $$(gem env gemdir)/gems/* > /dev/null 2>&1; then gem uninstall -axI $$(ls $$(gem env gemdir)/gems/|sed -e 's/-[0-9].*$$//'|sort -u);fi
