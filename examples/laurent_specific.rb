# frozen_string_literal: true

# Sample "custom" code for KNX configuration

class EtsToHass
  def apply_specific
    @logger.info('Applying custom code: laurent')
    # 1: manipulate objects: fix special blinds...
    # prepare lists of objects to add and delete
    o_delete = [] # id of objects to delete
    o_new = {} # objects to add
    # loop on objects to find blinds
    @data[:ob].each do |obj_id, object|
      # manage in special manner my blinds, identified by "pulse" in address group name
      next unless object[:type].eql?(:sun_protection) && @data[:ga][object[:ga].first][:name].end_with?(':Pulse')

      # split this object into 2: so delete old object
      o_delete.push(obj_id)
      # create one obj per GA
      object[:ga].each do |gid|
        # get direction of ga based on name
        direction = case @data[:ga][gid][:name]
                    when /Montee/ then 'Montee'
                    when /Descente/ then 'Descente'
                    else raise "error: #{@data[:ga][gid][:name]}"
                    end
        # fix datapoint for ga (I have set up/down in ETS)
        @data[:ga][gid][:datapoint].replace('1.001')
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
    o_delete.each { |i| @data[:ob].delete(i) }
    # add split objects
    @data[:ob].merge!(o_new)
    # 2: set unique name when needed
    @data[:ob].each do |_unused_id, object|
      # set name as room + function
      # object[:custom][:ha_init] = { 'name' => "#{object[:name]} #{object[:room]}" }
      # set my specific parameters
      if object[:type].eql?(:sun_protection)
        object[:custom][:ha_init] ||= {}
        object[:custom][:ha_init].merge!({ 'travelling_time_down' => 59,
                                           'travelling_time_up'   => 59 })
      end
      object[:custom][:ha_type] = 'switch' if object[:type].eql?(:custom)
    end
    # 3- I use x/1/x for state and x/4/x for brightness state
    @data[:ga].each_value do |ga|
      ga[:custom][:ha_address_type] = 'state_address' if ga[:address].include?('/1/')
      ga[:custom][:ha_address_type] = 'brightness_state_address' if ga[:address].include?('/4/')
    end
    # 4- manage group addresses without object
    error = false
    @data[:ga].values.select { |ga| ga[:objs].empty? }.each do |ga|
      error = true
      warn("group not in object: #{ga[:address]}")
    end
    warn('Error found in custom code, see above') if error
  end
end
