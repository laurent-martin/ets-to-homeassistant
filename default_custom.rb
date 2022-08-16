# frozen_string_literal: true

# generate
lambda do |knxconf|
  # get data to manipulate
  knx = knxconf.data
  objid = 0
  knx[:ga].each do |id, ga|
    next unless ga[:objs].empty?

    # generate a dummy object with a single group address
    knx[:ob][objid] = {
      name: ga[:name],
      type: :custom, # unknown, so assume just switch
      ga: [id],
      floor: 'unknown floor',
      room: 'unknown room',
      custom: { ha_type: 'switch' } # custom values
    }
    # prepare next object identifier
    objid += 1
  end
end
