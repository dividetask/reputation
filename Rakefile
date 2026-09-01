# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test" << "lib"
  t.pattern = "test/**/*_test.rb"
  t.warning = false
end

desc "Crawl every configured source"
task :crawl do
  ruby "bin/crawl"
end

desc "Start the web app"
task :server do
  sh "bundle exec rackup -p #{ENV.fetch('PORT', 4567)}"
end

task default: :test
