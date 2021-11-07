ETS_FILE=Beverly Mai - Maison_20211107.knxproj
SPECIAL=laurent_specific.rb
ETS_EXT=.knxproj
HA_EXT=.ha.yaml
LK_EXT=.linknx.xml
XK_EXT=.xknx.yaml
all::
	./ets_to_hass.rb "$(ETS_FILE)" homeass "$$(basename "$(ETS_FILE)" $(ETS_EXT))$(HA_EXT)" $(SPECIAL)
	./ets_to_hass.rb "$(ETS_FILE)" linknx  "$$(basename "$(ETS_FILE)" $(ETS_EXT))$(LK_EXT)" $(SPECIAL)
	./ets_to_hass.rb "$(ETS_FILE)" xknx    "$$(basename "$(ETS_FILE)" $(ETS_EXT))$(XK_EXT)" $(SPECIAL)
clean:
	rm -f *$(HA_EXT) *$(LK_EXT) *$(XK_EXT)
