ETS_FILE=local/Beverly Mai - Maison.knxproj
SPECIAL=laurent_specific.rb
ETS_EXT=.knxproj
HA_EXT=.ha.yaml
LK_EXT=.linknx.xml
XK_EXT=.xknx.yaml
TESTFILES=sample
all::
	./ets_to_hass.rb homeass "$(ETS_FILE)" $(SPECIAL) > "$$(basename "$(ETS_FILE)" $(ETS_EXT))$(HA_EXT)"
	./ets_to_hass.rb linknx  "$(ETS_FILE)" $(SPECIAL) > "$$(basename "$(ETS_FILE)" $(ETS_EXT))$(LK_EXT)"
clean:
	rm -f *$(HA_EXT) *$(LK_EXT) *$(XK_EXT)
test:
	./ets_to_hass.rb homeass $(TESTFILES)/Style1.knxproj
	./ets_to_hass.rb homeass $(TESTFILES)/Style2.knxproj
	./ets_to_hass.rb homeass $(TESTFILES)/Style3.knxproj
