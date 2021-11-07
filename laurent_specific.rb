def process_object(ga)
  # by convetion name is: <room>:<object>:<type>
  parts=ga[:ets_name].split(':')
  raise "[#{ga[:ets_name]}] does not follow convention: <location>:<object>:<type>" unless parts.length.eql?(3)
  object_location=parts[0]
  object_simple_name=parts[1]
  group_type=parts[2]
  ga[:p_object_id]=[object_location,object_simple_name].map{|i| ConfigurationImporter.name_to_id(i)}.join('.')
  # used by linknx: change into spaces for easier read
  ga[:p_group_name]=ga[:p_group_name].gsub(':',' ').strip

  case ga[:ets_dpst_str]
  when '1.001'
    raise "#{ga} expecting ON/OFF" unless group_type.eql?('ON/OFF')
    #puts object_simple_name
    ga[:ha_type_force]='switch' if object_simple_name.start_with?('VMC')
    ga[:ha_type_force]='switch' if object_simple_name.start_with?('Sonnette')
  when '3.007'
    raise "inconsistent type" unless group_type.eql?('variation')
  when '5.001'
    raise "#{ga} expecting valeur" unless ['valeur','Position'].include?(group_type)
  when '1.008'
    # 1.008: up/down , but Pulse: special case
    if group_type.eql?('Pulse')
      # Pulse means push button, remove from name
      ga[:p_group_name]=ga[:p_group_name].gsub(/Pulse$/,'').strip
      raise %Q{name error "#{ga[:ets_name]}": VR} unless object_simple_name.start_with?('VR ')
      # specific to me
      ga[:ets_dpst_str]='1.001'
      ga[:ha_type_force]='switch'
      puts "Fixing Pulse: #{ga}"
    end
  end
end

lambda { |ga| process_object(ga)}
