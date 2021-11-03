ETS_FILE=Beverly Mai - Maison_20211102.knxproj
SPECIAL=laurent_specific.rb
ETS_EXT=.knxproj
HA_EXT=.ha.yaml
all::
	./ets_to_hass.rb "$(ETS_FILE)" homeass "$$(basename "$(ETS_FILE)" $(ETS_EXT))$(HA_EXT)" $(SPECIAL)
clean:
	rm -f *$(HA_EXT) *.linknx.xml *.xknx.yaml
