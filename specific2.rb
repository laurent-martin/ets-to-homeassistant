# frozen_string_literal: true

# This example of custom method uses group address description to figure out devices
PREFIX = {
  'ECL_On/Off '      => { ha_address_type: 'address', ha_type: 'light' },
  # 'ECL_VAL ' => {ha_address_type: 'todo1',ha_type: 'light'},
  # 'État_ECL_VAL ' => {ha_address_type: 'todo2',ha_type: 'light'},
  'État_ECL_On/Off ' => { ha_address_type: 'state_address', ha_type: 'light' },
  'ECL_VAR '         => { ha_address_type: 'brightness_address', ha_type: 'light' },
  'Pos._VR_% '       => { ha_address_type: 'position_address', ha_type: 'cover' },
  'M/D_VR '          => { ha_address_type: 'move_long_address', ha_type: 'cover' }
  # 'État_Pos._VR_% ' => {ha_address_type: 'todo',ha_type: 'cover'},
  # 'T°_Amb.  ' => {ha_address_type: 'type4',ha_type: 'light'},
  # 'Dét._Prés. ' => {ha_address_type: 'type4',ha_type: 'light'},
}

# generate
lambda do |knxconf|
  # get data to manipulate
  knx = knxconf.data
  knx[:ga].each do |gaid, ga|
    # ignore if the group address is already in object
    next unless ga[:objs].empty?

    obj_name = nil
    ha_type = nil
    # try to guess an object name from group address name
    PREFIX.each do |prefix, data|
      next unless ga[:name].start_with?(prefix)
      obj_name = ga[:name][prefix.length..]
      ga[:custom][:ha_address_type] = data[:ha_address_type]
      ha_type = data[:ha_type]
      break
    end
    if obj_name.nil?
      warn("unknown:#{ga}")
      next
    end

    # is this an existing object ?
    objid = obj_name
    object = knx[:ob][objid]
    if object.nil?
      object = knx[:ob][objid] = {
        name:   obj_name,
        type:   :custom, # unknown, so assume just switch
        ga:     [],
        floor:  'unknown floor',
        room:   'unknown room',
        custom: { ha_type: ha_type } # custom values
      }
    end
    object[:ga].push(gaid)
    ga[:objs].push(objid)
  end
end
