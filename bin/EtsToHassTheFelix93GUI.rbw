# frozen_string_literal: true

require 'glimmer-dsl-libui'

require 'shellwords'
require 'clipboard'

# to enable packagin to exe (glimmer dependencies that get not recognized by ocran)
require 'matrix'
require 'rake'

# simple YAML persistence
require 'yaml'
require 'fileutils'

$exe_dir = File.dirname(ENV['OCRAN_EXECUTABLE'] || $0)

module Settings
  APP_NAME = 'ets_to_hass_gui'

  def self.config_dir
    File.join(Dir.home, '.config', APP_NAME)
  end

  def self.config_file
    File.join(config_dir, 'settings.yml')
  end

  def self.load
    return {} unless File.exist?(config_file)
    YAML.safe_load(File.read(config_file), symbolize_names: false) || {}
  rescue StandardError
    {}
  end

  def self.save(hash)
    FileUtils.mkdir_p(config_dir)
    str_keys = hash.transform_keys!(&:to_s)
    File.write(config_file, str_keys.to_yaml)
  rescue StandardError
    # swallow to avoid blocking UI closing
  end
end

class EtsToHassApp
  include Glimmer

  class EtsToHassRunner
    def initialize(model)
      @model = model
    end

    # Visible Command Prompt (new window)
    def open_user_cmd(command:, keep_open: true)
      shell_flag = keep_open ? '/k' : '/c'

      system(%Q(start "CMD - ETS → Home Assistant KNX (Github - TheFelix93)" cmd #{shell_flag} "#{clear_env_cmd} & #{command}"))
    end

    # Ensure we hand cmd.exe a string when needed
    def command_string(command)
      command.is_a?(Array) ? command.map(&:to_s).join(' ') : command.to_s
    end

    def clear_env_cmd
      cmd = [
        'set "BUNDLER_ORIG_BUNDLER_SETUP="',
        'set "BUNDLER_ORIG_BUNDLER_VERSION="',
        'set "BUNDLER_ORIG_BUNDLE_BIN_PATH="',
        'set "BUNDLER_ORIG_BUNDLE_GEMFILE="',
        'set "BUNDLER_ORIG_GEM_HOME="',
        'set "BUNDLER_ORIG_GEM_PATH="',
        'set "BUNDLER_ORIG_MANPATH="',
        'set "BUNDLER_ORIG_PATH="',
        'set "BUNDLER_ORIG_RB_USER_INSTALL="',
        'set "BUNDLER_ORIG_RUBYLIB="',
        'set "BUNDLER_ORIG_RUBYOPT="',
        'set "BUNDLER_SETUP="',
        'set "BUNDLER_VERSION="',
        'set "BUNDLE_BIN_PATH="',
        'set "BUNDLE_GEMFILE="',
        'set "BUNDLE_SYSTEM_BINDIR="',
        'set "RUBYLIB="',
        'set "RUBYOPT="',
        'set "GEM_HOME="'
      ].join(' & ')
    end
  end

  class AppModel
    attr_accessor :project_path, :output_path, :format_index, :ha_knx, :sort_by_name, :full_name,
                  :fix_file_path, :addr_index, :trace_index, :cmd_preview, :exe_path # , :password

    def initialize
      Glimmer::LibUI.queue_main do
        # load settings with safe defaults(string(keys))
        s = Settings.load

        # default settings if nothing was loaded
        s = defaults_hash if s.empty?

        apply_hash(s)
        rebuild_preview(false)
      end
    end

    def apply_hash(h)
      self.project_path = h['project_path'].to_s if h.key?('project_path')

      self.output_path = h['output_path'].to_s if h.key?('output_path')

      self.exe_path = h['exe_path'].to_s if h.key?('exe_path')

      if h.key?('format_index')
        idx = begin
          Integer(h['format_index'])
        rescue StandardError
          -1
        end
        values = format_values
        self.format_index = (0...values.size).cover?(idx) ? idx : (values.index('homeass') || 0)
      end

      self.ha_knx = !!h['ha_knx'] if h.key?('ha_knx')

      self.sort_by_name = !!h['sort_by_name'] if h.key?('sort_by_name')

      self.full_name = !!h['full_name'] if h.key?('full_name')

      self.fix_file_path = h['fix_file_path'].to_s if h.key?('fix_file_path')

      if h.key?('addr_index')
        idx = begin
          Integer(h['addr_index'])
        rescue StandardError
          -1
        end
        self.addr_index = (0...addr_values.size).cover?(idx) ? idx : 0
      end

      return unless h.key?('trace_index')
      idx = begin
        Integer(h['trace_index'])
      rescue StandardError
        -1
      end
      self.trace_index = (0...trace_values.size).cover?(idx) ? idx : 0
    end

    def defaults_hash
      {
        'exe_path'      => upcase_drive(File.join($exe_dir, 'ets_to_hass.exe').to_s.tr('/', '\\')),
        'fix_file_path' => upcase_drive(File.expand_path(File.join($exe_dir, '..', 'lib', 'ets_to_hass', 'specific', 'TheFelix93.rb')).to_s.tr('/', '\\')),
        'output_path'   => upcase_drive(File.join($exe_dir, 'output', 'config_knx.yaml').to_s.tr('/', '\\')),
        'full_name'     => true,
        'format_index'  => 0,
        'addr_index'    => nil,
        'trace_index'   => nil,
        'ha_knx'        => false,
        'sort_by_name'  => false

      }
    end

    def apply_defaults
      apply_hash(defaults_hash)
    end

    def format_values
      @format_values ||= %w[homeass linknx]
    end

    def addr_values
      @addr_values ||= [''] + %w[Free TwoLevel ThreeLevel']
    end

    def trace_values
      @trace_values ||= ['', 'debug', 'info', 'warn', 'error']
    end

    def format
      format_values[@format_index] || format_values.first
    end

    def addr
      addr_values[@addr_index] || ''
    end

    def trace
      trace_values[@trace_index] || ''
    end

    def cmd_fully_quote(arg)
      s = arg.to_s
      # 1) neutralize percent expansion
      s = s.gsub('%', '%%')
      # 2) double embedded quotes
      s = s.gsub('"', '""')
      # 3) wrap in quotes
      %Q("#{s}")
    end

    def rebuild_preview(return_only)
      argv = []
      argv << '--ha-knx' if @ha_knx
      argv << '--sort-by-name' if @sort_by_name
      argv << '--full-name' if @full_name
      argv += ['--format', format] unless format.to_s.strip.empty?
      argv += ['--fix', "\"#{@fix_file_path.strip}\""] unless @fix_file_path.to_s.strip.empty?
      argv += ['--addr', addr] unless addr.to_s.strip.empty?
      argv += ['--trace', trace] unless trace.to_s.strip.empty?
      argv += ['--output', "\"#{@output_path.strip}\""] unless @output_path.to_s.strip.empty?

      # if return_only
      #   argv += ['--password', "#{cmd_fully_quote(@password.strip)}"] unless @password.to_s.strip.empty?
      # elsif !return_only && !@password.to_s.strip.empty?
      #   argv += ['--password', '"PASSWORD_HIDDEN"']
      #   argv += ['--password', "#{cmd_fully_quote(@password.strip)}"] unless @password.to_s.strip.empty?
      # end

      argv << "\"#{@project_path.strip}\"" unless @project_path.to_s.strip.empty?

      if @exe_path.to_s.strip.empty?
        tool = 'ets_to_hass.exe not selected'
        prefix = 'cd /d ".\\"'
      else
        tool = upcase_drive(@exe_path.strip)
        prefix = "cd /d \"#{File.dirname(tool)}\""
      end

      command_args = ["\"#{tool}\"", *argv]

      suffix = ''

      # Ensure every arg is a UTF-8 String before join
      safe_args = command_args.map do |a|
        s = a.to_s
        s = s.dup.force_encoding(Encoding::UTF_8) if s.encoding == Encoding::ASCII_8BIT
        # If bytes are not valid UTF-8, transcode with replacement to avoid exceptions
        s.valid_encoding? ? s : s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: '?')
      end

      safe_prefix = prefix.to_s
      safe_prefix = safe_prefix.dup.force_encoding(Encoding::UTF_8) if safe_prefix.encoding == Encoding::ASCII_8BIT
      safe_prefix = safe_prefix.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: '?') unless safe_prefix.valid_encoding?

      safe_suffix = suffix.to_s
      safe_suffix = safe_suffix.dup.force_encoding(Encoding::UTF_8) if safe_suffix.encoding == Encoding::ASCII_8BIT
      safe_suffix = safe_suffix.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: '?') unless safe_suffix.valid_encoding?

      new_cmd = "#{safe_prefix} && #{safe_args.join(' ')}#{safe_suffix}"

      return_only ? new_cmd : self.cmd_preview = new_cmd
    end

    # ADD: export settings hash
    def to_settings_hash
      {
        project_path:  @project_path,
        output_path:   @output_path,
        format_index:  @format_index,
        ha_knx:        @ha_knx,
        sort_by_name:  @sort_by_name,
        full_name:     @full_name,
        fix_file_path: @fix_file_path,
        addr_index:    @addr_index,
        trace_index:   @trace_index,
        exe_path:      @exe_path
      }
    end

    def upcase_drive(path)
      path.sub(/\A([a-z]):/) { |m| m.upcase }
    end
  end

  def launch
    model = AppModel.new
    runner = EtsToHassRunner.new(model)

    project_entry = nil
    output_entry  = nil
    fix_entry     = nil

    window('ETS → Home Assistant KNX (TheFelix93)', 1000, 400) do
      on_closing do
        Settings.save(model.to_settings_hash)
        nil # allow default close behavior
      end

      margined true
      vertical_box do
        group('Info') do
          margined true
          stretchy false
          vertical_box do
            horizontal_box do
              label do
                text "Settings are stored in #{Settings.config_file}"
                stretchy false
              end

              button('Reset to Defaults') do
                on_clicked do
                  model.apply_defaults
                  model.rebuild_preview(false)
                end
              end
              label do
                text ''
                stretchy true
              end
            end
          end
        end
        tab do
          tab_item('Main') do
            vertical_box do
              group('Input / Output') do
                margined true
                form do
                  project_entry = entry do
                    label '.knxproj file'
                    read_only true
                    text <=> [model, :project_path, { after_write: ->(_) { model.rebuild_preview(false) } }] # rubocop:disable Layout/SpaceAroundOperators,Lint/Void
                    stretchy false
                  end
                  # password_entry do
                  #   label '.knxproj password'
                  #   text <=> [model, :password, { after_write: ->(_) { model.rebuild_preview(false) } }] # rubocop:disable Layout/SpaceAroundOperators,Lint/Void
                  #   stretchy false
                  # end

                  button('Browse…') do
                    on_clicked do
                      path = open_file
                      if path && !path.empty?
                        shown = path.dup.force_encoding(Encoding::UTF_8)
                        model.project_path = shown
                        project_entry.text = shown
                        model.rebuild_preview(false)
                      end
                    end
                    stretchy false
                  end

                  output_entry = entry do
                    label 'Output file'
                    read_only true
                    text <=> [model, :output_path, { after_write: ->(_) { model.rebuild_preview(false) } }] # rubocop:disable Lint/Void
                    stretchy false
                  end

                  button('Save as…') do
                    on_clicked do
                      path = save_file
                      if path && !path.empty?
                        shown = path.dup.force_encoding(Encoding::UTF_8)
                        model.output_path = shown
                        output_entry.text = shown
                        model.rebuild_preview(false)
                      end
                    end
                    stretchy false
                  end

                  fix_entry = entry do
                    read_only true
                    label 'Ruby File (specific code to fix objects)'
                    text <=> [model, :fix_file_path, { after_write: ->(_) { model.rebuild_preview(false) } }] # rubocop:disable Lint/Void
                    stretchy false
                  end

                  button('Browse...') do
                    stretchy false
                    on_clicked do
                      path = open_file
                      if path && !path.empty?
                        shown = path.dup.force_encoding(Encoding::UTF_8)
                        model.fix_file_path = shown
                        fix_entry.text = shown
                        model.rebuild_preview(false)
                      end
                    end
                  end
                end
              end

              group('Options') do
                margined true
                stretchy false
                vertical_box do
                  horizontal_box do
                    stretchy false
                    label do
                      text 'Format'
                      stretchy false
                    end
                    combobox do
                      items model.format_values
                      selected <=> [model, :format_index, { after_write: ->(_) { model.rebuild_preview(false) } }] # rubocop:disable Lint/Void
                      stretchy false
                    end

                    checkbox('HA KNX level') do
                      checked <=> [model, :ha_knx, { after_write: ->(_) { model.rebuild_preview(false) } }] # rubocop:disable Lint/Void
                      stretchy false
                    end
                    checkbox('Sort by name') do
                      checked <=> [model, :sort_by_name, { after_write: ->(_) { model.rebuild_preview(false) } }] # rubocop:disable Lint/Void
                      stretchy false
                    end
                    checkbox('Full name') do
                      checked <=> [model, :full_name, { after_write: ->(_) { model.rebuild_preview(false) } }] # rubocop:disable Lint/Void
                      stretchy false
                    end
                    label do
                      text ''
                      stretchy true
                    end
                  end

                  horizontal_box do
                    label do
                      text 'Addr parser'
                      stretchy false
                    end
                    combobox do
                      items model.addr_values
                      selected <=> [model, :addr_index, { after_write: ->(_) { model.rebuild_preview(false) } }] # rubocop:disable Lint/Void
                      stretchy false
                    end

                    label do
                      text 'Trace'
                      stretchy false
                    end
                    combobox do
                      items model.trace_values
                      selected <=> [model, :trace_index, { after_write: ->(_) { model.rebuild_preview(false) } }] # rubocop:disable Lint/Void
                      stretchy false
                    end
                    label do
                      text ''
                      stretchy true
                    end
                  end
                end
              end

              group('Command Preview') do
                margined true

                vertical_box do
                  form do
                    exe_entry = entry do
                      read_only true
                      label 'ets_to_hass.exe'
                      text <=> [model, :exe_path, { after_write: ->(_) { model.rebuild_preview(false) } }] # rubocop:disable Lint/Void
                      stretchy true
                    end

                    button('Browse…') do
                      stretchy false
                      on_clicked do
                        path = open_file
                        if path && !path.empty?
                          shown = path.dup.force_encoding(Encoding::UTF_8)
                          model.exe_path = shown
                          exe_entry.text = shown
                          model.rebuild_preview(false)
                        end
                      end
                    end
                  end

                  multiline_entry do
                    read_only true
                    text <= [model, :cmd_preview]
                  end

                  horizontal_box do
                    stretchy false

                    button('Copy') do
                      on_clicked do
                        Clipboard.copy(model.cmd_preview.to_s.dup.force_encoding('UTF-8'))
                        # msg_box('Copied', 'Command copied to clipboard.')
                      end
                    end

                    button('Execute in CMD') do
                      on_clicked do
                        cmd = model.rebuild_preview(true)
                        next if cmd.empty?

                        runner.open_user_cmd(command: cmd).to_s
                      end
                    end
                    button('Open output folder') do
                      on_clicked do
                        path = File.dirname(model.output_path.to_s)

                        if Gem.win_platform?
                          system('explorer.exe', path)
                        elsif RUBY_PLATFORM =~ /darwin/
                          system('open', path)
                        else
                          system('xdg-open', path)
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
        horizontal_box do
          stretchy false
          label do
            text '(C) https://github.com/TheFelix93/ets-to-homeassistant - 2025'
            stretchy false
          end
        end
      end
    end.show
  end
end

EtsToHassApp.new.launch
