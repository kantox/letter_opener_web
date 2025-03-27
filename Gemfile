# frozen_string_literal: true

source 'http://rubygems.org'

# Declare your gem's dependencies in letter_opener_web.gemspec.
# Bundler will treat runtime dependencies like base dependencies, and
# development dependencies will be added by default to the :development group.
gemspec

group :development do
  if RUBY_VERSION.to_f < 3.0
    gem 'rails', '~> 5.2'
  else
    gem 'rails', '~> 6.1'
  end
  gem 'rspec-rails', '~> 5.0'
  gem 'rubocop', '~> 1.22'
  gem 'rubocop-rails', '~> 2.12'
  gem 'rubocop-rspec', '~> 2.5'
end

group :development, :test do
  gem 'pry-byebug'
  gem 'pry-rails'
end
