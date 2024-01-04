# frozen_string_literal: true

# This example of custom method uses group address description to figure out devices
PREFIX = {
  'ECL_On/Off '      => { address_type: 'address', domain: 'light' },
  # 'ECL_VAL ' => {address_type: 'todo1',domain: 'light'},
  # 'État_ECL_VAL ' => {address_type: 'todo2',domain: 'light'},
  'État_ECL_On/Off ' => { address_type: 'state_address', domain: 'light' },
  'ECL_VAR '         => { address_type: 'brightness_address', domain: 'light' },
  'Pos._VR_% '       => { address_type: 'position_address', domain: 'cover' },
  'M/D_VR '          => { address_type: 'move_long_address', domain: 'cover' }
  # 'État_Pos._VR_% ' => {address_type: 'todo',domain: 'cover'},
  # 'T°_Amb.  ' => {address_type: 'type4',domain: 'light'},
  # 'Dét._Prés. ' => {address_type: 'type4',domain: 'light'},
}.freeze

# generate
def fix_objects(generator)
  # loop on group addresses
  generator.all_ga_ids.each do |ga_id|
    # ignore if the group address is already in an object
    next unless generator.ga_object_ids(ga_id).empty?
    ga_data = generator.group_address_data(ga_id)
    obj_name = nil
    object_domain = nil
    # try to guess an object name from group address name
    PREFIX.each do |prefix, info|
      next unless ga_data[:name].start_with?(prefix)
      obj_name = ga_data[:name][prefix.length..]
      ga_data[:ha][:address_type] = info[:address_type]
      object_domain = info[:domain]
      break
    end
    if obj_name.nil?
      warn("unknown:#{ga_data}")
      next
    end

    # use name as id, so that we can easily group GAs
    obj_id = obj_name

    if generator.object(obj_id).nil?
      generator.add_object(
        obj_id, {
          name:  obj_name,
          type:  :custom, # unknown, so assume just switch
          floor: 'unknown floor',
          room:  'unknown room',
          ha:    { domain: object_domain }
        }
      )
    end
    generator.associate(ga_id: ga_id, object_id: obj_id)
  end
end
