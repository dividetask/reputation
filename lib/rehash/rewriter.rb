# frozen_string_literal: true

module Rehash
  # Headline rewriting is pluggable: pick one with the REWRITER env var.
  #
  #   rule_based (default) — offline, deterministic de-clickbaiting
  #   claude               — genuine rewrites via the Anthropic API
  #   none                 — keep the publisher's headline verbatim
  module Rewriter
    REGISTRY = {}

    class << self
      def register(name, klass)
        REGISTRY[name.to_sym] = klass
      end

      def build(name, options = {})
        klass = REGISTRY.fetch(name.to_sym) do
          raise Error, "unknown rewriter #{name.inspect} (have: #{REGISTRY.keys.join(', ')})"
        end
        klass.new(**options.slice(*klass.accepted_options))
      end
    end

    # Rewriters only have to implement #rewrite; batching is free.
    class Base
      def self.accepted_options = []

      def name
        self.class.name.split("::").last
             .gsub(/([a-z])([A-Z])/, '\1_\2').downcase
      end

      def rewrite(title, source: nil)
        title
      end

      def rewrite_all(titles, source: nil)
        titles.map { |title| rewrite(title, source: source) }
      end
    end

    # Leaves headlines exactly as published.
    class Passthrough < Base
      def name = "none"
    end
    register(:none, Passthrough)
  end
end

require_relative "rewriters/rule_based"
require_relative "rewriters/claude"
