# frozen_string_literal: true

def fix_objects(obj)
  # group addresses
  group_addresses = obj.data[:ga]
  # objects
  objects = obj.data[:ob]
  # generate new objects sequentially
  new_object_id = 0
  # loop on group addresses
  group_addresses.each do |id, ga|
    # group address already assigned to an object
    next unless ga[:objs].empty?

    # generate a dummy object with a single group address
    objects[new_object_id] = {
      name:   ga[:name],
      type:   :custom, # unknown, so assume just switch
      ga:     [id],
      floor:  'unknown floor',
      room:   'unknown room',
      custom: { ha_type: 'switch' } # custom values
    }
    # prepare next object identifier
    new_object_id += 1
  end
end
