require 'date'
require 'cgi'

module Agents
	class WeatherAlertAgent < Agent

		description <<-MD
		  The WeatherAlertAgent creates an event that retrieves current weather alerts at a given `location` which is taken from the WeatherAgent events.

		  The weather alerts are provided by Wunderground.  You must setup an [API key for Wunderground](http://www.wunderground.com/weather/api/) in order to use this Agent with Wunderground. Preferably setup a credential named "wunderground_api_key".

		  Set `location` to an API friendly description of your geographic location.

		  Set `api_key` to your Wunderground API key.

		  Set `default_check_schedule` to the maximum interval to check when not expecting an alert.

		  Set `on_alert_check_schedule` to the interval at which to check when there is an alert or an alert is expected.

		  Set `expected_update_period_in_days` to the maximum amount of time that you'd expect to pass between Events being created by this Agent.
		MD

		event_description <<-MD
			Events look like this:
			MD
		fake_event = [{
					"type" => "HEA", 
					"description" => "Heat Advisory", 
					"date" => "11:14 am CDT on July 3, 2012", 
					"date_epoch" => "1341332040", 
					"expires" => "7:00 AM CDT on July 07, 2012", 
					"expires_epoch" => "1341662400", 
					"message" => "\u000A...Heat advisory remains in effect until 7 am CDT Saturday...\u000A\u000A* temperature...heat indices of 100 to 105 are expected each \u000A afternoon...as Max temperatures climb into the mid to upper \u000A 90s...combined with dewpoints in the mid 60s to around 70. \u000A Heat indices will remain in the 75 to 80 degree range at \u000A night. \u000A\u000A* Impacts...the hot and humid weather will lead to an increased \u000A risk of heat related stress and illnesses. \u000A\u000APrecautionary/preparedness actions...\u000A\u000AA heat advisory means that a period of hot temperatures is\u000Aexpected. The combination of hot temperatures and high humidity\u000Awill combine to create a situation in which heat illnesses are\u000Apossible. Drink plenty of fluids...stay in an air-conditioned\u000Aroom...stay out of the sun...and check up on relatives...pets...\u000Aneighbors...and livestock.\u000A\u000ATake extra precautions if you work or spend time outside. Know\u000Athe signs and symptoms of heat exhaustion and heat stroke. Anyone\u000Aovercome by heat should be moved to a cool and shaded location.\u000AHeat stroke is an emergency...call 9 1 1.\u000A\u000A\u000A\u000AMjb\u000A\u000A\u000A", 
					"phenomena" => "HT", 
					"significance" => "Y", 
					"ZONES" => [ { "state" => "UT", "ZONE" => "001" } ], 
					"StormBased" => 
						{ 
							"vertices" => 
							[ 
								{ "lat" => "38.87", "lon" => "-87.13" }, 
								{ "lat" => "38.89", "lon" => "-87.13" }, 
								{ "lat" => "38.91", "lon" => "-87.11" }, 
								{ "lat" => "38.98", "lon" => "-86.93" }, 
								{ "lat" => "38.87", "lon" => "-86.69" }, 
								{ "lat" => "38.75", "lon" => "-86.3" }, 
								{ "lat" => "38.84", "lon" => "-87.16" } 
							], 
							"Vertex_count" => 7, 
							"stormInfo" => 
							{ 
								"time_epoch" => 1363464360, 
								"Motion_deg" => 243, 
								"Motion_spd" => 18, 
								"position_lat" => 38.90, 
								"position_lon" => -86.96 
							} 
					}
				}]
		#MD

		default_schedule 'every_30m'
		@default_schedule = 'every_30m'
		@default_on_alert_schedule = 'every_10m'
		@default_location = '94103'
		@default_api_key = 'your-key'
		@default_watch_alerts = false
		@default_have_alerts = false

		def watch_alerts?
			# if we have a suspect forecast return true else return false
			self.memory["watch_alerts"] = @default_watch_alerts unless self.memory["watch_alerts"].present?
			self.memory["watch_alerts"]
		end

		def have_alerts?
			# if we have alerts return true else return false
			self.memory["have_alerts"] = @default_have_alerts unless self.memory["have_alerts"].present?
			self.memory["have_alerts"]
		end
		
		def on_alert?
			have_alerts? or watch_alerts?
		end

		def location?
			interpolated["location"] != @default_location
		end

		def location
			interpolated["location"].presence || @default_location
		end

		def working?
			event_created_within?((interpolated['expected_update_period_in_days'].presence || 1).to_i) && !recent_error_logs?
		end

		def api_key?
			interpolated['api_key'] != @default_api_key
		end

		def api_key
			interpolated['api_key'].presence || @default_api_key
		end

		def ready?
			api_key? and location?
		end

		def default_check_schedule
			interpolated['default_check_schedule'].presence || @default_schedule
		end

		def on_alert_check_schedule
			interpolated['on_alert_check_schedule'].presence || @default_on_alert_schedule
		end

			#alert['expires_short'] = Time.at(alert["expires_epoch"].to_i).strftime("%m/%d %H:%M")

			# clean up major formatting
			#msg = alert['message'].gsub("\u000A...","").gsub("\u000A", "").gsub("...","\n")
			# condense first sentence describing the event end it's duration
			#msg = msg.gsub("^#{alert['description']} remains in effect until [^.]","#{alert['description']} expires #{expires_short}")
			# grab an arbitrary number of characters to prevent tweet or sms overflow
			#alert['message_short'] = msg.slice(0, 140)

		def default_options
		  {
			'location' => @default_location,
			'api_key' => @default_api_key,
			'default_check_schedule' => @default_schedule,
			'on_alert_check_schedule' => @default_on_alert_schedule,
			'expected_update_period_in_days' => '0'
		  }
		end

		def validate_options
			errors.add(:base, "api_key is required") unless api_key?
			errors.add(:base, "location is required") unless location?
		end

		def get_alerts
			wg = Wunderground.new(api_key)
			alerts = fake_event #wg.alert_for(location)["alerts"]
			alerts.map { |alert| Hash[alert.map { |k, v| [{'type' => 'alert_type'}[k] || k, v] }] }
		end

		def model
			alerts = get_alerts
			self.memory["have_alerts"] = !alerts.empty?
			alerts
		end

		def receive(incoming_events)
			incoming_events.each do |event|
				check_forecast(event.payload['conditions'])
			end
		end

		def check_forecast(conditions)
			# Accepts WeatherAgent events with `which_day` == 0
			# If the forcast is for nasty stuff pay closer attention to the weather alerts.
			# check if we should expect an alert given the weather forecast
			# and set the interval to check for alerts if they are expected
			[
				/.*Thunderstorm.*/i,
				/.*Squalls.*/i,
				/.*Sandstorm.*/i,
				/.*Dust.*/i,
				/.*Sand.*/i,
				/.*Smoke.*/i,
				/.*Hail.*/i
			].each do |condition|
				self.memory["watch_alerts"] = (conditions =~ condition)
				break if watch_alerts?
			end
			if on_alert?
				self.schedule = on_alert_check_schedule
			else
				self.schedule = default_check_schedule
			end
		end

		def check
			events = model
			create_event :payload => events unless events.empty?
		end
	end
end
