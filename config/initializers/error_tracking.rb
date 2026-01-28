# frozen_string_literal: true

# Register error tracking subscriber with Rails error reporter
Rails.application.config.after_initialize do
  Rails.error.subscribe(Admin::Errors::Subscriber.new)
end
