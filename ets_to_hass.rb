#!/usr/bin/env ruby
# Laurent Martin
# translate configuration from ETS into KNXWeb and Home Assistant
require 'zip'
require 'xmlsimple'
require 'yaml'
require 'json'

class ConfigurationImporter
  ETS_EXT='.knxproj'
  private_constant :ETS_EXT
  def initialize(file,lambdafile=nil)
    raise "ETS file must end with #{ETS_EXT}" unless file.end_with?(ETS_EXT)
    @knx_groups=[]
    entry_point=nil
    # read ETS5 file and get project file
    Zip::File.open(file) do |zip_file|
      zip_file.glob('*/0.xml').each do |entry|
        entry_point=XmlSimple.xml_in(entry.get_input_stream.read, {'ForceArray' => true})
      end
    end
    # dig to get only group addresses
    ['Project','Installations','Installation','GroupAddresses','GroupRanges'].each do |n|
      entry_point=entry_point[n]
      raise "ERROR: cannot find level #{n} in xml" if entry_point.nil?
      # because we use ForceArray
      entry_point=entry_point.first
      raise "ERROR: expect array with one element in #{n}" if entry_point.nil?
    end
    lambdafile=eval(File.read(lambdafile)) unless lambdafile.nil?
    # loop on each group range
    entry_point['GroupRange'].each do |group_range_1|
      ranges=group_range_1['GroupRange']
      next if ranges.nil?
      ranges.each do |range|
        addresses=range['GroupAddress']
        next if addresses.nil?
        # process each group address
        addresses.each do |ga|
          # build object for each group address
          o={
            ets_name:       ga['Name'],
            ets_descr:      ga['Description'],
            p_group_name:   ga['Name'], # (modifiable by special) linknx: group name
            p_object_id:    self.class.name_to_id(ga['Name']), # (modifiable by special) ha and xknx: unique identifier of object which this group is about. e.g. kitchen.ceiling_light
          }
          a=ga['Address'].to_i
          o[:ets_addr_str]=[(a>>12)&15,(a>>8)&15,a&255].join("/")   # group address as string "x/y/z"

          if ga['DatapointType'].nil?
            puts "WARN: no datapoint type for #{o[:ets_addr_str]} : #{o[:ets_name]}, group address is skipped"
            next
          end
          # parse datapoint for easier use
          if m = ga['DatapointType'].match(/^DPST-([0-9]+)-([0-9]+)$/)
            # datapoint type as string x.00y
            o[:ets_dpst_str]=sprintf("%d.%03d",m[1].to_i,m[2].to_i)
          else
            puts "WARN: cannot parse datapoint : #{ga['DatapointType']}, group is skipped"
            next
          end
          # give a chance to do personal processing
          lambdafile.call(o) unless lambdafile.nil?

          @knx_groups.push(o)
        end
      end
    end
  end

  # generate identifier without special characters
  def self.name_to_id(str,repl='_')
    return str.gsub(/[^A-Za-z]+/,repl)
  end

  def homeass
    # index: id, value: home assistant object with type
    objects={}
    @knx_groups.each do |ga|
      o=objects[ga[:p_object_id]]
      o={'name'=>ga[:p_object_id]} if o.nil?
      # TODO: add types here
      case ga[:ets_dpst_str]
      when '1.001' # switch
        p='address'
        t='light'
      when '1.008' # up/down
        p='move_long_address'
        t='cover'
      when '1.010' # stop
        p='stop_address'
        t='cover'
      when '3.007' # dimming control
        p='brightness_address'
        t='light'
      when '5.001' # percentage 0-100
        p='brightness_state_address' if o[:type].eql?('light')
        p='position_address' if o[:type].eql?('cover')
        t=nil
      else
        puts "WARN: no mapping for group address: #{ga[:ets_addr_str]} : #{ga[:ets_name]}: #{ga[:ets_dpst_str]}"
        next
      end
      next "unexpected nil property name for #{ga} : #{o}" if p.nil?
      o[p]=ga[:ets_addr_str]
      if ! ga[:ha_type_force].nil?
        #puts "WARN: Overriding type #{ga[:p_object_id]}: #{o[:type]}" if !o[:type].eql?(ga[:ha_type_force])
        o[:type]=ga[:ha_type_force]
      elsif !t.nil?
        puts "WARN: Changing type #{ga[:p_object_id]}: #{o[:type]} -> #{t}" if !o[:type].nil? and !o[:type].eql?(t)
        o[:type]=t
      end
      objects[ga[:p_object_id]]=o
      puts "#{ga} #{o}"
    end
    knx={}
    objects.each do |k,v|
      knx[v[:type]]=[] unless knx.has_key?(v[:type])
      knx[v[:type]].push(v)
      v.delete(:type)
    end
    return {'knx'=>knx}.to_yaml
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
    @knx_groups.each do |ga|
      x=lights[ga[:p_object_id]]||={}
      # TODO: add types here
      address_attribute=case ga[:ets_dpst_str]
      when '1.001'; 'group_address_switch'
      when '3.007'; 'group_address_brightness'
      when '5.001'; 'group_address_brightness_state'
      end
      if address_attribute.nil?
        puts "WARN: no mapping for group address for type #{ga[:ets_dpst_str]} : #{ga[:ets_addr_str]} : #{ga[:ets_name]}"
      else
        x[address_attribute]=ga[:ets_addr_str]
      end
    end
    cleanup_hash(conf['groups'])
    return conf.to_yaml
  end

  # https://sourceforge.net/p/linknx/wiki/Object_Definition_section/
  def linknx
    return @knx_groups.map do |ga|
      linknx_id="id_#{ga[:ets_addr_str].gsub('/','_')}"
      linknx_type=ga[:ets_dpst_str]
      linknx_type='5.xxx' if linknx_type.start_with?('5.')
      %Q(        <object type="#{linknx_type}" id="#{linknx_id}" gad="#{ga[:ets_addr_str]}" init="request">#{ga[:p_group_name]}</object>)
    end.join("\n")
  end

end

raise "Usage: #{$0} etsprojectfile.knxproj format extension [special]" unless ARGV.length >= 3 and ARGV.length  <= 4
infile=ARGV.shift
format=ARGV.shift.to_sym
raise "no such format" unless [:xknx,:homeass,:linknx].include?(format)
outfile=ARGV.shift
special=ARGV.shift
File.write(outfile,ConfigurationImporter.new(infile,special).send(format))
