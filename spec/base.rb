require File.dirname(__FILE__) + '/../lib/all'

require 'mocha'
require 'micronaut'

Micronaut.configure do |config|
  config.mock_with :mocha
  config.color_enabled = true
  config.alias_example_to :fit, :focused => true
  config.filter_run :options => { :focused => true }
end
