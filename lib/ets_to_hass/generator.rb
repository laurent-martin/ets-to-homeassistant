# frozen_string_literal: true

require 'zip'
require 'xmlsimple'
require 'yaml'
require 'json'
require 'logger'
require 'ets_to_hass/string_colors'
require 'ets_to_hass/info'

module EtsToHass
  # Import ETS project file and generate configuration for Home Assistant and KNXWeb
  class Generator
    # extension of ETS project file
    ETS_EXT = '.knxproj'
    # converters of group address integer address into representation
    GROUP_ADDRESS_PARSERS = {
      Free:       ->(a) { a.to_s },
      TwoLevel:   ->(a) { [(a >> 11) & 31, a & 2047].join('/') },
      ThreeLevel: ->(a) { [(a >> 11) & 31, (a >> 8) & 7, a & 255].join('/') }
    }.freeze
    # KNX functions described in knx_master.xml in project file.
    # map index parsed from "FT-x" to recognizable identifier
    ETS_FUNCTIONS_INDEX_TO_NAME =
      %i[custom switchable_light dimmable_light sun_protection heating_radiator heating_floor
         dimmable_light sun_protection heating_switching_variable heating_continuous_variable].freeze
    private_constant :ETS_EXT, :ETS_FUNCTIONS_INDEX_TO_NAME

    # class methods
    class << self
      # helper function to dig through keys, knowing that we used ForceArray
      def dig_xml(entry_point, path)
        raise "ERROR: wrong entry point: #{entry_point.class}, expect Hash" unless entry_point.is_a?(Hash)

        path.each do |n|
          raise "ERROR: cannot find level #{n} in xml, have #{entry_point.keys.join(',')}" unless entry_point.key?(n)

          entry_point = entry_point[n]
          # because we use ForceArray
          entry_point = entry_point.first
          raise "ERROR: expect array with one element in #{n}" if entry_point.nil?
        end
        entry_point
      end

      def function_type_to_name(ft_type)
        m = ft_type.match(/^FT-([0-9])$/)
        raise "ERROR: Unknown function type: #{ft_type}" if m.nil?

        ETS_FUNCTIONS_INDEX_TO_NAME[m[1].to_i]
      end

      def specific_defined?
        defined?(fix_objects).eql?('method')
      end
    end

    attr_reader :data

    def initialize(file, options = {})
      # command line options
      @opts = options
      # parsed data: ob: objects (ETS functions), ga: group addresses
      @data = { ob: {}, ga: {} }
      # log to stderr, so that redirecting stdout captures only generated data
      @logger = Logger.new($stderr)
      @logger.level = @opts.key?(:trace) ? @opts[:trace] : Logger::INFO
      @logger.debug("options: #{@opts}")
      # read .knxproj file xml into project variable
      project = read_file(file)
      # find out address style
      proj_info = self.class.dig_xml(project[:info], %w[Project ProjectInformation])
      @group_addr_style = (@opts[:addr] || proj_info['GroupAddressStyle']).to_sym
      raise "Error: no such style #{@group_addr_style} in #{GROUP_ADDRESS_PARSERS.keys}" if GROUP_ADDRESS_PARSERS[@group_addr_style].nil?

      @logger.info("Using project #{proj_info['Name']}, address style: #{@group_addr_style}")
      # locate main node in xml
      installation = self.class.dig_xml(project[:data], %w[Project Installations Installation])
      # process group ranges: fill @data[:ga]
      process_group_ranges(self.class.dig_xml(installation, %w[GroupAddresses GroupRanges]))
      # process group ranges: fill @data[:ob] (for 2 versions of ETS which have different tags?)
      process_space(self.class.dig_xml(installation, ['Locations']), 'Space') if installation.key?('Locations')
      process_space(self.class.dig_xml(installation, ['Buildings']), 'BuildingPart') if installation.key?('Buildings')
      @logger.warn('No building information found.') if @data[:ob].keys.empty?
      return unless @opts[:specific]
      # load specific code
      load(@opts[:specific])
      raise "no method found in #{specific}" unless self.class.specific_defined?
    end

    def warning(entity, name, message)
      @logger.warn("#{entity.red} #{name.green} #{message}")
    end

    # format the integer group address to string in desired style (e.g. 1/2/3)
    def parse_group_address(group_address)
      GROUP_ADDRESS_PARSERS[@group_addr_style].call(group_address.to_i).freeze
    end

    # Read both project.xml and 0.xml
    # @return Hash {info: xml data, data: xml data}
    def read_file(file)
      raise "ETS file must end with #{ETS_EXT}" unless file.end_with?(ETS_EXT)

      project = {}
      # read ETS5 file and get project file
      Zip::File.open(file) do |zip_file|
        zip_file.each do |entry|
          case entry.name
          when %r{P-[^/]+/project\.xml$}
            project[:info] = XmlSimple.xml_in(entry.get_input_stream.read, { 'ForceArray' => true })
          when %r{P-[^/]+/0\.xml$}
            project[:data] = XmlSimple.xml_in(entry.get_input_stream.read, { 'ForceArray' => true })
          end
        end
      end
      raise "Did not find project information or data (#{project.keys})" unless project.keys.sort.eql?(%i[data info])

      project
    end

    # process group range recursively and find addresses
    def process_group_ranges(group)
      group['GroupRange'].each { |sgr| process_group_ranges(sgr) } if group.key?('GroupRange')
      group['GroupAddress'].each { |group_address| process_ga(group_address) } if group.key?('GroupAddress')
    end

    # process a group address
    def process_ga(group_address)
      # build object for each group address
      group = {
        name:        group_address['Name'].freeze, # ETS: name field
        description: group_address['Description'].freeze, # ETS: description field
        address:     parse_group_address(group_address['Address']), # group address as string. e.g. "x/y/z" depending on project style
        datapoint:   nil, # datapoint type as string "x.00y"
        objs:        [], # objects ids, it may be in multiple objects
        custom:      {} # prepared to be potentially modified by specific code
      }
      if group_address['DatapointType'].nil?
        warning(group[:address], group[:name], 'no datapoint type for address group, to be defined in ETS, skipping')
        return
      end
      # parse datapoint for easier use
      if (m = group_address['DatapointType'].match(/^DPST-([0-9]+)-([0-9]+)$/))
        # datapoint type as string x.00y
        group[:datapoint] = format('%d.%03d', m[1].to_i, m[2].to_i) # no freeze
      else
        warning(group[:address], group[:name],
                "Cannot parse data point type: #{group_address['DatapointType']} (DPST-x-x), skipping")
        return
      end
      # Index is the internal Id in xml file
      @data[:ga][group_address['Id'].freeze] = group.freeze
      @logger.debug("group: #{group}")
    end

    # process locations recursively, and find functions
    # @param space the current space
    # @param info current location information: floor, room
    def process_space(space, space_type, info = nil)
      @logger.debug(">sname>#{space['Type']}: #{space['Name']}")
      @logger.debug(">space>#{space}")
      info = info.nil? ? {} : info.dup
      # process building sub spaces
      if space.key?(space_type)
        # get floor when we have it
        info[:floor] = space['Name'] if space['Type'].eql?('Floor')
        space[space_type].each { |s| process_space(s, space_type, info) }
      end
      # Functions are objects
      return unless space.key?('Function')

      # we assume the object is directly in the room
      info[:room] = space['Name']
      # loop on group addresses
      space['Function'].each do |f|
        @logger.debug("function #{f}")
        # ignore functions without group address
        next unless f.key?('GroupAddressRef')

        # the object
        o = {
          name:   f['Name'].freeze,
          type:   self.class.function_type_to_name(f['Type']),
          ga:     f['GroupAddressRef'].map { |g| g['RefId'].freeze },
          custom: {} # custom values
        }.merge(info)
        # store reference to this object in the GAs
        o[:ga].each { |g| @data[:ga][g][:objs].push(f['Id']) if @data[:ga].key?(g) }
        @logger.debug("function: #{o}")
        @data[:ob][f['Id']] = o.freeze
      end
    end

    # map ETS function to home assistant object type
    # see https://www.home-assistant.io/integrations/knx/
    def map_ets_function_to_ha_type(ets_func)
      # map FT-x type to home assistant type
      case ets_func[:type]
      when :switchable_light, :dimmable_light then 'light'
      when :sun_protection then 'cover'
      when :custom, :heating_continuous_variable, :heating_floor, :heating_radiator, :heating_switching_variable
        @logger.warn("#{ets_func[:room].red} #{ets_func[:name].green} function type #{ets_func[:type].to_s.blue} not implemented")
        nil
      else @logger.error("#{ets_func[:room].red} #{ets_func[:name].green} function type #{ets_func[:type].to_s.blue} not supported, please report")
           nil
      end
    end

    # map datapoint to home assistant type
    # see https://www.home-assistant.io/integrations/knx/
    def map_ets_datapoint_to_ha_type(group_address, ha_obj_type)
      case group_address[:datapoint]
      when '1.001' then 'address' # switch on/off or state
      when '1.008' then 'move_long_address' # up/down
      when '1.010' then 'stop_address' # stop
      when '1.011' then 'state_address' # switch state
      when '3.007'
        @logger.debug("#{group_address[:address]}(#{ha_obj_type}:#{group_address[:datapoint]}:#{group_address[:name]}): ignoring datapoint")
        nil # dimming control: used by buttons
      when '5.001' # percentage 0-100
        # custom code tells what is state
        case ha_obj_type
        when 'light' then 'brightness_address'
        when 'cover' then 'position_address'
        else
          warning(group_address[:address], group_address[:name], "#{group_address[:datapoint]} expects: light or cover, not #{ha_obj_type.magenta}")
          nil
        end
      else
        warning(group_address[:address], group_address[:name], "un-managed datapoint #{group_address[:datapoint].blue} (#{ha_obj_type.magenta})")
        nil
      end
    end

    # This creates the Home Assistant configuration in variable ha_config
    # based on @data coming from ETS
    # and optionally modified by specific code in apply_specific
    def generate_homeass
      # First, apply user-provided specific code
      if self.class.specific_defined?
        @logger.info("Applying fix code from #{@opts[:specific]}")
        fix_objects(self)
      end
      # This will be the YAML for HA
      ha_config = {}
      # warn of group addresses that will not be used (you can fix in specific code)
      @data[:ga].values.select { |ga| ga[:objs].empty? }.each do |ga|
        warning(ga[:address], ga[:name],
                'Group not in object: use ETS to create functions or use specific code')
      end
      # Generate devices from either functions in ETS, or from specific code
      @data[:ob].each_value do |o|
        # HA configuration object, either empty or from specific code
        ha_device = o[:custom].key?(:ha_init) ? o[:custom][:ha_init] : {}
        # default name
        ha_device['name'] = @opts[:full_name] ? "#{o[:name]} #{o[:room]}" : o[:name] unless ha_device.key?('name')
        # compute object type, this is the section in HA configuration (switch, light, etc...)
        ha_obj_type = o[:custom][:ha_type] || map_ets_function_to_ha_type(o)
        if ha_obj_type.nil?
          warning(o[:name], o[:room], "function type not detected #{o[:type].to_s.blue}")
          next
        end
        # process all group addresses in function
        o[:ga].each do |group_address_reference|
          # get this group information
          ga = @data[:ga][group_address_reference]
          if ga.nil?
            @logger.error("#{o[:name].red} #{o[:room].green} (#{o[:type].to_s.magenta}) group address #{group_address_reference} not found, skipping")
            next
          end
          # find property name based on datapoint
          ha_address_type = ga[:custom][:ha_address_type] || map_ets_datapoint_to_ha_type(ga, ha_obj_type)
          if ha_address_type.nil?
            warning(ga[:address], ga[:name],
                    "address type not detected #{ga[:datapoint].blue} / #{ha_obj_type.magenta}, skipping")
            next
          end
          if ha_device.key?(ha_address_type)
            @logger.error("#{ga[:address].red} #{ga[:name].green} (#{ha_obj_type.magenta}:#{ga[:datapoint]}) #{ha_address_type} already set with #{ha_device[ha_address_type]}, skipping")
            next
          end
          ha_device[ha_address_type] = ga[:address]
        end
        ha_config[ha_obj_type] = [] unless ha_config.key?(ha_obj_type)
        # check name is not duplicated, as name is used to identify the object
        @logger.warn("#{ha_device['name'].red} object name is duplicated") if ha_config[ha_obj_type].any? { |v| v['name'].casecmp?(ha_device['name']) }
        ha_config[ha_obj_type].push(ha_device)
      end
      return { 'knx' => ha_config }.to_yaml if @opts[:ha_knx]

      ha_config.to_yaml
    end

    # https://sourceforge.net/p/linknx/wiki/Object_Definition_section/
    def generate_linknx
      @data[:ga].values.sort { |a, b| a[:address] <=> b[:address] }.map do |ga|
        linknx_name = ga[:custom][:linknx_name] || ga[:name]
        %Q(        <object type="#{ga[:datapoint]}" id="id_#{ga[:address].gsub('/',
                                                                               '_')}" gad="#{ga[:address]}" init="request">#{linknx_name}</object>)
      end.join("\n")
    end
  end
end
