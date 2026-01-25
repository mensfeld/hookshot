source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use sqlite3 as the database for Active Record
gem "sqlite3"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Use Tailwind CSS [https://github.com/rails/tailwindcss-rails]
gem "tailwindcss-rails"

# Use the database-backed adapter for Active Job
gem "solid_queue"

# Job queue dashboard
gem "mission_control-jobs"

# Pagination
gem "kaminari"

group :development, :test do
  gem "debug"
  gem "rubocop-rails-omakase", require: false
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "simplecov"
end

group :test do
  gem "shoulda-matchers"
  gem "webmock"
end
