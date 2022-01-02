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
    a=ga['Address'].to_i
    # build object for each group address
    group={
      id:               ga['Id'].freeze,                              # ETS: internal id
      name:             ga['Name'].freeze,                            # ETS: name field
      description:      ga['Description'].freeze,                     # ETS: description field
      address:          [(a>>12)&15,(a>>8)&15,a&255].join('/').freeze,# group address as string "x/y/z" : we assume 3 levels
      datapoint:        nil,                                          # datapoint type as string "x.00y"
      linknx_disp_name: ga['Name'],                                   # (modifiable by special) linknx: display name of group address (no < or >)
      objs:             [],                                           # it may be in multiple objects
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
  end

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
        o={
          name:   f['Name'].freeze,
          type:   f['Type'].freeze, # type of function : FT-x
          ga:     f['GroupAddressRef'].map{|g|g['RefId'].freeze},
          custom: {} # custom values
        }.merge(info)
        # store reference to this object in the GAs
        o[:ga].each do |g|
          @knx[:ga][g][:objs].push(f['Id'])
        end
        @logger.debug("func #{o}")
        @knx[:ob][f['Id']]=o.freeze
      end
    end
  end

  def initialize(file,lambdafile=nil)
    raise "ETS file must end with #{ETS_EXT}" unless file.end_with?(ETS_EXT)
    lambdafile=eval(File.read(lambdafile)) unless lambdafile.nil?
    @knx={ga: {}, ob: {}}
    @logger = Logger.new(STDERR)
    xml_root=nil
    # read ETS5 file and get project file
    Zip::File.open(file) do |zip_file|
      zip_file.glob('*/0.xml').each do |entry|
        xml_root=XmlSimple.xml_in(entry.get_input_stream.read, {'ForceArray' => true})
      end
    end
    installation=self.class.my_dig(xml_root,['Project','Installations','Installation'])
    # loop on each group range (assume 3 levels)
    self.class.my_dig(installation,['GroupAddresses','GroupRanges'])['GroupRange'].each do |group_range_1|
      ranges=group_range_1['GroupRange']
      next if ranges.nil?
      ranges.each do |range|
        addresses=range['GroupAddress']
        next if addresses.nil?
        # process each group address
        addresses.each do |ga|
          process_ga(ga)
        end
      end # loop GA
    end
    process_space(self.class.my_dig(installation,['Locations']))
    # give a chance to fix project specific information
    lambdafile.call(@knx) unless lambdafile.nil?
    #PP.pp(self.class.my_dig(installation,['Locations']))
    #PP.pp(@knx)
  end

  def homeass
    knx={}
    @knx[:ob].values.each do |o|
      new_obj=o[:custom].has_key?(:ha_init) ? o[:custom][:ha_init] : {}
      new_obj['name']=o[:name] unless new_obj.has_key?('name')
      # add functions here
      ha_obj_type=case o[:type]
      when 'FT-0';'switch'
      when 'FT-1';'light'
      when 'FT-6';'light' # dimmable
      when 'FT-7';'cover'
      else @logger.error("function type not supported, please report: #{f['Type']}");next
      end
      o[:ga].each do |garef|
        ga=@knx[:ga][garef]
        case ga[:datapoint]
        when '1.001' # switch on/off
          p='address'
        when '1.008' # up/down
          p='move_long_address'
        when '1.010' # stop
          p='stop_address'
        when '1.011' # switch state
          p='state_address'
        when '3.007' # dimming control: used by buttons
          next
        when '5.001' # percentage 0-100
          # custom code tells what is state
          p=case ha_obj_type
          when 'light'; new_obj.has_key?('brightness_address') ? 'brightness_state_address' : 'brightness_address'
          when 'cover'; 'position_address'
          else nil
          end
        else
          @logger.warn("no mapping for group address: #{ga[:address]} : #{ga[:name]}: #{ga[:datapoint]}")
          next
        end
        if p.nil?
          @logger.warn("unexpected nil property name for #{ga} : #{o}")
          next
        end
        @logger.warn("overwriting value #{p} : #{new_obj[p]} with #{ga[:address]}") if new_obj.has_key?(p)
        new_obj[p]=ga[:address]
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
infile=ARGV.shift
format=ARGV.shift.to_sym
raise 'no such format' unless [:homeass,:linknx].include?(format)
special=ARGV.shift
$stdout.write(ConfigurationImporter.new(infile,special).send(format))
