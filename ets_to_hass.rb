#!/usr/bin/env ruby
# Laurent Martin
# translate configuration from ETS into KNXWeb and Home Assistant
require 'zip'
require 'xmlsimple'
require 'yaml'
require 'json'
require 'pp'
require 'logger'

class ConfigurationImporter
  ETS_EXT='.knxproj'
  private_constant :ETS_EXT
  def self.my_dig(entry_point,path)
    path.each do |n|
      entry_point=entry_point[n]
      raise "ERROR: cannot find level #{n} in xml" if entry_point.nil?
      # because we use ForceArray
      entry_point=entry_point.first
      raise "ERROR: expect array with one element in #{n}" if entry_point.nil?
    end
    return entry_point
  end

  # generate identifier without special characters
  def self.name_to_id(str,repl='_')
    return str.gsub(/[^A-Za-z]+/,repl)
  end

  def process_ga(ga)
    # build object for each group address
    group={
      id:               ga['Id'].freeze,                              # ETS: internal id
      name:             ga['Name'].freeze,                            # ETS: name field
      description:      ga['Description'].freeze,                     # ETS: description field
      address:          @addrparser.call(ga['Address'].to_i).freeze,  # group address as string "x/y/z" : we assume 3 levels
      datapoint:        nil,                                          # datapoint type as string "x.00y"
      linknx_disp_name: ga['Name'],                                   # (modifiable by special) linknx: display name of group address (no < or >)
      objs:             [],                                           # objects ids, it may be in multiple objects
      custom:           {}                                            # modified by lambda
    }
    if ga['DatapointType'].nil?
      @logger.warn("no datapoint type for #{group[:address]} : #{group[:name]}, group address is skipped")
      return
    end
    # parse datapoint for easier use
    if m = ga['DatapointType'].match(/^DPST-([0-9]+)-([0-9]+)$/)
      # datapoint type as string x.00y
      group[:datapoint]=sprintf('%d.%03d',m[1].to_i,m[2].to_i) # no freeze
    else
      @logger.warn("cannot parse datapoint : #{ga['DatapointType']}, group is skipped")
      return
    end
    # Index is the internal Id in xml file
    @knx[:ga][group[:id]]=group.freeze
    @logger.debug("group: #{group}")
  end

  def process_group_ranges(gr)
    gr['GroupRange'].each{|sgr|process_group_ranges(sgr)} if gr.has_key?('GroupRange')
    gr['GroupAddress'].each{|ga|process_ga(ga)} if gr.has_key?('GroupAddress')
  end

  # from knx_master.xml in project file
  KNOWN_FUNCTIONS=[:custom,:switchable_light,:dimmable_light,:sun_protection,:heating_radiator,:heating_floor,:dimmable_light,:sun_protection,:heating_switching_variable,:heating_continuous_variable]

  def process_space(space,info=nil)
    @logger.debug("#{space['Type']}: #{space['Name']}")
    info=info.nil? ? {} : info.dup
    if space.has_key?('Space')
      # get floor when we have it
      info[:floor]=space['Name'] if space['Type'].eql?('Floor')
      space['Space'].each{|s|process_space(s,info)}
    end
    # Functions are objects
    if space.has_key?('Function')
      # we assume the object is directly in the room
      info[:room]=space['Name']
      # loop on group addresses
      space['Function'].each do |f|
        if m=f['Type'].match(/^FT-([0-9])$/)
          type=KNOWN_FUNCTIONS[m[1].to_i]
        else
          raise "unknown function type: #{f['Type']}"
        end
        o={
          name:   f['Name'].freeze,
          type:   type,
          ga:     f['GroupAddressRef'].map{|g|g['RefId'].freeze},
          custom: {} # custom values
        }.merge(info)
        # store reference to this object in the GAs
        o[:ga].each do |g|
          next unless @knx[:ga].has_key?(g)
          @knx[:ga][g][:objs].push(f['Id'])
        end
        @logger.debug("function: #{o}")
        @knx[:ob][f['Id']]=o.freeze
      end
    end
  end

  def initialize(file,lambdafile=nil)
    raise "ETS file must end with #{ETS_EXT}" unless file.end_with?(ETS_EXT)
    lambdafile=eval(File.read(lambdafile)) unless lambdafile.nil?
    @knx={ga: {}, ob: {}}
    @logger = Logger.new(STDERR)
    xml_project=xml_data=nil
    # read ETS5 file and get project file
    Zip::File.open(file) do |zip_file|
      zip_file.each do |entry|
        case entry.name
        when %r{P-[^/]+/project\.xml$};xml_project=XmlSimple.xml_in(entry.get_input_stream.read, {'ForceArray' => true})
        when %r{P-[^/]+/0\.xml$};xml_data=XmlSimple.xml_in(entry.get_input_stream.read, {'ForceArray' => true})
        end
      end
    end
    proj_info=xml_project['Project'].first['ProjectInformation'].first
    @logger.info("Using project #{proj_info['Name']}, address style: #{proj_info['GroupAddressStyle']}")
    # set group address formatter according to project settings
    @addrparser=case proj_info['GroupAddressStyle']
    when 'Free';lambda{|a|a.to_s}
    when 'TwoLevel';lambda{|a|[(a>>11)&31,a&2047].join('/')}
    when 'ThreeLevel';lambda{|a|[(a>>11)&31,(a>>8)&7,a&255].join('/')}
    else raise "Error: #{proj_info['GroupAddressStyle']}"
    end
    installation=self.class.my_dig(xml_data,['Project','Installations','Installation'])
    # process group ranges
    process_group_ranges(self.class.my_dig(installation,['GroupAddresses','GroupRanges']))
    process_space(self.class.my_dig(installation,['Locations']))
    # give a chance to fix project specific information
    lambdafile.call(@knx) unless lambdafile.nil?
  end

  def homeass
    knx={}
    @knx[:ob].values.each do |o|
      new_obj=o[:custom].has_key?(:ha_init) ? o[:custom][:ha_init] : {}
      new_obj['name']=o[:name] unless new_obj.has_key?('name')
      # compute object type
      ha_obj_type=o[:custom][:ha_type] || case o[:type]
      when :switchable_light,:dimmable_light;'light'
      when :sun_protection;'cover'
      when :custom,:heating_continuous_variable,:heating_floor,:heating_radiator,:heating_switching_variable
        @logger.warn("function type not implemented for #{o[:name]}/#{o[:room]}: #{o[:type]}");next
      else @logger.error("function type not supported for #{o[:name]}/#{o[:room]}, please report: #{o[:type]}");next
      end
      # process all group addresses in function
      o[:ga].each do |garef|
        ga=@knx[:ga][garef]
        next if ga.nil?
        # find property name based on datapoint
        ha_property=case ga[:datapoint]
        when '1.001';new_obj.has_key?('address') ? 'state_address' : 'address' # switch on/off or state
        when '1.008';'move_long_address' # up/down
        when '1.010';'stop_address' # stop
        when '1.011';'state_address' # switch state
        when '3.007';next # dimming control: used by buttons
        when '5.001' # percentage 0-100
          # custom code tells what is state
          case ha_obj_type
          when 'light'; new_obj.has_key?('brightness_address') ? 'brightness_state_address' : 'brightness_address'
          when 'cover'; 'position_address'
          else nil
          end
        else
          @logger.warn("no mapping for group address: #{ga[:address]} : #{ga[:name]}: #{ga[:datapoint]}")
          next
        end
        if ha_property.nil?
          @logger.warn("unexpected nil property name for #{ga} : #{o}")
          next
        end
        @logger.warn("overwriting value #{ha_property} : #{new_obj[ha_property]} with #{ga[:address]}") if new_obj.has_key?(ha_property)
        new_obj[ha_property]=ga[:address]
      end
      knx[ha_obj_type]=[] unless knx.has_key?(ha_obj_type)
      knx[ha_obj_type].push(new_obj)
    end
    #
    @knx[:ga].values.select{|ga|ga[:objs].empty?}.each do |ga|
      @logger.error("group not in object: #{ga[:address]}: Create custom object in lambda if needed , or use ETS to create functions")
    end
    return {'knx'=>knx}.to_yaml
  end

  # https://sourceforge.net/p/linknx/wiki/Object_Definition_section/
  def linknx
    return @knx[:ga].values.map do |ga|
      %Q(        <object type="#{ga[:datapoint]}" id="id_#{ga[:address].gsub('/','_')}" gad="#{ga[:address]}" init="request">#{ga[:linknx_disp_name]}</object>)
    end.join("\n")
  end

end

raise "Usage: #{$0} etsprojectfile.knxproj format [special]" unless ARGV.length >= 2 and ARGV.length  <= 3
format=ARGV.shift.to_sym
infile=ARGV.shift
raise 'no such format' unless [:homeass,:linknx].include?(format)
special=ARGV.shift
$stdout.write(ConfigurationImporter.new(infile,special).send(format))
