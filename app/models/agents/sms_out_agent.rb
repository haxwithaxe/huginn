module Agents
  class SmsOutAgent < Agent
    include EmailConcern

    cannot_be_scheduled!
    cannot_create_events!

    description <<-MD
      The SMSOutAgent sends any events it receives via email->SMS gateway immediately.
      The email will be sent to the specified phone number and will have a `subject` before listing the Events.  If the Events' payloads contain a `:message`, that will be highlighted, otherwise everything in their payloads will be shown.

      Set `expected_receive_period_in_days` to the maximum amount of time that you'd expect to pass between Events being received by this Agent.
    MD

	self.validate :validate_sms_options

    def default_options
      {
          'subject' => "You have a notification!",
		  'phone_num' => "5555555555",
		  'sms_gateway' => "sms.example.com",
          'expected_receive_period_in_days' => "90"
      }
    end

	def validate_sms_options
		errors.add(:base, "`phone_num` must be set to a valid phone number.") if interpolated['phone_num'] == "5555555555"
		errors.add(:base, "`sms_gateway` must be set to a valid email to SMS gateway (see http://www.ukrainecalling.com/email-to-text.aspx)") if interpolated['sms_gateway'] == "sms.example.com"
	end

	def email_address
		# return the formatted email address comprised of the phone number and SMS
		# email gateway domain.
		return "#{phone_num}@#{sms_gateway}"
	end

	def sms_gateway
		# return the domain part of the SMS email gateway
		return interpolated['sms_gateway']
	end

	def phone_num
		# return the phone number specified in the config
		return interpolated['phone_num']
	end

    def receive(incoming_events)
      incoming_events.each do |event|
        log "Sending SMS to #{email_address} with event #{event.id}"
        SystemMailer.delay.send_message(:to => "#{email_address}", :subject => interpolated(event.payload)['subject'], :groups => [present(event.payload)])
      end
    end
  end
end
