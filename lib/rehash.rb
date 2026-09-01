# frozen_string_literal: true

require "pathname"

# Rehash — a reddit-style aggregator that crawls sites, rewrites the
# headlines it finds, and ranks the links it collects.
module Rehash
  class Error < StandardError; end

  ROOT = Pathname.new(File.expand_path("..", __dir__))

  class << self
    def env
      ENV.fetch("APP_ENV", ENV.fetch("RACK_ENV", "development"))
    end

    def test?
      env == "test"
    end

    def config
      @config ||= Config.load
    end

    # Reset memoized state — used by the test suite and by `bin/crawl` when it
    # is handed a non-default configuration.
    def reset!
      @config = nil
      @db = nil
      @rewriter = nil
    end

    def db
      @db ||= Database.new(config.database_path)
    end

    def repo
      @repo ||= Repository.new(db)
    end

    def rewriter
      @rewriter ||= Rewriter.build(config.rewriter, config.rewriter_options)
    end

    def logger
      @logger ||= begin
        require "logger"
        log = Logger.new($stdout)
        log.level = test? ? Logger::FATAL : Logger::INFO
        log.formatter = ->(sev, time, _prog, msg) { "[#{time.strftime('%H:%M:%S')}] #{sev.ljust(5)} #{msg}\n" }
        log
      end
    end
  end
end

require_relative "rehash/config"
require_relative "rehash/database"
require_relative "rehash/repository"
require_relative "rehash/ranking"
require_relative "rehash/fetcher"
require_relative "rehash/crawler"
require_relative "rehash/rewriter"
