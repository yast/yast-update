ENV["Y2DIR"] = File.join(File.expand_path(File.dirname(__FILE__)), "../src/")

require "yast"
require "yast/rspec"
require_relative "helpers"

RSpec.configure do |config|
  config.extend Yast::I18n # available in context/describe
  config.include Yast::I18n # available in it/let/before
  config.include Helpers
end

if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start do
    add_filter "/test/"
  end

  src_location = File.expand_path("../../src", __FILE__)
  # track all ruby files under src
  SimpleCov.track_files("#{src_location}/**/*.rb")

  # use coveralls for on-line code coverage reporting at Travis CI
  if ENV["TRAVIS"]
    require "coveralls"
    SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter[
      SimpleCov::Formatter::HTMLFormatter,
      Coveralls::SimpleCov::Formatter
    ]
  end
end

