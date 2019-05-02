require "simplecov"
require "coveralls"
require 'curb'
require 'webmock/rspec'
require 'nokogiri'
require 'builder'
SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter::new
SimpleCov.start { add_filter "/spec/" }

require "lita-slack"
require "teamcityhelper/misc"
require "lita/handlers/teamcity"
require "lita/rspec"
require "lita-buildbot"

Lita.version_3_compatibility_mode = false

RSpec.configure do |config|
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
end
