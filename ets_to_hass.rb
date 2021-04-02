#!/usr/bin/env ruby
require 'zip'
require 'xmlsimple'
require 'yaml'

class ConfigurationImporter
  ETS_EXT='.knxproj'
  attr_reader :knx_groups
  def initialize(file)
    raise "ETS file must end with #{ETS_EXT}" unless file.end_with?(ETS_EXT)
    @baseout=File.basename(file,ETS_EXT)
    @knx_groups=[]
    navigate=nil
    # read ETS5 file and get project file
    Zip::File.open(file) do |zip_file|
      zip_file.glob('*/0.xml').each do |entry|
        navigate=XmlSimple.xml_in(entry.get_input_stream.read, {'ForceArray' => true})
      end
    end
    # dig to get only group addresses
    ['Project','Installations','Installation','GroupAddresses','GroupRanges','GroupRange'].each do |n|
      navigate=navigate[n]
      raise "ERROR: cannot find level #{n} in xml" if navigate.nil?
      # because we use ForceArray
      navigate=navigate.first
      raise "ERROR: expect array with one element in #{n}" if navigate.nil?
    end
    # loop on each group range
    navigate['GroupRange'].each do |group|
      addresses=group['GroupAddress']
      # ignore if group is empty
      next if addresses.nil?
      # process each group address
      addresses.each do |e|
        o={
          ets_name:       e['Name'],
          ets_dpst_xstr:  e['DatapointType'],
          ets_addr_int:   e['Address'].to_i,
          ets_descr:      e['Description'],
          p_group_name:   e['Name'], # linknx: group name (can be modified by special code)
          p_object_id:    self.class.name_to_id(e['Name']), # ha and xknx: unique identifier of object which this group is about. e.g. kitchen.ceiling_light
          p_ha_type:      'light',   # ha: object type, by default assume light
        }
        a=o[:ets_addr_int]
        o[:ets_addr_arr]=[(a>>12)&15,(a>>8)&15,a&255]
        o[:ets_addr_str]=o[:ets_addr_arr].join("/")

        self.class.specific_processing_for_my_project(o)

        if o[:ets_dpst_xstr].nil?
          puts "WARN: no datapoint type for #{o[:ets_addr_str]} : #{o[:ets_name]}, group is skipped"
        else
          if m = o[:ets_dpst_xstr].match(/^DPST-([0-9]+)-([0-9]+)$/)
            o[:ets_dpst_arr]=[m[1].to_i,m[2].to_i]
            o[:ets_dpst_str]=sprintf("%d.%03d",o[:ets_dpst_arr].first,o[:ets_dpst_arr].last)
            @knx_groups.push(o)
          else
            puts "WARN: cannot parse datapoint : #{o[:ets_dpst_xstr]}, group is skipped"
          end
        end
      end
    end
  end

  def self.specific_processing_for_my_project(o)
  end

  def self.name_to_id(str)
    return str.gsub(/[^A-Za-z]+/,'_')
  end

  def homeass
    # set empty hash for key knx
    conf=init_hash(['knx'])
    # initialize hass types
    knx=conf['knx']=init_hash(['binary_sensor','climate','cover','light','notify','scene','sensor','switch','weather'])
    @knx_groups.each do |o|
      k=knx[o[:p_ha_type]][o[:p_object_id]]||={}
      # TODO: add types here
      address_attribute=case o[:ets_dpst_str]
      when '1.001'; 'address'
      when '3.007'; 'brightness_address'
      when '5.001'; 'brightness_state_address'
      end
      if address_attribute.nil?
        puts "WARN: no mapping for group address: #{o[:ets_addr_str]} : #{o[:ets_name]}: #{o[:ets_dpst_str]}"
      else
        k[address_attribute]=o[:ets_addr_str]
      end
    end
    cleanup_hash(knx)
    knx.keys.each do |g|
      knx[g]=knx[g].keys.inject([]){|m,n|knx[g][n]['name']=n;m.push(knx[g][n]);m}
    end
    return conf.to_yaml
  end

  def init_hash(keys)
    return keys.inject({}){|m,n|m[n]={};m}
  end

  def cleanup_hash(hash)
    hash.reject!{|k,v|v.empty?}
  end

  def xknx
    conf=init_hash(['general','groups'])
    conf['general']['own_address']='1.1.132'
    conf['groups']=init_hash(['binary_sensor','climate','cover','light','sensor','switch','time','weather'])
    conf['groups']['time']['General.Time']='9/0/1'
    lights=conf['groups']['light']
    @knx_groups.each do |o|
      x=lights[o[:p_object_id]]||={}
      # TODO: add types here
      address_attribute=case o[:ets_dpst_str]
      when '1.001'; 'group_address_switch'
      when '3.007'; 'group_address_brightness'
      when '5.001'; 'group_address_brightness_state'
      end
      if address_attribute.nil?
        puts "WARN: no mapping for group address for type #{o[:ets_dpst_str]} : #{o[:ets_addr_str]} : #{o[:ets_name]}"
      else
        x[address_attribute]=o[:ets_addr_str]
      end
    end
    cleanup_hash(conf['groups'])
    return conf.to_yaml
  end

  # https://sourceforge.net/p/linknx/wiki/Object_Definition_section/
  def linknx
    return @knx_groups.map do |o|
      linknx_id="id_#{o[:ets_addr_arr].join('_')}"
      linknx_type=o[:ets_dpst_str]
      linknx_type='5.xxx' if linknx_type.start_with?('5.')
      %Q(        <object type="#{linknx_type}" id="#{linknx_id}" gad="#{o[:ets_addr_str]}" init="request">#{o[:p_group_name]}</object>)
    end.join("\n")
  end

  def generate(data,ext)
    File.write("#{@baseout}.#{ext}",data)
  end
end

if ENV.has_key?('SPECIAL')
  load(ENV['SPECIAL'])
else
  puts "no specific code, set env var SPECIAL to load specific code"
end

raise "Usage: #{$0} etsprojectfile.knxproj" unless ARGV.length.eql?(1)
config=ConfigurationImporter.new(ARGV.first)
#puts config.knx_groups
config.generate(config.xknx,'xknx.yaml')
config.generate(config.homeass,'ha.yaml')
config.generate(config.linknx,'linknx.xml')
