# frozen_string_literal: true

# Author: https://github.com/TheFelix93/ets-to-homeassistant


#### Short explanation about my ETS project ####
# GA address scheme: function/sub-function/channel-name
# All devices that I want in home assistant are grouped into ETS-Functions
# Currently used/implemented ETS-functions:
#	switchable_light => Lights with on/off
#	dimmable_light => Dimmable-Light, Lights with RGB, Lights-CCT
#	sun_protection => standard covers, shutters with angle-settings
#	custom => 	binary sensors (e.g. reed contacts or any true/false GA),
#				sensors (DPT-to-HA-Sensor-Type mapping table from documentation is used see https://www.home-assistant.io/integrations/knx/#value-types),
#				switches
#	
# This script will use the ETS-Function name to identify the function types and middle-group of the GAs to map GAs to HA specific attributes.

#### GENERAL ####
ENTITY_NAME_WITH_FLOOR = true # if true and a function lies below a floor, the floor name is appended to the HA entity name

SKIP_PATTERN = 'deactivated'






#### Lights #####
# DPT 7.600 in Lights can be 'color_temperature_state_address' or 'color_temperature_address', thus we need a criteria to decide.
# In my ETS project I have a GAs with middle groups that are unique for each function
GA_MIDDLE_GROUP_PATTERN_BRIGHTNESS_SET = '/3/'
GA_MIDDLE_GROUP_PATTERN_BRIGHTNESS_STATUS = '/6/'

## CCT ##
GA_MIDDLE_GROUP_PATTERN_COLOR_TEMP_SET = '/5/'
GA_MIDDLE_GROUP_PATTERN_COLOR_TEMP_STATUS = '/7/'

## RGB ##
GA_MIDDLE_GROUP_PATTERN_RGBCOLOR_SET = '/7/'
GA_MIDDLE_GROUP_PATTERN_RGBCOLOR_STATUS = '/5/'

#### Covers ####
GA_MIDDLE_GROUP_PATTERN_COVER_UP_DOWN = '/0/' # To enable up/down arrows in HA. I have to put my middle group here to distinguish between up/down and current-direction GA. Both have the same DPT.
GA_MIDDLE_GROUP_PATTERN_COVER_POSITION_STATUS = '/4/'
GA_MIDDLE_GROUP_PATTERN_COVER_POSITION_SET = '/3/'
GA_MIDDLE_GROUP_PATTERN_COVER_ANGLE_SET = '/5/'
GA_MIDDLE_GROUP_PATTERN_COVER_ANGLE_STATUS = '/6/'

### Climate ###
GA_MIDDLE_GROUP_PATTERN_SETPOINT_SHIFT_ADDRESS = '/2/' # to distinguish setpoint_shift_status from setpoint_shift_address in DPT9002 mode. May not needed by your project. Somehow to many possibilities with climate...
GA_MIDDLE_GROUP_PATTERN_CURRENT_TEMP = '/0/'
GA_MIDDLE_GROUP_PATTERN_TARGET_TEMP = '/1/'
GA_MIDDLE_GROUP_PATTERN_OPERATION_MODE_SET = '/5/'
GA_MIDDLE_GROUP_PATTERN_OPERATION_MODE_STATUS = '/6/'

CLIMATE_TEMP_STEP = 0.5 # Defines the step size in Kelvin for each step of setpoint_shift (scale factor). For non setpoint-shift configurations this is used to set the step of temperature sliders in UI.
CLIMATE_SHIFT_POINT_MODE = 'DPT9002'



#### Sensors ####
#I name all my sensors like "*Sensor*" in :custom ets functions. This name pattern is used by the script to distinguish them from other custom functions.
#string must be part of ets function name
PATTERN_SENSOR = 'sensor'
SENSOR_SYNC_STATE = true # can be used to change default sync state setting for binary sensors, see HA KNX docu.

#### Number Inputs ####
#I name all my number inputs like "*input*" in :custom ets functions.
PATTERN_INPUT_NUMERIC = 'input'

# to distinguish between GA for address and GA for state_address I added "(set)" to the names of all GAs that should be used for address.
GA_NAME_PATTERN_INPUT_NUMERIC = '(set)'






## patterns to map HA device classes tell HA the type of binary sensor
#string must be part of ets function name
PATTERN_PRESENCE_SENSOR = 'präsenz'
PATTERN_WINDOW_CONTACT = 'fensterkontakt'
PATTERN_WINDALARM_SENSOR = 'windalarm'



#### Switches ####
# If non of the sensor patterns matched then the custom function must be a switch.
#string must be part of ets function name
PATTERN_SWITCH = nil # if you define a switch pattern, then only matches are added as switches to output yaml. With nil set, all remaining custom functions are considered as switches.




# TheFelix93's specific code for KNX configuration
def fix_objects(generator)
  # loop on objects to find blinds

	generator.all_object_ids.each do |obj_id|
		object = generator.object(obj_id)
		group_ids = object_ga_ids(obj_id)
		# set name as function + room + floor if available and activated
		if ENTITY_NAME_WITH_FLOOR && object[:floor] then
			object[:ha]['name'] = "#{object[:name]} #{object[:room]} #{object[:floor]}" 
		end 

		if object[:name].downcase().include?(SKIP_PATTERN) then 
			generator.delete_object(obj_id)
		end
		
		# map FT-x type to home assistant type AND fix HA attributes for each function.
		case object[:type]
		
		when :switchable_light, :dimmable_light 
			object[:ha][:domain] = 'light'
			#loop through GAs of that function
				group_ids.each do |ga_id|
				
					ga_data = generator.group_address_data(ga_id)
					
					
					case ga_data[:datapoint] 
					when '1.001' then ga_data[:ha][:address_type] = 'address'
					when '1.011' then ga_data[:ha][:address_type] = 'state_address' # switch state
					when '3.007' then ga_data[:ha][:address_type] = :ignore # skip relative dimming GA
					when '7.600' then 
						if ga_data[:address].include?(GA_MIDDLE_GROUP_PATTERN_COLOR_TEMP_SET) then ga_data[:ha][:address_type] = 'color_temperature_state_address' 
						elsif ga_data[:address].include?(GA_MIDDLE_GROUP_PATTERN_COLOR_TEMP_STATUS) then ga_data[:ha][:address_type] = 'color_temperature_address'
						else
							ga_data[:ha][:address_type] = :ignore
							warning("TheFelix93", ga_data[:address], "#{ga_data[:name].to_s.cyan} un-managed datapoint #{ga_data[:datapoint].cyan} (#{object[:ha][:domain].magenta}). DPT does not match to identified HA entity type.")
						end
					when '5.001'
						if ga_data[:address].include?(GA_MIDDLE_GROUP_PATTERN_BRIGHTNESS_SET) then ga_data[:ha][:address_type] = 'brightness_state_address' 
						elsif ga_data[:address].include?(GA_MIDDLE_GROUP_PATTERN_BRIGHTNESS_STATUS) then ga_data[:ha][:address_type] = 'brightness_address'
						else
							ga_data[:ha][:address_type] = :ignore
							warning("TheFelix93", ga_data[:address], "#{ga_data[:name].to_s.cyan} un-managed datapoint #{ga_data[:datapoint].cyan} (#{object[:ha][:domain].magenta}). DPT does not match to identified HA entity type.")
						end
					when '232.600' then
						if ga_data[:address].include?(GA_MIDDLE_GROUP_PATTERN_RGBCOLOR_SET) then ga_data[:ha][:address_type] = 'color_address' 
						elsif ga_data[:address].include?(GA_MIDDLE_GROUP_PATTERN_RGBCOLOR_STATUS) then ga_data[:ha][:address_type] = 'color_state_address'
						else
							ga_data[:ha][:address_type] = :ignore
							warning("TheFelix93", ga_data[:address], "#{ga_data[:name].to_s.cyan} un-managed datapoint #{ga_data[:datapoint].cyan} (#{object[:ha][:domain].magenta}). DPT does not match to identified HA entity type.")
						end
					else
						ga_data[:ha][:address_type] = :ignore
						warning("TheFelix93", ga_data[:address], "#{ga_data[:name].to_s.cyan} un-managed datapoint #{ga_data[:datapoint].cyan} (#{object[:ha][:domain].magenta}). DPT does not match to identified HA entity type.")
					end
				
				end
			
			
			

		when :sun_protection then 
			object[:ha][:domain] = 'cover'
			
			#loop through GAs of that function
				group_ids.each do |ga_id|
				
					ga_data = generator.group_address_data(ga_id)
										
					
					case ga_data[:datapoint] 
					when '1.008' then
						if GA_MIDDLE_GROUP_PATTERN_COVER_UP_DOWN && ga_data[:address].include?(GA_MIDDLE_GROUP_PATTERN_COVER_UP_DOWN) || GA_MIDDLE_GROUP_PATTERN_COVER_UP_DOWN == nil
							ga_data[:ha][:address_type] = 'move_long_address'
						else
							ga_data[:ha][:address_type] = :ignore
							warning("TheFelix93", ga_data[:address], "#{ga_data[:name].to_s.cyan} un-managed datapoint #{ga_data[:datapoint].cyan} (#{object[:ha][:domain].magenta}). DPT does not match to identified HA entity type.")
						end
					when '1.007', '1.017' then ga_data[:ha][:address_type] = 'stop_address' # stop, has in my project sometimes DPT "1.007 step" and "1.017 trigger"
					when '5.001' # percentage 0-100
						if ga_data[:address].include?(GA_MIDDLE_GROUP_PATTERN_COVER_POSITION_STATUS) then ga_data[:ha][:address_type] = 'position_state_address' 
						elsif  ga_data[:address].include?(GA_MIDDLE_GROUP_PATTERN_COVER_POSITION_SET) then ga_data[:ha][:address_type] = 'position_address'
						elsif  ga_data[:address].include?(GA_MIDDLE_GROUP_PATTERN_COVER_ANGLE_SET) then ga_data[:ha][:address_type] = 'angle_address'
						elsif  ga_data[:address].include?(GA_MIDDLE_GROUP_PATTERN_COVER_ANGLE_STATUS) then ga_data[:ha][:address_type] = 'angle_state_address'
						else
							ga_data[:ha][:address_type] = :ignore
							warning("TheFelix93", ga_data[:address], "#{ga_data[:name].to_s.cyan} un-managed datapoint #{ga_data[:datapoint].cyan} (#{object[:ha][:domain].magenta}). DPT does not match to identified HA entity type.")
						end
					else
						ga_data[:ha][:address_type] = :ignore
						warning("TheFelix93", ga_data[:address], "#{ga_data[:name].to_s.cyan} un-managed datapoint #{ga_data[:datapoint].cyan} (#{object[:ha][:domain].magenta}). DPT does not match to identified HA entity type.")
					end
				
				end

		when :heating_switching_variable, :heating_floor, :heating_continuous_variable then			
			object[:ha][:domain] = 'climate'
			
			#default parameters needed in HA
			object[:ha].merge!({ 
				'temperature_step' => CLIMATE_TEMP_STEP,
				'setpoint_shift_mode' => CLIMATE_SHIFT_POINT_MODE
			})
			
			
			#loop through GAs of that function
			group_ids.each do |ga_id|	
				
				ga_data = generator.group_address_data(ga_id)
				case ga_data[:datapoint]
				when '6.010', '1.007' then ga_data[:ha][:address_type] = 'setpoint_shift_address'
				when '9.002' then 
					if ga_data[:address].include?(GA_MIDDLE_GROUP_PATTERN_SETPOINT_SHIFT_ADDRESS) then ga_data[:ha][:address_type] = 'setpoint_shift_address'
					else
						ga_data[:ha][:address_type] = 'setpoint_shift_state_address' 
					end
				when '9.001' then
					if ga_data[:address].include?(GA_MIDDLE_GROUP_PATTERN_CURRENT_TEMP) then ga_data[:ha][:address_type] = 'temperature_address' 
					elsif  ga_data[:address].include?(GA_MIDDLE_GROUP_PATTERN_TARGET_TEMP) then ga_data[:ha][:address_type] = 'target_temperature_state_address'
					else
						warning("TheFelix93", ga_data[:address], "#{ga_data[:name].to_s.cyan} un-managed datapoint #{ga_data[:datapoint].cyan} (#{object[:ha][:domain].magenta})")
						ga_data[:ha][:address_type] = :ignore
					end
				when '20.102' then
					if ga_data[:address].include?(GA_MIDDLE_GROUP_PATTERN_OPERATION_MODE_SET) then ga_data[:ha][:address_type] = 'operation_mode_address' 
					elsif  ga_data[:address].include?(GA_MIDDLE_GROUP_PATTERN_OPERATION_MODE_STATUS) then ga_data[:ha][:address_type] = 'operation_mode_state_address'
					else
						warning("TheFelix93", ga_data[:address], "#{ga_data[:name].to_s.cyan} un-managed datapoint #{ga_data[:datapoint].cyan} (#{object[:ha][:domain].magenta})")
						ga_data[:ha][:address_type] = :ignore
					end
				when '5.001' then ga_data[:ha][:address_type] = 'command_value_state_address'
					 
				else
					warning("TheFelix93", ga_data[:address], "#{ga_data[:name].to_s.cyan} un-managed datapoint #{ga_data[:datapoint].cyan} (#{object[:ha][:domain].magenta})")
					ga_data[:ha][:address_type] = :ignore
				end
			end
		
		when :custom then
			
			#sensors
			if object[:name].downcase().include?(PATTERN_SENSOR) then
				object[:ha][:domain] = 'sensor'
				
				# sync_state is recommended for sensors
				object[:ha].merge!({ 
					'sync_state' => SENSOR_SYNC_STATE
				})
				
				#loop through GAs of that function
				group_ids.each do |ga_id|
				
					ga_data = generator.group_address_data(ga_id)
				
					sensor_type = getTypeOfDPT(ga_data[:datapoint])
					if sensor_type then
						# all sensor need state_address=GA
						ga_data[:ha][:address_type] = 'state_address'
						
						
						
						
						if sensor_type == 'binary' then #true false sensor can only be used as binary_sensor in HA... it uses a different yaml section
							object[:ha][:domain] = 'binary_sensor'
							
							if object[:name].downcase().include?(PATTERN_PRESENCE_SENSOR) then #device_class is used to tell HA the type of binary sensor
								object[:ha].merge!({ 
									'device_class' => 'motion'
								})
							elsif object[:name].downcase().include?(PATTERN_WINDOW_CONTACT) then
								object[:ha].merge!({ 
									'device_class' => 'window'
								})
							elsif object[:name].downcase().include?(PATTERN_WINDALARM_SENSOR) then
								object[:ha].merge!({ 
									'device_class' => 'problem'
								})
							else
								# binary sensor without device_class
							end
						else # for all other sensor types an auto lookup ETS DPT to HA type is possible
							object[:ha].merge!({ 
								'type' => sensor_type
							})
						end
					else
						ga_data[:ha][:address_type] = :ignore
						warning("TheFelix93", ga_data[:address], "#{ga_data[:name].to_s.cyan} Unknown sensor type with DPT #{ga_data[:datapoint].to_s.red}. Check if sensor type exists in HA KNX integration")
					end
				
				end
			elsif object[:name].downcase().include?(PATTERN_INPUT_NUMERIC) then
				# numeric inputs
				object[:ha][:domain] = 'number'
							
				
				#loop through GAs of that function
				group_ids.each do |ga_id|
				
					ga_data = generator.group_address_data(ga_id)
				
					number_type = getTypeOfDPT(ga_data[:datapoint])
					if number_type then					
						object[:ha].merge!({ 
							'type' => number_type
						})
						
						# It would be possible to define all sorts of use cases with HA attributes step, min, max, mode etc.
						# I decided to implement only the basics and define the other specifics manually in the yaml ouput.
					
						# identify address and state_address GA
						if ga_data[:name].downcase().include?(GA_NAME_PATTERN_INPUT_NUMERIC) then
							ga_data[:ha][:address_type] = 'address'
						else
							ga_data[:ha][:address_type] = 'state_address'
						end
						
					else
						ga_data[:ha][:address_type] = :ignore
						warning("TheFelix93", ga_data[:address], "#{ga_data[:name].to_s.cyan} Unknown number input type with DPT #{ga_data[:datapoint].to_s.red}. Check if number input type exists in HA KNX integration")
					end
				
				end
				
			elsif PATTERN_SWITCH && object[:name].downcase().include?(PATTERN_SWITCH) || PATTERN_SWITCH == nil then			#In my case all remaining custom functions are switches, but you may have other, so use this PATTERN_SWITCH
				object[:ha][:domain] = 'switch'
				
				#loop through GAs of that function
				group_ids.each do |ga_id|
				
					ga_data = generator.group_address_data(ga_id)
				
					if ga_data[:datapoint] == '1.001' || ga_data[:datapoint] == '1.010' then
						ga_data[:ha][:address_type] = 'address'
					elsif ga_data[:datapoint] == '1.011' then
						ga_data[:ha][:address_type] = 'state_address'
					else
						ga_data[:ha][:address_type] = :ignore
						warning("TheFelix93", ga_data[:address], "#{ga_data[:name].to_s.cyan} Unexpected GA in Switch function with DPT #{ga_data[:datapoint].to_s.red}. Check the switch name pattern and/or functions in ETS and remove all unwanted GAs.")	
					end
					
				end
			else
				#logged by standard script already
				warning("TheFelix93", object[:room], "#{object[:name].to_s.cyan} function type #{object[:type].to_s.red} not implemented.")
			end	


		when :heating_radiator
			warning("TheFelix93", object[:room], "#{object[:name].to_s.cyan} function type #{object[:type].to_s.red} not implemented.")
		else 
			warning("TheFelix93", object[:room], "#{object[:name].to_s.cyan} function type #{object[:type].to_s.red} was not available in ETS5 when this script was developed, please use other ETS functions.")
		end
	end
end





def getTypeOfDPT(knxdpt)
		case knxdpt
		when '1.001' then 'binary'
		when '1.002' then 'binary'
		when '1.003' then 'binary'
		when '1.011' then 'binary'
		when '5' then '1byte_unsigned'
		when '5.001' then 'percent'
		when '5.003' then 'angle'
		when '5.004' then 'percentU8'
		when '5.005' then 'decimal_factor'
		when '5.006' then 'tariff'
		when '5.010' then 'pulse'
		when '6' then '1byte_signed'
		when '6.001' then 'percentV8'
		when '6.010' then 'counter_pulses'
		when '7' then '2byte_unsigned'
		when '7.001' then 'pulse_2byte'
		when '7.002' then 'time_period_msec'
		when '7.003' then 'time_period_10msec'
		when '7.004' then 'time_period_100msec'
		when '7.005' then 'time_period_sec'
		when '7.006' then 'time_period_min'
		when '7.007' then 'time_period_hrs'
		when '7.011' then 'length_mm'
		when '7.012' then 'current'
		when '7.013' then 'brightness'
		when '7.600' then 'color_temperature'
		when '8' then '2byte_signed'
		when '8.001' then 'pulse_2byte_signed'
		when '8.002' then 'delta_time_ms'
		when '8.003' then 'delta_time_10ms'
		when '8.004' then 'delta_time_100ms'
		when '8.005' then 'delta_time_sec'
		when '8.006' then 'delta_time_min'
		when '8.007' then 'delta_time_hrs'
		when '8.010' then 'percentV16'
		when '8.011' then 'rotation_angle'
		when '8.012' then 'length_m'
		when '9' then '2byte_float'
		when '9.001' then 'temperature'
		when '9.002' then 'temperature_difference_2byte'
		when '9.003' then 'temperature_a'
		when '9.004' then 'illuminance'
		when '9.005' then 'wind_speed_ms'
		when '9.006' then 'pressure_2byte'
		when '9.007' then 'humidity'
		when '9.008' then 'ppm'
		when '9.009' then 'air_flow'
		when '9.010' then 'time_1'
		when '9.011' then 'time_2'
		when '9.020' then 'voltage'
		when '9.021' then 'curr'
		when '9.022' then 'power_density'
		when '9.023' then 'kelvin_per_percent'
		when '9.024' then 'power_2byte'
		when '9.025' then 'volume_flow'
		when '9.026' then 'rain_amount'
		when '9.027' then 'temperature_f'
		when '9.028' then 'wind_speed_kmh'
		when '9.029' then 'absolute_humidity'
		when '9.030' then 'concentration_ugm3'
		when '9.?' then 'enthalpy'
		when '12' then '4byte_unsigned'
		when '12.001' then 'pulse_4_ucount'
		when '12.100' then 'long_time_period_sec'
		when '12.101' then 'long_time_period_min'
		when '12.102' then 'long_time_period_hrs'
		when '121.200' then 'volume_liquid_litre'
		when '121.201' then 'volume_m3'
		when '13' then '4byte_signed'
		when '13.001' then 'pulse_4byte'
		when '13.002' then 'flow_rate_m3h'
		when '13.010' then 'active_energy'
		when '13.011' then 'apparant_energy'
		when '13.012' then 'reactive_energy'
		when '13.013' then 'active_energy_kwh'
		when '13.014' then 'apparant_energy_kvah'
		when '13.015' then 'reactive_energy_kvarh'
		when '13.016' then 'active_energy_mwh'
		when '13.100' then 'long_delta_timesec'
		when '14' then '4byte_float'
		when '14.000' then 'acceleration'
		when '14.001' then 'acceleration_angular'
		when '14.002' then 'activation_energy'
		when '14.003' then 'activity'
		when '14.004' then 'mol'
		when '14.005' then 'amplitude'
		when '14.006' then 'angle_rad'
		when '14.007' then 'angle_deg'
		when '14.008' then 'angular_momentum'
		when '14.009' then 'angular_velocity'
		when '14.010' then 'area'
		when '14.011' then 'capacitance'
		when '14.012' then 'charge_density_surface'
		when '14.013' then 'charge_density_volume'
		when '14.014' then 'compressibility'
		when '14.015' then 'conductance'
		when '14.016' then 'electrical_conductivity'
		when '14.017' then 'density'
		when '14.018' then 'electric_charge'
		when '14.019' then 'electric_current'
		when '14.020' then 'electric_current_density'
		when '14.021' then 'electric_dipole_moment'
		when '14.022' then 'electric_displacement'
		when '14.023' then 'electric_field_strength'
		when '14.024' then 'electric_flux'
		when '14.025' then 'electric_flux_density'
		when '14.026' then 'electric_polarization'
		when '14.027' then 'electric_potential'
		when '14.028' then 'electric_potential_difference'
		when '14.029' then 'electromagnetic_moment'
		when '14.030' then 'electromotive_force'
		when '14.031' then 'energy'
		when '14.032' then 'force'
		when '14.033' then 'frequency'
		when '14.034' then 'angular_frequency'
		when '14.035' then 'heatcapacity'
		when '14.036' then 'heatflowrate'
		when '14.037' then 'heat_quantity'
		when '14.038' then 'impedance'
		when '14.039' then 'length'
		when '14.040' then 'light_quantity'
		when '14.041' then 'luminance'
		when '14.042' then 'luminous_flux'
		when '14.043' then 'luminous_intensity'
		when '14.044' then 'magnetic_field_strength'
		when '14.045' then 'magnetic_flux'
		when '14.046' then 'magnetic_flux_density'
		when '14.047' then 'magnetic_moment'
		when '14.048' then 'magnetic_polarization'
		when '14.049' then 'magnetization'
		when '14.050' then 'magnetomotive_force'
		when '14.051' then 'mass'
		when '14.052' then 'mass_flux'
		when '14.053' then 'momentum'
		when '14.054' then 'phaseanglerad'
		when '14.055' then 'phaseangledeg'
		when '14.056' then 'power'
		when '14.057' then 'powerfactor'
		when '14.058' then 'pressure'
		when '14.059' then 'reactance'
		when '14.060' then 'resistance'
		when '14.061' then 'resistivity'
		when '14.062' then 'self_inductance'
		when '14.063' then 'solid_angle'
		when '14.064' then 'sound_intensity'
		when '14.065' then 'speed'
		when '14.066' then 'stress'
		when '14.067' then 'surface_tension'
		when '14.068' then 'common_temperature'
		when '14.069' then 'absolute_temperature'
		when '14.070' then 'temperature_difference'
		when '14.071' then 'thermal_capacity'
		when '14.072' then 'thermal_conductivity'
		when '14.073' then 'thermoelectric_power'
		when '14.074' then 'time_seconds'
		when '14.075' then 'torque'
		when '14.076' then 'volume'
		when '14.077' then 'volume_flux'
		when '14.078' then 'weight'
		when '14.079' then 'work'
		when '14.080' then 'apparent_power'
		when '16.000' then 'string'
		when '16.001' then 'latin_1'
		when '17.001' then 'scene_number'
		else nil
		end
	end
