ENV["Y2DIR"] = File.join(File.expand_path(File.dirname(__FILE__)), "../src/")

# make sure we run the tests in English locale
# (some tests check the output which is marked for translation)
ENV["LC_ALL"] = "en_US.UTF-8"

require "yast"
require "yast/rspec"
require_relative "helpers"

RSpec.configure do |config|
  config.extend Yast::I18n # available in context/describe
  config.include Yast::I18n # available in it/let/before
  config.include Helpers
end
