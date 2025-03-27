# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'test'

# I am not sure why we need this. Maybe never rails version auto require logger properly
require 'logger'

require File.expand_path('dummy/config/environment', __dir__)
require 'spec_helper'
require 'rspec/rails'

RSpec.configure(&:infer_spec_type_from_file_location!)
