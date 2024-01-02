# frozen_string_literal: true

# I can detect HA object address type based on group address
GROUP_TO_ADDR_TYPE = {
  '/1/' => 'state_address',
  '/4/' => 'brightness_state_address'
}.freeze

# Sample "custom" code for KNX configuration
def fix_objects(obj)
  group_addresses = obj.data[:ga]
  objects = obj.data[:ob]
  # 1: manipulate objects: fix special blinds...
  # prepare lists of objects to add and delete
  o_delete = [] # id of objects to delete
  o_new = {} # objects to add
  # loop on objects to find blinds
  # my setup is special, each blind has 2 GA: one for up, one for down, but I need to use those as 2 objects
  objects.each do |obj_id, object|
    # manage in special manner my blinds, identified by "pulse" in address group name
    next unless object[:type].eql?(:sun_protection) && group_addresses[object[:ga].first][:name].end_with?(':Pulse')

    # split this object into 2: so delete old object
    o_delete.push(obj_id)
    # create one object per GA
    object[:ga].each do |gid|
      # get direction of ga based on name
      direction = case group_addresses[gid][:name]
                  when /Montee/ then 'Montee'
                  when /Descente/ then 'Descente'
                  else raise "error: #{group_addresses[gid][:name]}"
                  end
      # fix datapoint for ga (I have set up/down in ETS)
      group_addresses[gid][:datapoint].replace('1.001')
      # create new object
      o_new["#{obj_id}_#{direction}"] = {
        name:   "#{object[:name]} #{direction}",
        type:   :custom, # simple switch
        ga:     [gid],
        floor:  object[:floor],
        room:   object[:room],
        custom: { ha_type: 'switch' } # custom values
      }
    end
  end
  # delete redundant objects
  o_delete.each { |i| objects.delete(i) }
  # add split objects
  objects.merge!(o_new)
  # 2: set specific parameters for "normal" blinds
  objects.each_value do |object|
    if object[:type].eql?(:sun_protection)
      # set my specific times
      object[:custom][:ha_init] ||= {}
      object[:custom][:ha_init].merge!({ 'travelling_time_down' => 59,
                                         'travelling_time_up'   => 59 })
    end
    # TODO: check if needed
    object[:custom][:ha_type] = 'switch' if object[:type].eql?(:custom)
  end
  # 3- I use x/1/x for state and x/4/x for brightness state
  group_addresses.each_value do |ga|
    GROUP_TO_ADDR_TYPE.each do |pattern, addr_type|
      ga[:custom][:ha_address_type] = addr_type if ga[:address].include?(pattern)
    end
  end
end
