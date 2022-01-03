# ets-to-homeassistant

A Ruby script to convert an ETS5 project file (*.knxproj) into:

* a YAML configuration file suitable for Home Assistant
* an XML file for linknx (the object list only)
* YAML for xknx

[https://www.home-assistant.io/integrations/knx/](https://www.home-assistant.io/integrations/knx/)

## Usage

Install Ruby for your platform (Windows, macOS, Linux), install required gems (xmlsimple, zip).

```
./ets_to_hass.rb <xknx|homeass|linknx> <input file> [<special processing lambda>]
```

Set env var DEBUG to one of: debug, info, warn, error (default is info)

Set env var GADDRSTYLE to Free, TwoLevel, ThreeLevel to override project group address style.
    
## Structure in ETS

The script takes the exported file with extension: `knxproj`.
This file is a zip with several XML files in it.
The script parses the first project file found.
It extracts group address information, as well as Building information.

<p align="center"><img src="images/ets5.png" width="100%"/><br/>Fig. 1 ETS 5 with building</p>

## Home Assistant

In building information, "functions" are mapped to Home Assistant objects, such as dimmable lights, which group several group addresses.

So, it is mandatory to create functions in order for the script to find objects.

## Linknx

`linknx` does not have an object concept, and needs only group addresses.

## XKNX

Support is dropped for the moment, until needed.

## Special processing

It is possible to provide a post-processing function that can modify the analyzed structure, either to add information or change objects.

For instance if you use naming conventions or information in the description field of group address.

The function is called on the global data hash, which contains both group address and building information.

