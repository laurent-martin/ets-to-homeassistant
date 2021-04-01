#!/usr/bin/env ruby
require 'zip'
require 'xmlsimple'
require 'yaml'

class ConfigurationImporter
  ETS_EXT='.knxproj'
  attr_reader :obj_list
  def initialize(file)
    raise "ETS file must end with #{ETS_EXT}" unless file.end_with?(ETS_EXT)
    @baseout=File.basename(file,ETS_EXT)
    @obj_list=[]
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
      raise "error at #{n}" if navigate.nil?
      # because we use ForceArray
      navigate=navigate.first
      raise "error at first #{n}" if navigate.nil?
    end
    # loop on each group range
    navigate['GroupRange'].each do |group|
      addresses=group['GroupAddress']
      # ignore if group is empty
      next if addresses.nil?
      # process each group address
      addresses.each do |e|
        o={
          name_ets: e['Name'],
          type_ets: e['DatapointType'],
          addr_ets: e['Address'].to_i
        }
        a=o[:addr_ets]
        o[:addr_arr]=[(a>>12)&15,(a>>8)&15,a&255]
        o[:addr_str]=o[:addr_arr].join("/")
        #        o.each do |k,v|
        #          if v.nil?
        #            raise "error: field #{k} is nil for #{o[:addr_str]} : #{o[:name_ets]}"
        #          end
        #        end
        if not o[:type_ets].nil? and m = o[:type_ets].match(/^DPST-([0-9]+)-([0-9]+)$/)
          o[:dpst]=[m[1].to_i,m[2].to_i]
        else
          puts "WARN: cannot match type [#{o[:type_ets]}] for #{o[:addr_str]} : #{o[:name_ets]}"
        end
        @obj_list.push(o)
      end
    end
  end

  # extract location information from ETS name
  def extract_name_info
    @obj_list.each do |o|
      # This part is specific to naming
      parts=o[:name_ets].split(':')
      raise "[#{o[:name_ets]}] does not follow convention: <location>:<object>:<type>" if !parts.length.eql?(3)
      o[:my_location]=parts[0]
      o[:my_object]=parts[1]
      o[:additional_info]=parts[2]
      if o[:type_ets].nil?
        case o[:additional_info]
        when 'ON/OFF'; o[:type_ets]='DPST-1-1'
        when 'variation'; o[:type_ets]='DPST-3-7'
        when 'valeur'; o[:type_ets]='DPST-5-1'
        end
      end
    end
  end

  # add specific code here
  def fix_special_conditions
    @obj_list.each do |o|
      if o[:type_ets].eql?('DPST-1-8')
        raise "name error #{o[:my_object]}" unless o[:my_object].start_with?('VR ') or o[:my_object].start_with?('Pergola ')
        raise "name error #{o[:my_object]}" unless o[:additional_info].eql?('Pulse')
        # specific to me
        o[:type_ets]='DPST-1-1'
        # Pulse means push button, remove from name
        o[:name_ets].gsub!(/:Pulse$/,'')
      end
    end
  end

  def homeass
    conf=init_hash(['knx'])
    knx=conf['knx']=init_hash(['binary_sensor','climate','cover','light','notify','scene','sensor','switch','weather'])
    @obj_list.each do |o|
      ha_obj_name=[o[:my_location],o[:my_object]].map{|i| i.gsub(/[^A-Za-z]+/,'_')}.join('.')
      ha_obj_type=case o[:addr_arr][1]
      when 0,1; 'light'
      when 3,4; 'switch'
      else raise "unknown group: #{o[:addr_arr][1]}"
      end
      k=knx[ha_obj_type][ha_obj_name]||={}
      case o[:type_ets]
      when 'DPST-1-1'; k['address']=o[:addr_str]
      when 'DPST-3-7'; k['brightness_address']=o[:addr_str]
      when 'DPST-5-1'; k['brightness_state_address']=o[:addr_str]
      when NilClass; raise "no type for #{o}"
      else raise "unknown type #{o} "
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
    @obj_list.each do |o|
      ha_obj_name=[o[:my_location],o[:my_object]].map{|i| i.gsub(/[^A-Za-z]+/,'_')}.join('.')
      x=lights[ha_obj_name]||={}
      case o[:type_ets]
      when 'DPST-1-1'; x['group_address_switch']=o[:addr_str]
      when 'DPST-3-7'; x['group_address_brightness']=o[:addr_str]
      when 'DPST-5-1'; x['group_address_brightness_state']=o[:addr_str]
      when NilClass; raise "no type for #{o}"
      else raise "unknown type #{x[:type_ets]} "
      end
    end
    cleanup_hash(conf['groups'])
    return conf.to_yaml
  end

  def linknx
    return @obj_list.map do |o|
      linknx_id="id_#{o[:addr_arr].join('_')}"
      linknx_descr=o[:name_ets].gsub(':',' ').strip
      linknx_type=case o[:type_ets]
      when 'DPST-1-1'; '1.001'
      when 'DPST-3-7'; '3.007'
      when 'DPST-5-1'; '5.xxx'
      when NilClass; raise "no type for #{o} for #{o[:addr_str]}"
      else raise "unknown type #{o[:type_ets]} for #{o[:addr_str]}"
      end
      %Q(        <object type="#{linknx_type}" id="#{linknx_id}" gad="#{o[:addr_str]}" init="request">#{linknx_descr}</object>)
    end.join("\n")
  end

  def generate(data,ext)
    File.write("#{@baseout}.#{ext}",data)
  end
end

raise "Usage: #{$0} etsprojectfile.knxproj" unless ARGV.length.eql?(1)
config=ConfigurationImporter.new(ARGV.first)
config.extract_name_info
config.fix_special_conditions
#puts config.obj_list
config.generate(config.xknx,'xknx.yaml')
config.generate(config.homeass,'ha.yaml')
config.generate(config.linknx,'linknx.xml')
