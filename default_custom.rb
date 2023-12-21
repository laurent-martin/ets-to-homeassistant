# frozen_string_literal: true

# default handling

# generate
lambda do |knx_config|
  # get data from KNX configuration, with fields: :ga and :ob
  knx = knx_config.data
  # generate new objects sequentially
  new_object_id = 0
  # loop on group addresses
  knx[:ga].each do |id, ga|
    # group address already assigned to an object
    next unless ga[:objs].empty?

    # generate a dummy object with a single group address
    knx[:ob][new_object_id] = {
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
