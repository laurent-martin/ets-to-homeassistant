lambda do |o|
  # by convetion name is: <room>:<object>:<type>
  parts=o[:ets_name].split(':')
  raise "[#{o[:ets_name]}] does not follow convention: <location>:<object>:<type>" if !parts.length.eql?(3)
  object_location=parts[0]
  object_simple_name=parts[1]
  group_type=parts[2]
  o[:p_object_id]=[object_location,object_simple_name].map{|i| ConfigurationImporter.name_to_id(i)}.join('.')
  o[:p_group_name]=o[:p_group_name].gsub(':',' ').strip

  # manual fix, shall not happen
  if o[:ets_dpst_xstr].nil?
    puts "WARN: non datapoint type for #{o[:ets_addr_str]} : #{o[:ets_name]}"
    case group_type
    when 'ON/OFF'; o[:ets_dpst_xstr]='DPST-1-1'
    when 'variation'; o[:ets_dpst_xstr]='DPST-3-7'
    when 'valeur'; o[:ets_dpst_xstr]='DPST-5-1'
    end
  end
  if o[:ets_dpst_xstr].eql?('DPST-1-8')
    raise %Q{name error "#{o[:ets_name]}": VR or Pergola} unless object_simple_name.start_with?('VR ') or object_simple_name.start_with?('Pergola ')
    raise %Q{type error "#{o[:ets_name]}": Pulse} unless group_type.eql?('Pulse')
    # specific to me
    o[:ets_dpst_xstr]='DPST-1-1'
    # Pulse means push button, remove from name
    o[:p_group_name]=o[:p_group_name].gsub(/Pulse$/,'').strip
  end
  # TODO: find a common way to detect type
  # this part is specific to me: group 0 and 1 are lights, and 3/4 are switches
  case o[:ets_addr_arr][1]
  when 0,1; o[:p_ha_type]='light'
  when 3,4; o[:p_ha_type]='switch'
  else raise "unknown group: #{o[:ets_addr_arr][1]}"
  end
end
