# frozen_string_literal: true

require "yaml"

module Rehash
  # One crawlable site. `type` is :feed (RSS/Atom) or :html (CSS selectors).
  Source = Struct.new(
    :key, :name, :community, :type, :url, :max_items, :selectors,
    keyword_init: true
  ) do
    def feed?  = type == :feed
    def html?  = type == :html
  end

  # Application configuration: the source list from config/sources.yml plus a
  # handful of environment-driven knobs.
  class Config
    DEFAULT_SOURCES_PATH = -> { Rehash::ROOT.join("config/sources.yml") }

    attr_reader :sources, :defaults, :sources_path

    def self.load(path = nil)
      path ||= ENV["SOURCES_FILE"] || DEFAULT_SOURCES_PATH.call
      new(YAML.safe_load_file(path.to_s, aliases: true) || {}, path)
    end

    def initialize(doc, path = nil)
      @sources_path = path
      @defaults = symbolize(doc["defaults"] || {})
      @sources = Array(doc["sources"]).map { |raw| build_source(raw) }
      validate!
    end

    def source(key)
      sources.find { |s| s.key == key.to_s }
    end

    def communities
      sources.map(&:community).uniq.sort
    end

    def database_path
      ENV["DATABASE_PATH"] || Rehash::ROOT.join("db", "rehash.#{Rehash.env}.sqlite3").to_s
    end

    # :rule_based (default, offline), :claude (Anthropic API) or :none.
    def rewriter
      (ENV["REWRITER"] || "rule_based").to_sym
    end

    def rewriter_options
      {
        model: ENV.fetch("ANTHROPIC_MODEL", "claude-opus-5"),
        api_key: ENV["ANTHROPIC_API_KEY"],
        batch_size: Integer(ENV.fetch("REWRITE_BATCH_SIZE", 12)),
        style: ENV["REWRITE_STYLE"]
      }
    end

    def user_agent
      ENV.fetch("USER_AGENT", "RehashBot/0.1 (+https://github.com/dividetask/reputation)")
    end

    def timeout        = Integer(defaults.fetch(:timeout, 12))
    def crawl_delay    = Float(defaults.fetch(:crawl_delay, 1.0))
    def respect_robots = defaults.fetch(:respect_robots, true)

    # Seconds between automatic background crawls; 0 disables the thread.
    def crawl_interval = Integer(ENV.fetch("CRAWL_INTERVAL", 0))

    private

    def build_source(raw)
      raw = symbolize(raw)
      Source.new(
        key: raw.fetch(:key).to_s,
        name: raw[:name] || raw.fetch(:key).to_s,
        community: (raw[:community] || "all").to_s.downcase,
        type: (raw[:type] || "feed").to_sym,
        url: raw.fetch(:url).to_s,
        max_items: Integer(raw[:max_items] || @defaults.fetch(:max_items, 25)),
        selectors: symbolize(raw[:selectors] || {})
      )
    end

    def validate!
      dupes = sources.map(&:key).tally.select { |_, n| n > 1 }.keys
      raise Error, "duplicate source keys: #{dupes.join(', ')}" if dupes.any?

      sources.each do |source|
        unless %i[feed html].include?(source.type)
          raise Error, "source #{source.key}: unknown type #{source.type.inspect}"
        end
        if source.html? && source.selectors[:item].to_s.empty?
          raise Error, "source #{source.key}: html sources need selectors.item"
        end
      end
    end

    def symbolize(hash)
      hash.each_with_object({}) { |(k, v), out| out[k.to_sym] = v }
    end
  end
end
