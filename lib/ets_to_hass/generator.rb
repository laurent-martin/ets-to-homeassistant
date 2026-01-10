# frozen_string_literal: true

require 'zip'
require 'xmlsimple'
require 'yaml'
require 'json'
require 'logger'
require 'fileutils'
require 'ets_to_hass/string_colors'
require 'ets_to_hass/info'
require 'io/console'
require 'base64'

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
    # KNX functions described in knx_master.xml in project file, in <FunctionTypes>
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

    def initialize(file, options = {})
      # command line options
      @opts = options
      # parsed data: ob: objects (ETS functions), ga: group addresses
      @objects = {}
      @group_addresses = {}
      @associations = []
      # log to stderr, so that redirecting stdout captures only generated data
      @logger = Logger.new($stderr)
      @logger.level = @opts.key?(:trace) ? @opts[:trace] : Logger::INFO
      @logger.debug("options: #{@opts}")
      # read .knxproj file xml into project variable
      # project = @opts.key?(:password) ? read_file(file, password: @opts[:password]) : read_file(file)
      project = read_file(file)

      # find out address style
      proj_info = self.class.dig_xml(project[:info], %w[Project ProjectInformation])
      @group_addr_style = (@opts[:addr] || proj_info['GroupAddressStyle']).to_sym
      raise "Error: no such style #{@group_addr_style} in #{GROUP_ADDRESS_PARSERS.keys}" if GROUP_ADDRESS_PARSERS[@group_addr_style].nil?

      @logger.info("Using project #{proj_info['Name']}, address style: #{@group_addr_style}")
      # locate main node in xml
      installation = self.class.dig_xml(project[:data], %w[Project Installations Installation])
      # process group ranges: fill @group_addresses
      process_group_ranges(self.class.dig_xml(installation, %w[GroupAddresses GroupRanges]))
      # process group ranges: fill @objects (for 2 versions of ETS which have different tags?)
      process_space(self.class.dig_xml(installation, ['Locations']), 'Space') if installation.key?('Locations')
      process_space(self.class.dig_xml(installation, ['Buildings']), 'BuildingPart') if installation.key?('Buildings')
      @logger.warn('No building information found.') if @objects.keys.empty?
      return unless @opts[:specific]
      unless File.exist?(@opts[:specific])
        @logger.warn("Specific code file #{@opts[:specific]} not found, creating generic one.")
        FileUtils.cp(File.join(File.dirname(__FILE__), 'specific', 'generic.rb'), @opts[:specific])
      end
      # load specific code
      load(@opts[:specific])
      raise "no method found in #{@opts[:specific]}" unless self.class.specific_defined?
    end

    def warning(entity, name, message)
      @logger.warn("#{entity.red} #{name.green} #{message}")
    end

    # format the integer group address to string in desired style (e.g. 1/2/3)
    def parse_group_address(group_address)
      GROUP_ADDRESS_PARSERS[@group_addr_style].call(group_address.to_i).freeze
    end

    def read_file(zip_path, password: '')
      project_data = nil
      zero_data = nil

      inner_zip_re     = /\AP-[\w]+\.zip\z/
      project_path_re  = %r{\AP-[\w]+/project\.xml\z}
      zero_path_re     = %r{\AP-[\w]+/0\.xml\z}

      Zip::File.open(zip_path) do |zf|
        # Case A: direct folder P-xxxxx/
        proj_entry = zf.entries.find { |e| e.name =~ project_path_re && !e.directory? }
        zero_entry = zf.entries.find { |e| e.name =~ zero_path_re    && !e.directory? }
        if proj_entry && zero_entry
          project_data = zf.read(proj_entry.name)
          zero_data    = zf.read(zero_entry.name)
        end

        # Case B: nested P-xxxxx.zip (encrypted)
        if project_data.nil? || zero_data.nil?
          inner_entry = zf.entries.find { |e| e.name =~ inner_zip_re && !e.directory? }
          if inner_entry
            inner_bytes = zf.read(inner_entry.name)
            # try a sequence of decrypters until one works
            IO.console.puts 'Your KNX project is password protected!'
            password = IO.console.getpass('Enter password: ')

            decrypters = []
            begin
              decrypters << Zip::AESDecrypter.new(ets6_encrypt_password(password), Zip::AESEncryption::STRENGTH_256_BIT)
              decrypters << Zip::AESDecrypter.new(ets6_encrypt_password(password), Zip::AESEncryption::STRENGTH_128_BIT)
            rescue NameError
              # AES classes not available (older rubyzip), skip AES variants
            end
            begin
              decrypters << Zip::TraditionalDecrypter.new(password)
            rescue NameError
            end

            decrypters << nil

            last_error = nil
            decrypters.each do |dec|
              project_data, zero_data = read_two_from_inner_zip(inner_bytes, decrypter: dec, need_project: project_data.nil?, need_zero: zero_data.nil?)
              break if project_data && zero_data
            rescue StandardError => e
              # Bad password / wrong decrypter leads to errors on get_next_entry/read; try next decrypter
              last_error = "Wrong password or the ETS uses an unknown encryption method (supported are AES256, AES128, ZipCrypto-Deflate):\n #{e}"
              next
            end

            raise(last_error || RuntimeError.new('Failed to read encrypted inner zip')) if project_data.nil? || zero_data.nil?
          end
        end
      end

      raise 'project.xml not found' unless project_data
      raise '0.xml not found' unless zero_data

      project = {
        info: XmlSimple.xml_in(project_data, { 'ForceArray' => true }),
        data: XmlSimple.xml_in(zero_data, { 'ForceArray' => true })
      }

      raise "Did not find project information or data (#{project.keys})" unless project.keys.sort.eql?(%i[data info])
      project
    end

    def read_two_from_inner_zip(bytes, decrypter:, need_project:, need_zero:)
      proj = nil
      zero = nil
      # Use InputStream so we can pass decrypter; read sequentially
      Zip::InputStream.open(StringIO.new(bytes), decrypter: decrypter) do |input|
        loop do
          entry = input.get_next_entry
          break unless entry
          if need_project && entry.name == 'project.xml'
            proj = input.read
          elsif need_zero && entry.name == '0.xml'
            zero = input.read
          else
            # consume entry to move stream forward
            input.read
          end
          break if (!need_project || proj) && (!need_zero || zero)
        end
      end
      [proj, zero]
    end

    def ets6_encrypt_password(password_utf8)
      # ETS6 derives from UTF-16LE bytes of the entered password

      utf16le_bytes = password_utf8.encode('UTF-16LE')
      key = OpenSSL::KDF.pbkdf2_hmac(
        utf16le_bytes,
        salt:       '21.project.ets.knx.org'.b,
        iterations: 65_536,
        length:     32,
        hash:       'sha256'
      )
      Base64.strict_encode64(key)
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
        ha:          { address_type: nil } # prepared to be potentially modified by specific code
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
      @group_addresses[group_address['Id'].freeze] = group.freeze
      @logger.debug("group: #{group}")
    end

    # process locations recursively, and find functions
    # @param space the current space
    # @param space_type the type of space: Space or BuildingPart
    # @param info current location information: floor, room
    def process_space(space, space_type, info = nil)
      info = info.nil? ? {} : info.dup
      @logger.debug("space: #{space['Type']}: #{space['Name']} (#{info})")
      # process building sub spaces
      if space.key?(space_type)
        # get floor when we have it
        info[:floor] = space['Name'] if space['Type'].eql?('Floor')
        # recursively process sub-spaces
        space[space_type].each { |s| process_space(s, space_type, info) }
      end
      # Functions are objects
      return unless space.key?('Function')

      # we assume the object is directly in the room
      info[:room] = space['Name']
      # loop on group addresses
      space['Function'].each do |ets_function|
        # @logger.debug("function #{ets_function}")
        # ignore functions without group address
        next unless ets_function.key?('GroupAddressRef')

        # the ETS object, created from ETS function
        ets_object = {
          name: ets_function['Name'].freeze,
          type: self.class.function_type_to_name(ets_function['Type']),
          ha:   { domain: nil } # hone assistant values
        }.merge(info)
        add_object(ets_function['Id'], ets_object)
        ets_function['GroupAddressRef'].map { |g| g['RefId'].freeze }.each do |group_address_id|
          associate(ga_id: group_address_id, object_id: ets_function['Id'])
        end
        @logger.debug("function: #{ets_object}")
      end
    end

    # map ETS function to home assistant object type
    # see https://www.home-assistant.io/integrations/knx/
    def map_ets_function_to_ha_object_category(ets_func)
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
    def map_ets_datapoint_to_ha_address_type(group_address, ha_object_domain)
      case group_address[:datapoint]
      when '1.001' then 'address' # switch on/off or state
      when '1.008' then 'move_long_address' # up/down
      when '1.010' then 'stop_address' # stop
      when '1.011' then 'state_address' # switch state
      when '3.007'
        @logger.debug("#{group_address[:address]}(#{ha_object_domain}:#{group_address[:datapoint]}:#{group_address[:name]}): ignoring datapoint")
        nil # dimming control: used by buttons
      when '5.001' # percentage 0-100
        # user-provided code tells what is state
        case ha_object_domain
        when 'light' then 'brightness_address'
        when 'cover' then 'position_address'
        else
          warning(group_address[:address], group_address[:name], "#{group_address[:datapoint]} expects: light or cover, not #{ha_object_domain.magenta}")
          nil
        end
      else
        warning(group_address[:address], group_address[:name], "un-managed datapoint #{group_address[:datapoint].blue} (#{ha_object_domain.magenta})")
        nil
      end
    end

    # @param ga_id group address id
    # @returns array of objects for this group id
    def ga_object_ids(ga_id)
      @associations.select { |a| a[:ga_id].eql?(ga_id) }.map { |a| a[:object_id] }
    end

    def all_object_ids
      @objects.keys
    end

    # @param object_id object id
    # @returns array of group addresses for this object
    def object_ga_ids(object_id)
      @associations.select { |a| a[:object_id].eql?(object_id) }.map { |a| a[:ga_id] }
    end

    def all_ga_ids
      @group_addresses.keys
    end

    def associate(ga_id:, object_id:)
      @associations.push({ ga_id: ga_id, object_id: object_id })
    end

    def delete_object(object_id)
      @objects.delete(object_id)
      @associations.delete_if { |a| a[:object_id].eql?(object_id) }
    end

    def add_object(object_id, object)
      # objects will not be modified, this shall be what comes from ETS only, use field `ha` for specific code
      @objects[object_id] = object.freeze
    end

    def object(object_id)
      @objects[object_id]
    end

    def group_address_data(ga_id)
      @group_addresses[ga_id]
    end

    # This creates the Home Assistant configuration in variable ha_config
    # based on data coming from ETS
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
      all_ga_ids.each do |ga_id|
        next unless ga_object_ids(ga_id).empty?
        ga_data = group_address_data(ga_id)
        warning(ga_data[:address], ga_data[:name], 'Group not in object: use ETS to create functions or use specific code')
      end
      # Generate devices from either functions in ETS, or from specific code
      all_object_ids.each do |object_id|
        ets_object = object(object_id)
        # compute object domain, this is the section in HA configuration (switch, light, etc...)
        ha_object_domain = ets_object[:ha].delete(:domain) || map_ets_function_to_ha_object_category(ets_object)
        if ha_object_domain.nil?
          warning(ets_object[:name], ets_object[:room], "#{ets_object[:type].to_s.blue}: function type not detected, skipping")
          next
        end
        # add domain to config, if necessary
        ha_config[ha_object_domain] ||= []
        # HA configuration object, either empty or initialized in specific code
        ha_device = ets_object[:ha]
        # default name
        ha_device['name'] ||= @opts[:full_name] ? "#{ets_object[:name]} #{ets_object[:room]}" : ets_object[:name]
        # check name is not duplicated, as name is used to identify the object
        if ha_config[ha_object_domain].any? { |v| v['name'].casecmp?(ha_device['name']) }
          @logger.warn("#{ha_device['name'].red} object name is duplicated (check ETS objects and rooms)")
        end
        # add object to configuration
        ha_config[ha_object_domain].push(ha_device)
        # process all group addresses in ETS function (object)
        object_ga_ids(object_id).each do |group_address_id|
          # get this group information
          ga_data = group_address_data(group_address_id)
          if ga_data.nil?
            @logger.error("#{ets_object[:name].red} #{ets_object[:room].green} (#{ets_object[:type].to_s.magenta}): #{group_address_id}: group address not found, skipping")
            next
          end
          # find HA property name based on datapoint
          ha_address_type = ga_data[:ha][:address_type] || map_ets_datapoint_to_ha_address_type(ga_data, ha_object_domain)
          next if ha_address_type.eql?(:ignore)
          if ha_address_type.nil?
            warning(ga_data[:address], ga_data[:name],
                    "#{ga_data[:datapoint].blue} / #{ha_object_domain.magenta}: address type not detected, skipping")
            next
          end
          if ha_device.key?(ha_address_type)
            @logger.error("#{ga_data[:address].red} #{ga_data[:name].green} (#{ha_object_domain.magenta}:#{ga_data[:datapoint]}) #{ha_address_type} already set with #{ha_device[ha_address_type]}, skipping")
            # TODO: support passive addresses ?
            next
          end
          # ok, we have the property name and group address
          ha_device[ha_address_type] = ga_data[:address]
        end
      end
      if @opts[:sort_by_name]
        @logger.info('Sorting by name')
        ha_config.each_value { |v| v.sort_by! { |o| o['name'] } }
      end
      # add knx level, if user asks for it
      ha_config = { 'knx' => ha_config } if @opts[:ha_knx]
      ha_config.to_yaml
    end

    # https://sourceforge.net/p/linknx/wiki/Object_Definition_section/
    def generate_linknx
      @group_addresses.values.sort { |a, b| a[:address] <=> b[:address] }.map do |ga_data|
        linknx_name = ga_data[:name]
        linknx_id = "id_#{ga_data[:address].gsub('/', '_')}"
        %Q(        <object type="#{ga_data[:datapoint]}" id="#{linknx_id}" gad="#{ga_data[:address]}" init="request">#{linknx_name}</object>)
      end.join("\n")
    end
  end
end
