#!/usr/bin/env ruby
require 'zip'
require 'xmlsimple'
require 'yaml'

class ConfigurationImporter
  attr_accessor :obj_list
  def initialize(file)
    @obj_list=[]
    navigate=nil
    # read file
    Zip::File.open(file) do |zip_file|
      zip_file.glob('*/0.xml').each do |entry|
        navigate=XmlSimple.xml_in(entry.get_input_stream.read, {'ForceArray' => true})
      end
    end
    # get only group addresses
    ['Project','Installations','Installation','GroupAddresses','GroupRanges','GroupRange'].each do |n|
      navigate=navigate[n]
      raise "error at #{n}" if navigate.nil?
      navigate=navigate.first
      raise "error at first #{n}" if navigate.nil?
    end
    navigate['GroupRange'].each do |group|
      addresses=group['GroupAddress']
      next if addresses.nil?
      addresses.each do |i|
        o={
          id: i['Name'].downcase.gsub(/[^a-z]+/,'_'),
          name: i['Name'].gsub(/\s+/,' '),
          type: i['DatapointType'],
          addr_num: i['Address'].to_i
        }
        a=o[:addr_num]
        o[:addr_arr]=[(a>>12)&15,(a>>8)&15,a&255]
        o[:addr_str]=o[:addr_arr].join("/")
        if o[:type].nil?
          puts("no type for #{o[:name]}, trying from name")
          # correlate type from name  (specific to me)
          o[:type]='DPST-1-1' if o[:name].upcase.end_with?('ON/OFF') or o[:name].include?(' VR ')
          o[:type]='DPST-3-7' if o[:name].end_with?('ariation')
          o[:type]='DPST-5-1' if o[:name].end_with?('aleur')
        end
        case o[:type]
        when 'DPST-1-1'; o[:ltype]='1.001'
        when 'DPST-3-7'; o[:ltype]='3.007'
        when 'DPST-5-1'; o[:ltype]='5.xxx'
        when NilClass; raise "no type for #{i}"
        else raise "unknown type #{o[:type]} "
        end
        o[:obj_name]=i[:name]
        o[:obj_type]=nil
        case o[:addr_arr][1]
        when 0
          o[:obj_name]=o[:name].gsub(' ON/OFF','')
          o[:obj_type]='light'
        when 1
          o[:obj_name]=o[:name].gsub(' ON/OFF','').gsub(' valeur','').gsub(' variation','')
          o[:obj_type]='light'
        when 3,4
          #.gsub('Montee ','').gsub('Descente ','')
          o[:obj_name]=o[:name].gsub('VR ','')
          o[:obj_type]='switch'
        else raise "unknown group: #{o[:addr_arr][1]}"
        end
        o[:obj_name].gsub!(/[^a-zA-Z]/,'.')
        @obj_list.push(o)
      end
    end
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
    @obj_list.each do |i|
      o=lights[i[:obj_name]]||={}
      case i[:type]
      when 'DPST-1-1'; o['group_address_switch']=i[:addr_str]
      when 'DPST-3-7'; o['group_address_brightness']=i[:addr_str]
      when 'DPST-5-1'; o['group_address_brightness_state']=i[:addr_str]
      when NilClass; raise "no type for #{i}"
      else raise "unknown type #{o[:type]} "
      end
    end
    cleanup_hash(conf['groups'])
    return conf.to_yaml
  end

  def homeass
    conf=init_hash(['knx'])
    knx=conf['knx']=init_hash(['binary_sensor','climate','cover','light','notify','scene','sensor','switch','weather'])
    @obj_list.each do |i|
      o=knx[i[:obj_type]][i[:obj_name]]||={}
      case i[:type]
      when 'DPST-1-1'; o['address']=i[:addr_str]
      when 'DPST-3-7'; o['brightness_address']=i[:addr_str]
      when 'DPST-5-1'; o['brightness_state_address']=i[:addr_str]
      when NilClass; raise "no type for #{i}"
      else raise "unknown type #{o[:type]} "
      end
    end
    cleanup_hash(knx)
    knx.keys.each do |g|
      knx[g]=knx[g].keys.inject([]){|m,n|knx[g][n]['name']=n;m.push(knx[g][n]);m}
    end
    return conf.to_yaml
  end

  def linknx
    return @obj_list.map do |i|
      %Q(        <object type="#{i[:ltype]}" id="#{i[:id]}" gad="#{i[:addr_str]}" init="request">#{i[:name]}</object>)
    end.join("\n")
  end
end

config=ConfigurationImporter.new(ARGV.first)
#puts config.obj_list
#puts config.xknx
puts config.homeass
#puts config.linknx

