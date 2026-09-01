# frozen_string_literal: true

require "json"

module Rehash
  module Rewriter
    # Rewrites headlines with the Anthropic API. Headlines are sent in batches
    # so one request covers a whole page of a source, and structured outputs
    # guarantee a parseable answer. Any failure falls back to the rule-based
    # rewriter, so a missing API key or a rate limit never breaks a crawl.
    class Claude < Base
      DEFAULT_MODEL = "claude-opus-5"
      MAX_TOKENS = 8_000

      SYSTEM = <<~PROMPT
        You rewrite headlines for a link aggregator.

        For each headline, produce one plain, accurate rewrite that:
        - says what actually happened, in under 100 characters
        - uses sentence case and no trailing period
        - drops hype, teasers, cliffhangers and the outlet's name
        - keeps names, numbers, places and hedges ("may", "reportedly") intact
        - never adds facts that are not in the original, and never guesses at
          what a vague headline is hiding — rephrase what is there

        Return one rewrite per input headline, in the same order.
      PROMPT

      SCHEMA = {
        type: "object",
        properties: {
          headlines: {
            type: "array",
            items: { type: "string" }
          }
        },
        required: ["headlines"],
        additionalProperties: false
      }.freeze

      def self.accepted_options = %i[model api_key batch_size style client logger]

      attr_reader :model, :batch_size

      def initialize(model: DEFAULT_MODEL, api_key: nil, batch_size: 12, style: nil,
                     client: nil, logger: nil)
        @model = model || DEFAULT_MODEL
        @api_key = api_key || ENV["ANTHROPIC_API_KEY"]
        @batch_size = [batch_size.to_i, 1].max
        @style = style
        @client = client
        @logger = logger || Rehash.logger
        @fallback = RuleBased.new
      end

      def name = "claude"

      def rewrite(title, source: nil)
        rewrite_all([title], source: source).first
      end

      def rewrite_all(titles, source: nil)
        return [] if titles.empty?

        titles.each_slice(@batch_size).flat_map do |batch|
          rewrite_batch(batch, source)
        rescue StandardError => e
          @logger.warn("claude rewriter failed (#{e.class}: #{e.message}); using rule-based fallback")
          @fallback.rewrite_all(batch, source: source)
        end
      end

      def available?
        !client.nil?
      rescue StandardError
        false
      end

      private

      def rewrite_batch(batch, source)
        response = client.messages.create(
          model: model.to_sym,
          max_tokens: MAX_TOKENS,
          output_config: { effort: :low, format_: { type: :json_schema, schema: SCHEMA } },
          system_: SYSTEM + style_instruction.to_s,
          messages: [{ role: "user", content: user_prompt(batch, source) }]
        )

        headlines = parse(response)
        raise Error, "expected #{batch.size} rewrites, got #{headlines.size}" if headlines.size != batch.size

        headlines.each_with_index.map do |headline, index|
          headline.to_s.strip.empty? ? batch[index] : headline.to_s.strip
        end
      end

      def user_prompt(batch, source)
        context = source ? "Source: #{source.name} (#{source.community})\n\n" : ""
        listing = batch.each_with_index.map { |title, i| "#{i + 1}. #{title}" }.join("\n")
        "#{context}Rewrite these #{batch.size} headlines:\n\n#{listing}"
      end

      def style_instruction
        return nil if @style.to_s.strip.empty?

        "\nAdditional house style: #{@style.strip}\n"
      end

      def parse(response)
        text = response.content.select { |block| block.type == :text }.map(&:text).join
        JSON.parse(text).fetch("headlines")
      end

      def client
        @client ||= begin
          require "anthropic"
          raise Error, "ANTHROPIC_API_KEY is not set" if @api_key.to_s.empty?

          Anthropic::Client.new(api_key: @api_key)
        end
      end
    end

    register(:claude, Claude)
  end
end
