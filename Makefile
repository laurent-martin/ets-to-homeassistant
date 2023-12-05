ETS_FILE=local/Beverly Mai - Maison.knxproj
SPECIAL=laurent_specific.rb
ETS_EXT=.knxproj
HA_EXT=.ha.yaml
LK_EXT=.linknx.xml
XK_EXT=.xknx.yaml
TESTFILES=sample
all::
	./ets_to_hass.rb --format homeass --lambda $(SPECIAL) --full-name "$(ETS_FILE)" > "$$(basename "$(ETS_FILE)" $(ETS_EXT))$(HA_EXT)"
	./ets_to_hass.rb --format linknx  --lambda $(SPECIAL) "$(ETS_FILE)" > "$$(basename "$(ETS_FILE)" $(ETS_EXT))$(LK_EXT)"
clean:
	rm -f *$(HA_EXT) *$(LK_EXT) *$(XK_EXT)
test:
	./ets_to_hass.rb $(TESTFILES)/Style1.knxproj
	./ets_to_hass.rb $(TESTFILES)/Style2.knxproj
	./ets_to_hass.rb $(TESTFILES)/Style3.knxproj
setup:
	gem install bundler
	bundle install
clean_gems:
	if ls $$(gem env gemdir)/gems/* > /dev/null 2>&1; then gem uninstall -axI $$(ls $$(gem env gemdir)/gems/|sed -e 's/-[0-9].*$$//'|sort -u);fi
