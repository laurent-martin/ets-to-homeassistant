# ETS project file to Home Assistant configuration

A Ruby script to convert an ETS5 project file (`*.knxproj`) into:

* a YAML configuration file suitable for Home Assistant (requires to define the building and functions in ETS)
* an XML file for `linknx` (the object list only)

[https://www.home-assistant.io/integrations/knx/](https://www.home-assistant.io/integrations/knx/)

Important note: if only group addresses are defined in ETS, then the script cannot collate them into a single H.A. object.
For example: switch, state and dimming function of a single light.
For details, see section [Structure in ETS](#structure-in-ets)

## Installation

[Install Ruby for your platform](https://www.ruby-lang.org/fr/downloads/):

* Linux: builtin (yum, apt), or [RVM](https://rvm.io/), or [rbenv](https://github.com/rbenv/rbenv)
* macOS: builtin, or [RVM](https://rvm.io/), or [brew](https://brew.sh/), or [rbenv](https://github.com/rbenv/rbenv)
* Windows: [Ruby Installer](https://rubyinstaller.org/)

Clone this repo:

    git clone https://github.com/laurent-martin/ets-to-homeassistant.git

Install required gems (`xml-simple`, `rubyzip`):

    cd ets-to-homeassistant

    gem install bundler

    bundle install

## Usage

Once Ruby is installed and this repo cloned, change directory to the main folder and execute `./ets_to_hass.rb`:

The general invokation syntax:

    ./ets_to_hass.rb <homeass|linknx> <input file> [<special processing lambda file>]

Set env var `DEBUG` to one of: `debug`, `info`, `warn`, `error` (default is `info`)

Set env var `GADDRSTYLE` to `Free`, `TwoLevel`, `ThreeLevel` to override project group address style. (Else, the tool detects the one used in the project).

For example to generate the home assistant KNX configuration from the exported ETS project: `myexport.knxproj`

    ./ets_to_hass.rb homeass myexport.knxproj

    DEBUG=debug ./ets_to_hass.rb homeass myexport.knxproj

The special processing lambda is `default_custom.rb` if none is provided.
It will generate basic Objects/Functions for group addresses not part of a function.

## Structure in ETS

The script takes the exported file with extension: `knxproj`.
This file is a zip with several XML files in it.
The script parses the first project file found.
It extracts group address information, as well as Building information.

<p align="center"><img src="images/ets5.png" width="100%"/><br/>Fig. 1 ETS 5 with building</p>

Building "functions" are used to gernerate H.A. objects. If the ETS project has no building information, then
the script will create one object per group address.
It is also possible to add this information using the third argument (script) which can add missing information, based, for example, on group address name.

## Home Assistant

In building information, "functions" are mapped to Home Assistant objects, such as dimmable lights, which group several group addresses.

So, it is mandatory to create functions in order for the script to find objects.

## Linknx

`linknx` does not have an object concept, and needs only group addresses.

## XKNX

Support is dropped for the moment, until needed, but it is close enough to HA.

## Special processing

Once the project file has been parsed, an object of type: `ConfigurationImporter`.
It's property `data` contains the project data and is structured like this:

```ruby
{
	ob:{
		_obid_ => {
			name:   "from ETS",
			type:   "object type, see below",
			floor:  "from ETS",
			room:   "from ETS",
			ga:     [list of _gaid_ included in this object],
			custom: {custom values set by lambda: ha_init, ha_type}
		},...
	},
	ga:{
		_gaid_ => {
			name:             "from ETS",
			description:      "from ETS",
			address:          group address as string. e.g. "x/y/z" depending on project style,
			datapoint:        datapoint type as string "x.00y",
			objs:             [list of _obid_ using this group address],
			custom:           {custom values set by lambda: ha_address_type, linknx_disp_name }                                            # 
		},...
	}
}
```

* `_obid_` is the internal identifier of the function in ETS
* `_gaid_` is the internal identifier of the group address in ETS

**object type** are functions defined by ETS:

* `:custom`
* `:switchable_light`
* `:dimmable_light`
* `:sun_protection`
* `:heating_radiator`
* `:heating_floor`
* `:heating_switching_variable`
* `:heating_continuous_variable`

The optional post-processing function can modify the analyzed structure:

* It can delete objects, or create objects.
* It can add fields in the `:custom` properties:

  * `ha_init` : initialize the HA object with some values
  * `ha_type` : force the entity type in HA
  * `ha_address_type` : define the use for the group address
  * `linknx_disp_name` : set the description of group address in `linknx`

The function can use any information such as fields of the object, or description or name of group address for that.

The function is called with the `ConfigurationImporter` as argument, from which property `data` is used.
