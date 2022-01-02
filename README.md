# ets-to-homeassistant

A Ruby script to convert an ETS5 project file (*.knxproj) into:

* a YAML configuration file suitable for Home Assistant
* an XML file for linknx (the object list only)
* YAML for xknx

[https://www.home-assistant.io/integrations/knx/](https://www.home-assistant.io/integrations/knx/)

## Usage

```
./ets_to_hass.rb <input file> <xknx|homeass|linknx> [<special processing lambda>]
```

## Structure in ETS

The script takes the exported file with extension: `knxproj`.
This file is a zip with several XML files in it.
The script parses the first project file found.
It extracts group address information, as well as Building information.

The script assumes 3-level address.

<img href="./images/ets.png"/>

## Home Assistant

In building information, "functions" are mapped to Home Assistant objects, such as dimmable lights, which group several group addresses.

So, it is mandatory to create functions in order for the script to find objects.

## Linknx

`linknx` does not have an object concept, and needs only group addresses.

## XKNX

Support is dropped for the moment, until needed.

## Special processing

If there are some special things to do, just before processing, the whole built structure is passed to a user-specific function (Ruby).

For instance if you use naming conventions or information in the description field of group address.

The function is called on the global data hash, which contains both group address and building information.

