# frozen_string_literal: true

# I can detect HA object address type based on group address
GROUP_TO_ADDR_TYPE = {
  '/1/' => 'state_address',
  '/4/' => 'brightness_state_address'
}.freeze
DATAPOINT_TO_ADDR_TYPE = {
  '3.007' => :ignore
}.freeze

# Laurent's specific code for KNX configuration
def fix_objects(generator)
  # loop on objects to find blinds
  # I have two types of blinds: normal and special
  # "normal" blinds have a single GA for up/down
  # "special" blinds have 2 GA: one for up, one for down, and are managed like a switch, so I declare 2 objects for them
  generator.all_object_ids.each do |obj_id|
    object = generator.object(obj_id)
    # customs are switches
    object[:ha][:domain] ||= 'switch' if object[:type].eql?(:custom)
    # need only to manage covers/blinds
    next unless object[:type].eql?(:sun_protection)
    # manage in special manner my blinds, identified by "pulse" in address group name
    if group_address_data(object[:ga_ids].first)[:name].end_with?(':Pulse')
      # delete current object: will be split into 2
      generator.delete_object(obj_id)
      # loop on GA for this object (one for up and one for down)
      object[:ga_ids].each do |ga_id|
        ga_data = group_address_data(ga_id)
        # get direction of GA based on name
        direction =
          case ga_data[:name]
          when /Montee/ then 'Montee'
          when /Descente/ then 'Descente'
          else raise "error: #{ga_data[:name]}"
          end
        # fix datapoint for GA (I have set up/down in ETS)
        ga_data[:datapoint].replace('1.001')
        new_object_id = "#{obj_id}_#{direction}"
        # create new object
        generator.add_object(
          new_object_id,
          {
            name:  "#{object[:name]} #{direction}",
            type:  :custom, # simple switch
            floor: object[:floor],
            room:  object[:room],
            ha:    { domain: 'switch' }
          }
        )
        generator.associate(ga_id: ga_id, object_id: new_object_id)
      end
    else
      # set my specific times
      object[:ha].merge!(
        { 'travelling_time_down' => 59,
          'travelling_time_up'   => 59 }
      )
    end
  end
  # lights: I use x/1/x for state and x/4/x for brightness state
  generator.all_ga_ids.each do |ga_id|
    ga_data = generator.group_address_data(ga_id)
    GROUP_TO_ADDR_TYPE.each do |pattern, addr_type|
      ga_data[:ha][:address_type] = addr_type if ga_data[:address].include?(pattern)
    end
    DATAPOINT_TO_ADDR_TYPE.each do |pattern, addr_type|
      ga_data[:ha][:address_type] = addr_type if ga_data[:datapoint].eql?(pattern)
    end
  end
end
