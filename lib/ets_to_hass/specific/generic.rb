# frozen_string_literal: true

# This example of custom method creates one object per group address.
# It's not right, but it's simple.

def fix_objects(generator)
  # generate new objects sequentially
  new_object_id = 0
  # loop on group addresses
  generator.all_ga_ids.each do |ga_id|
    # skip if group address already assigned to an object
    next unless generator.ga_object_ids(ga_id).empty?
    ga_data = generator.group_address_data(ga_id)
    # generate a dummy object with a single group address
    generator.add_object(
      new_object_id, {
        name:  ga_data[:name],
        type:  :custom, # unknown type of object, switch ?
        floor: 'unknown floor',
        room:  'unknown room',
        ha:    { domain: 'switch' }
      }
    )
    generator.associate(ga_id: ga_id, object_id: new_object_id)
    # prepare next object identifier
    new_object_id += 1
  end
end
