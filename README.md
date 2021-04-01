# ets-to-homeassistant

A simple ruby script to convert an ETS5 project file (*.knxproj) into:

* a YAML configuration file suitable for Home Assistant
* an XML file for linknx (the object list only)
* YAML for xknx

Note the ETS group type is either taken for the type in project if present, or by parsing the name of the group, which should follow the format:

```
<location>:<object>:<additional>
```

`location` is the name of the room where the controlled object is located

`object` is the name of the object (e.g. kitchen light)

`additional` contains additional information, such as type of command, special values:

* `ON/OFF` : type 1.001
* `variation` : type 3.007
* `valeur` : type 5.001
