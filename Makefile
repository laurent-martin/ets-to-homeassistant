ETS_FILE=Beverly Mai - Maison.knxproj
SPECIAL=laurent_specific.rb
ETS_EXT=.knxproj
HA_EXT=.ha.yaml
LK_EXT=.linknx.xml
XK_EXT=.xknx.yaml
all::
	./ets_to_hass.rb "$(ETS_FILE)" homeass $(SPECIAL) > "$$(basename "$(ETS_FILE)" $(ETS_EXT))$(HA_EXT)"
	./ets_to_hass.rb "$(ETS_FILE)" linknx  $(SPECIAL) > "$$(basename "$(ETS_FILE)" $(ETS_EXT))$(LK_EXT)"
clean:
	rm -f *$(HA_EXT) *$(LK_EXT) *$(XK_EXT)
