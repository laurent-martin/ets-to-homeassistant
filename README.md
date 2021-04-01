# ets-to-homeassistant

A simple ruby script to convert an ETS5 project file (*.knxproj) into:

* a YAML configuration file suitable for Home Assistant
* an XML file for linknx (the object list only)
* YAML for xknx

Usage 1:

ets_to_hass.rb myproject.knxproj

This will generate files in a generic way, but it does not find if objects are light, etc..

Usage 2:

write a little ruby code (specific.rb) to add special logic, for instance if you use naming conventions.

SPECIAL=specific.rb ./ets_to_hass.rb myproject.knxproj

This way a special code is called for each group address and give the opportunity to guess some values.

For instance in my project I use the following format for names:

```
<location>:<object>:<additional>
```

`location` is the name of the room where the controlled object is located

`object` is the name of the object (e.g. kitchen light)

`additional` contains additional information, such as type of command, special values:

* `ON/OFF` : type 1.001
* `variation` : type 3.007
* `valeur` : type 5.001

https://www.home-assistant.io/integrations/knx/

# TODO

make more generic, add types
