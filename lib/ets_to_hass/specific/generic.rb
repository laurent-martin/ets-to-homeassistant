# frozen_string_literal: true

def fix_objects(obj)
  gas = obj.data[:ga]
  obs = obj.data[:ob]
  # generate new objects sequentially
  new_object_id = 0
  # loop on group addresses
  gas.each do |id, ga|
    # group address already assigned to an object
    next unless ga[:objs].empty?

    # generate a dummy object with a single group address
    obs[new_object_id] = {
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
