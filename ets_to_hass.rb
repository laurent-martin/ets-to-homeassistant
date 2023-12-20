#!/usr/bin/env ruby
# frozen_string_literal: true

# Laurent Martin
# translate configuration from ETS into KNXWeb and Home Assistant
begin
  require 'zip'
  require 'xmlsimple'
  require 'getoptlong'
  require 'yaml'
  require 'json'
  require 'logger'
rescue LoadError => e
  puts(e.backtrace.join("\n"))
  puts("Missing gems: read the manual: execute:\n\e[5mgem install bundler\nbundle install\e[0m")
  exit(1)
end

# Import ETS project file and generate configuration for Home Assistant and KNXWeb
class ConfigurationImporter
  # extension of ETS project file
  ETS_EXT = '.knxproj'
  # converters of group address integer address into representation
  GROUP_ADDRESS_PARSERS = {
    Free: ->(a) { a.to_s },
    TwoLevel: ->(a) { [(a >> 11) & 31, a & 2047].join('/') },
    ThreeLevel: ->(a) { [(a >> 11) & 31, (a >> 8) & 7, a & 255].join('/') }
  }.freeze
  # KNX functions described in knx_master.xml in project file.
  # map index parsed from "FT-x" to recognizable identifier
  ETS_FUNCTIONS = %i[custom switchable_light dimmable_light sun_protection heating_radiator heating_floor
                     dimmable_light sun_protection heating_switching_variable heating_continuous_variable].freeze
  private_constant :ETS_EXT, :ETS_FUNCTIONS

  attr_reader :data

  def initialize(file, options = {})
    # set to true if the resulting yaml starts at the knx key
    @opts = options
    # parsed data: ob: objects, ga: group addresses
    @data = { ob: {}, ga: {} }
    # log to stderr, so that redirecting stdout captures only generated data
    @logger = Logger.new($stderr)
    @logger.level = @opts.key?(:trace) ? @opts[:trace] : Logger::INFO
    @logger.debug("options: #{@opts}")
    project = read_file(file)
    proj_info = self.class.dig_xml(project[:info], %w[Project ProjectInformation])
    group_addr_style = @opts.key?(:addr) ? @opts[:addr] : proj_info['GroupAddressStyle']
    @logger.info("Using project #{proj_info['Name']}, address style: #{group_addr_style}")
    # set group address formatter according to project settings
    @group_address_parser = GROUP_ADDRESS_PARSERS[group_addr_style.to_sym]
    raise "Error: no such style #{group_addr_style} in #{GROUP_ADDRESS_PARSERS.keys}" if @group_address_parser.nil?

    installation = self.class.dig_xml(project[:data], %w[Project Installations Installation])
    # process group ranges: fill @data[:ga]
    process_group_ranges(self.class.dig_xml(installation, %w[GroupAddresses GroupRanges]))
    # process group ranges: fill @data[:ob] (for 2 versions of ETS which have different tags?)
    process_space(self.class.dig_xml(installation, ['Locations']), 'Space') if installation.key?('Locations')
    process_space(self.class.dig_xml(installation, ['Buildings']), 'BuildingPart') if installation.key?('Buildings')
    @logger.warn('No building information found.') if @data[:ob].keys.empty?
  end

  # helper function to dig through keys, knowing that we used ForceArray
  def self.dig_xml(entry_point, path)
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

  def self.function_type_to_name(ft_type)
    m = ft_type.match(/^FT-([0-9])$/)
    raise "ERROR: Unknown function type: #{ft_type}" if m.nil?

    ETS_FUNCTIONS[m[1].to_i]
  end

  # Read both project.xml and 0.xml
  # @return Hash {info: xmldata, data: xmldata}
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
  def process_group_ranges(gr)
    gr['GroupRange'].each { |sgr| process_group_ranges(sgr) } if gr.key?('GroupRange')
    gr['GroupAddress'].each { |ga| process_ga(ga) } if gr.key?('GroupAddress')
  end

  # process a group address
  def process_ga(ga)
    # build object for each group address
    group = {
      name: ga['Name'].freeze, # ETS: name field
      description: ga['Description'].freeze, # ETS: description field
      address: @group_address_parser.call(ga['Address'].to_i).freeze, # group address as string. e.g. "x/y/z" depending on project style
      datapoint: nil, # datapoint type as string "x.00y"
      objs: [], # objects ids, it may be in multiple objects
      custom: {} # modified by lambda
    }
    if ga['DatapointType'].nil?
      @logger.warn("no datapoint type for #{group[:address]} : #{group[:name]}, group address is skipped")
      return
    end
    # parse datapoint for easier use
    if (m = ga['DatapointType'].match(/^DPST-([0-9]+)-([0-9]+)$/))
      # datapoint type as string x.00y
      group[:datapoint] = format('%d.%03d', m[1].to_i, m[2].to_i) # no freeze
    else
      @logger.warn("Cannot parse data point type: #{ga['DatapointType']}, group is skipped, expect: DPST-x-x")
      return
    end
    # Index is the internal Id in xml file
    @data[:ga][ga['Id'].freeze] = group.freeze
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
        name: f['Name'].freeze,
        type: self.class.function_type_to_name(f['Type']),
        ga: f['GroupAddressRef'].map { |g| g['RefId'].freeze },
        custom: {} # custom values
      }.merge(info)
      # store reference to this object in the GAs
      o[:ga].each { |g| @data[:ga][g][:objs].push(f['Id']) if @data[:ga].key?(g) }
      @logger.debug("function: #{o}")
      @data[:ob][f['Id']] = o.freeze
    end
  end

  def generate_homeass
    haknx = {}
    # warn of group addresses that will not be used (you can fix in custom lambda)
    @data[:ga].values.select { |ga| ga[:objs].empty? }.each do |ga|
      @logger.warn("group not in object: #{ga[:address]}: Create custom object in lambda if needed , or use ETS to create functions")
    end
    @data[:ob].each_value do |o|
      new_obj = o[:custom].key?(:ha_init) ? o[:custom][:ha_init] : {}
      unless new_obj.key?('name')
        new_obj['name'] =
        if true && @opts[:full_name]
          "#{o[:name]} #{o[:room]}"
        else
          o[:name]
        end
      end
      # compute object type
      ha_obj_type =
        if o[:custom].key?(:ha_type)
          o[:custom][:ha_type]
        else
          # map FT-x type to home assistant type
          case o[:type]
          when :switchable_light, :dimmable_light then 'light'
          when :sun_protection then 'cover'
          when :custom, :heating_continuous_variable, :heating_floor, :heating_radiator, :heating_switching_variable
            @logger.warn("function type not implemented for #{o[:name]}/#{o[:room]}: #{o[:type]}")
            next
          else @logger.error("function type not supported for #{o[:name]}/#{o[:room]}, please report: #{o[:type]}")
               next
          end
        end
      # process all group addresses in function
      o[:ga].each do |garef|
        ga = @data[:ga][garef]
        next if ga.nil?

        # find property name based on datapoint
        ha_address_type =
          if ga[:custom].key?(:ha_address_type)
            ga[:custom][:ha_address_type]
          else
            case ga[:datapoint]
            when '1.001' then 'address' # switch on/off or state
            when '1.008' then 'move_long_address' # up/down
            when '1.010' then 'stop_address' # stop
            when '1.011' then 'state_address' # switch state
            when '3.007'
              @logger.debug("#{ga[:address]}(#{ha_obj_type}:#{ga[:datapoint]}:#{ga[:name]}): ignoring datapoint")

              next # dimming control: used by buttons
            when '5.001' # percentage 0-100
              # custom code tells what is state
              case ha_obj_type
              when 'light' then 'brightness_address'
              when 'cover' then 'position_address'
              else @logger.warn("#{ga[:address]}(#{ha_obj_type}:#{ga[:datapoint]}:#{ga[:name]}): no mapping for datapoint #{ga[:datapoint]}")
                   next
              end
            else
              @logger.warn("#{ga[:address]}(#{ha_obj_type}:#{ga[:datapoint]}:#{ga[:name]}): no mapping for datapoint #{ga[:datapoint]}")

              next
            end
          end
        if ha_address_type.nil?
          @logger.warn("#{ga[:address]}(#{ha_obj_type}:#{ga[:datapoint]}:#{ga[:name]}): unexpected nil property name")
          next
        end
        if new_obj.key?(ha_address_type)
          @logger.error("#{ga[:address]}(#{ha_obj_type}:#{ga[:datapoint]}:#{ga[:name]}): ignoring for #{ha_address_type} already set with #{new_obj[ha_address_type]}")
          next
        end
        new_obj[ha_address_type] = ga[:address]
      end
      haknx[ha_obj_type] = [] unless haknx.key?(ha_obj_type)
      # check name is not duplicated, as name is used to identify the object
      if haknx[ha_obj_type].any? { |v| v['name'].casecmp?(new_obj['name']) }
        @logger.warn("object name is duplicated: #{new_obj['name']}")
      end
      haknx[ha_obj_type].push(new_obj)
    end
    return { 'knx' => haknx }.to_yaml if @opts[:ha_knx]

    haknx.to_yaml
  end

  # https://sourceforge.net/p/linknx/wiki/Object_Definition_section/
  def generate_linknx
    @data[:ga].values.sort { |a, b| a[:address] <=> b[:address] }.map do |ga|
      linknx_disp_name = ga[:custom][:linknx_disp_name] || ga[:name]
      %(        <object type="#{ga[:datapoint]}" id="id_#{ga[:address].gsub('/',
                                                                            '_')}" gad="#{ga[:address]}" init="request">#{linknx_disp_name}</object>)
    end.join("\n")
  end
end

# prefix of generation methods
GENE_PREFIX = 'generate_'
# get list of generation methods
gene_formats = (ConfigurationImporter.instance_methods - ConfigurationImporter.superclass.instance_methods)
               .select { |m| m.to_s.start_with?(GENE_PREFIX) }
               .map { |m| m[GENE_PREFIX.length..-1] }

opts = GetoptLong.new(
  ['--help', '-h', GetoptLong::NO_ARGUMENT],
  ['--format', '-f', GetoptLong::REQUIRED_ARGUMENT],
  ['--ha-knx', '-k', GetoptLong::NO_ARGUMENT],
  ['--full-name', '-n', GetoptLong::NO_ARGUMENT],
  ['--lambda', '-l', GetoptLong::REQUIRED_ARGUMENT],
  ['--trace', '-t', GetoptLong::REQUIRED_ARGUMENT]
)

options = {}

custom_lambda = File.join(File.dirname(__FILE__), 'default_custom.rb')
output_format = 'homeass'
opts.each do |opt, arg|
  case opt
  when '--help'
    puts <<-EOF
            Usage: #{$PROGRAM_NAME} [--format format] [--lambda lambda] [--addr addr] [--trace trace] [--ha-knx] [--full-name] <etsprojectfile>.knxproj

            -h, --help:
              show help

            --format [format]:
              one of #{gene_formats.join('|')}

            --lambda [lambda]:
              file with lambda

            --addr [addr]:
              one of #{ConfigurationImporter::GROUP_ADDRESS_PARSERS.keys.map(&:to_s).join(', ')}

            --trace [trace]:
              one of debug, info, warn, error

            --ha-knx:
              include level knx in ouput file

            --full-name:
              add room name in object name
    EOF
    Process.exit(1)
  when '--lambda'
    custom_lambda = arg
  when '--format'
    output_format = arg
    raise "Error: no such output format: #{output_format}" unless gene_formats.include?(output_format)
  when '--ha-knx'
    options[:ha_knx] = true
  when '--full-name'
    options[:full_name] = true
  when '--trace'
    options[:trace] = arg
  else
    raise "Unknown option #{opt}"
  end
end

if ARGV.length != 1
  puts 'Missing project file argument (try --help)'
  Process.exit(1)
end

infile = ARGV.shift

# read and parse ETS file
knx_config = ConfigurationImporter.new(infile, options)
# apply special code if provided
eval(File.read(custom_lambda), binding, custom_lambda).call(knx_config) unless custom_lambda.nil?
# generate result
$stdout.write(knx_config.send("#{GENE_PREFIX}#{output_format}".to_sym))
