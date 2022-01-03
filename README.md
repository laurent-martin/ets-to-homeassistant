# ets-to-homeassistant

A Ruby script to convert an ETS5 project file (*.knxproj) into:

* a YAML configuration file suitable for Home Assistant (requires to define the building and functions in ETS)
* an XML file for linknx (the object list only)

[https://www.home-assistant.io/integrations/knx/](https://www.home-assistant.io/integrations/knx/)

## Usage

Install Ruby for your platform (Windows, macOS, Linux), install required gems (xmlsimple, zip).

```
./ets_to_hass.rb <homeass|linknx> <input file> [<special processing lambda>]
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

Once the project file has been parsed, an object of type: `ConfigurationImporter` is created with property: `data`. structured like this:

```
data ={
	ob:{
		_obid_ => {
			name:   "...",
			type:   "object type, see below",
			floor:  name of floor,
			room:   name of room,
			ga:     [list of included group addresses identifiers],
			custom: {custom values set by lambda: ha_init, ha_type}
		},...
	},
	ga:{
		_gaid_ => {
			name:             "name",
			description:      description,
			address:          group address as string. e.g. "x/y/z" depending on project style,
			datapoint:        datapoint type as string "x.00y",
			objs:             [list of objects ids with this ga],
			custom:           {custom values set by lambda: ha_property, linknx_disp_name }                                            # 
		},...
	}
}
```

types include:

```
:custom,:switchable_light,:dimmable_light,:sun_protection,:heating_radiator,:heating_floor,:heating_switching_variable,:heating_continuous_variable
```

It is possible to provide a post-processing function that can modify the analyzed structure, either to add information or change objects.

For instance if you use naming conventions or information in the description field of group address.

The function is called on the global data hash, which contains both group address and building information.

