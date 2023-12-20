# ETS project file to Home Assistant configuration

A Ruby tool to convert an ETS5 project file (`*.knxproj`) into:

* a YAML configuration file suitable for **Home Assistant** (requires to define building, functions and group datapoints in ETS)
* an XML file for `linknx` (the object list only)

[https://www.home-assistant.io/integrations/knx/](https://www.home-assistant.io/integrations/knx/)

## Important note

In order for the tool to generate result properly read the following.

Actionable entities in KNX are **Group Addresses** (GA).
For example a dimmable light has at least one group address for On/Off and another for the dimming value.

Actionable entities in **Home Assistant** (HA) are devices.
For example, a dimmable light is a device and has properties, one of them is the group address for On/Off and another is the group address for the dimming value.

So, for the tool to work, the following pieces of information must be found:

* Group addresses
* Type of group address (On/Off, dimming value, etc.)
* Grouping of group addresses into devices

By default, and in fact in a lot of ETS projects, only group addresses are defined as this is sufficient for an installation.
I.e. no functions are defined, and data point types are not defined for group addresses.
This is why this tool will not work out of the box most of the times: missing information.
The next 2 sections explain how to fix this.

### Group address: Type

Group addresses are defined in the ETS project file naturally, as it is the base for the system to work.
But we need the types of them (e.g. **on/off** versus **dim value**) in order to create the HA configuration.

The best, easiest and more reliable way for the tool to find the **data point type** is to specify the **data point type** in the group address itself.
This requires editing the KNX project.
Refer to [Structure in ETS](#structure-in-ets).

Another possibility is to create a custom script.
Refer to [Custom method](#custom-method)

### Group address: Grouping into devices

The second part is to group **group addresses** into devices.
This is best done by creating **Functions** in ETS.
Refer to [Structure in ETS](#structure-in-ets).

Another possibility is to create a custom script.
Refer to [Custom method](#custom-method)

## Installation

[Install Ruby for your platform](https://www.ruby-lang.org/fr/downloads/):

* Linux: builtin (yum, apt), or [RVM](https://rvm.io/), or [rbenv](https://github.com/rbenv/rbenv)
* macOS: builtin, or [RVM](https://rvm.io/), or [brew](https://brew.sh/), or [rbenv](https://github.com/rbenv/rbenv)
* Windows: [Ruby Installer](https://rubyinstaller.org/)

Clone this repo:

```bash
git clone https://github.com/laurent-martin/ets-to-homeassistant.git
````

Install required gems (`xml-simple`, `rubyzip`):

```bash
cd ets-to-homeassistant

gem install bundler

bundle install
```

## Usage

Once Ruby is installed and this repo cloned, change directory to the main folder and execute `./ets_to_hass.rb`:

The general invocation syntax:

```bash
Usage: ./ets_to_hass.rb [--format format] [--lambda lambda] [--addr addr] [--trace trace] [--ha-knx] [--full-name] <etsprojectfile>.knxproj

-h, --help:
 show help

--format [format]:
 one of homeass|linknx

--lambda [lambda]:
 file with lambda

--addr [addr]:
 one of Free, TwoLevel, ThreeLevel

--trace [trace]:
 one of debug, info, warn, error

--ha-knx:
 include level knx in ouput file

--full-name:
 add room name in object name
```

For example to generate the home assistant KNX configuration from the exported ETS project: `myexport.knxproj`

```bash
./ets_to_hass.rb --format homeass myexport.knxproj > ha.yaml
./ets_to_hass.rb --format homeass --trace debug myexport.knxproj > ha.yaml
```

Option `--ha-knx` adds the dictionary key `knx` in the generated Home Assistant configuration.
Else, typically, include the generated entities in a separate file like this:

```yaml
knx: !include config_knx.yaml
```

The special processing lambda is `default_custom.rb` if none is provided.
It will generate basic Objects/Functions for group addresses not part of a function.

The generated result is displayed on terminal (STDOUT), so to store in a file, redirect using `>`.

Logs are sent to STDERR.

## Internal logic

The tool takes the exported file from ETS with extension: `knxproj`.
The project file is a zip with several XML files in it.
The tool parses the first project file found.
It extracts group address information, as well as Building information.
Make sure that the project file is not password protected.

Once the project file has been parsed, an object of type: `ConfigurationImporter` is created.
Then, the custom method is called.

The property `data` of the object contains the project data and is structured like this:

```ruby
{
 ga:{
  _gaid_ => {
   name:             "from ETS",
   description:      "from ETS",
   address:          group address as string. e.g. "x/y/z" depending on project style,
   datapoint:        datapoint type as string "x.00y",
   objs:             [list of _obid_ using this group address],
   custom:           {custom values set by lambda: ha_address_type, linknx_disp_name }                                            # 
  },...
 },
 ob:{
  _obid_ => {
   name:   "from ETS",
   type:   "object type, see below",
   floor:  "from ETS",
   room:   "from ETS",
   ga:     [list of _gaid_ included in this object],
   custom: {custom values set by lambda: ha_init, ha_type}
  },...
 }
}
```

`ga` contains all Group addresses, `_gaid_` is the internal identifier of the group address in ETS

`ob` contains all ETS **Functions**, `_obid_` is the internal identifier of the function in ETS

## Structure in ETS

Group Address types are used to findout HA device properties.
For each group address make sure to define the type as in the following screenshot:

![datapoint in group address](images/ets5_datapoint.png)

Building **Functions** are used to generate HA devices.
If the ETS project has no building information, then the tool will create one device per group address.

In the following screenshot, note that both group addresses and building **Functions** are created.

![ETS 5 with building functions](images/ets5.png)

Moreover, if the functions are located properly in building levels and rooms, the tool will read this information.

When ETS **Functions** are found, the tool will populate the `ob` Hash.

**object type** are functions defined by ETS:

* `:custom`
* `:switchable_light`
* `:dimmable_light`
* `:sun_protection`
* `:heating_radiator`
* `:heating_floor`
* `:heating_switching_variable`
* `:heating_continuous_variable`

## Custom method

If the type of group address is not defined in the ETS project, then the tool cannot guess which group address is e.g. for On/Off, or for dimming value.

If no building with **Functions** was created in the project, then the tool cannot guess which set of Group Addresses refer to the same HA device.

It is possible to add this information using the third argument (custom script) which can add missing information, based, for example, on group address name.

For example, I used to use a naming convention like: `<room>:<object>:<type>` before using ETS features, and the custom script could guess the missing data type from `<type>`, and then group addresses into devices based on `<room>` and `<object>`.

The optional post-processing function can modify the analyzed structure:

* It can delete objects, or create objects.
* It can add fields in the `:custom` properties:

  * `ha_init` : initialize the HA object with some values
  * `ha_type` : force the entity type in HA
  * `ha_address_type` : define the use for the group address
  * `linknx_disp_name` : set the description of group address in `linknx`

The function can use any information such as fields of the object, or description or name of group address for that.

The function is called with the `ConfigurationImporter` as argument, from which property `data` is used.

Typically, the name of group addresses can be used if a specific naming convention was used.
Or, if group addresses were defined using a specific convention: for example in a/b/c a is the type of action, b is the identifier of device...

## Linknx

`linknx` does not have an object concept, and needs only group addresses.

## XKNX

Support is dropped for the moment, until needed, but it is close enough to HA.

## Reporting issues

Include the version of ETS used and logs.
