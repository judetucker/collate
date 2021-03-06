require 'simplecov'

if ENV['CIRCLE_ARTIFACTS']
  dir = File.join(ENV['CIRCLE_ARTIFACTS'], "coverage")
  SimpleCov.coverage_dir(dir)
end

require 'coveralls'
SimpleCov.formatters = [
  SimpleCov::Formatter::HTMLFormatter,
  Coveralls::SimpleCov::Formatter
]

SimpleCov.start do
  add_filter 'test/'
  add_filter 'app/'
  add_filter 'config/'
  add_filter 'lib/collate.rb'
  add_filter 'lib/collate/engine.rb'
  add_filter 'lib/collate/action_view_extension.rb'
end

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
ENV['RAILS_ENV'] ||= 'test'
require 'collate'
require File.expand_path('../../config/environment', __FILE__)

require 'haml'

require "rails-controller-testing"
Rails::Controller::Testing.install

require 'rails/test_help'
require 'minitest/pride'
require 'minitest/hell'
require 'pry-rescue/minitest' if ENV['PRY'].present?

require 'minitest/autorun'

require 'active_record'


load File.dirname(__FILE__) + '/schema.rb'

load File.dirname(__FILE__) + '/seeds.rb'