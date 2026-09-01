# frozen_string_literal: true

source "https://rubygems.org"

ruby ">= 3.1"

gem "sinatra", "~> 4.1"          # web framework
gem "rackup", "~> 2.2"           # rack server launcher
gem "puma", "~> 6.4"             # app server
gem "sqlite3", "~> 2.1"          # storage
gem "nokogiri", "~> 1.16"        # HTML scraping
gem "rss", "~> 0.3"              # RSS/Atom parsing (stdlib gem)
gem "anthropic", "~> 1.0"        # optional: Claude-backed headline rewriting

group :development, :test do
  gem "minitest", "~> 5.20"
  gem "rack-test", "~> 2.1"
  gem "rake", "~> 13.0"
end
