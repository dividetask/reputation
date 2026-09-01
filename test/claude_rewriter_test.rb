# frozen_string_literal: true

require "json"
require_relative "test_helper"

class ClaudeRewriterTest < Minitest::Test
  include TestHelpers

  # Stands in for Anthropic::Client: records the request and replays whatever
  # the block returns as a message with a single text block.
  class FakeClient
    Block = Struct.new(:type, :text)
    Message = Struct.new(:content)

    attr_reader :requests

    def initialize(&responder)
      @responder = responder
      @requests = []
    end

    def messages = self

    def create(**params)
      @requests << params
      Message.new([Block.new(:text, @responder.call(params))])
    end
  end

  def rewriter(client)
    Rehash::Rewriter::Claude.new(model: "claude-opus-5", api_key: "test-key",
                                 batch_size: 2, client: client, logger: Rehash.logger)
  end

  def test_returns_one_rewrite_per_headline_in_order
    client = FakeClient.new { { headlines: ["First rewrite", "Second rewrite"] }.to_json }

    assert_equal ["First rewrite", "Second rewrite"],
                 rewriter(client).rewrite_all(["First original", "Second original"])
  end

  def test_sends_the_configured_model_and_a_json_schema
    client = FakeClient.new { { headlines: ["Rewritten"] }.to_json }
    rewriter(client).rewrite_all(["Original"], source: sample_source)
    request = client.requests.first

    assert_equal :"claude-opus-5", request[:model]
    assert_equal :json_schema, request[:output_config][:format_][:type]
    assert_equal :low, request[:output_config][:effort]
    assert_match(/Rewrite these 1 headlines/, request[:messages].first[:content])
    assert_match(/Source: Example/, request[:messages].first[:content])
  end

  def test_headlines_are_sent_in_batches
    client = FakeClient.new do |params|
      count = params[:messages].first[:content].scan(/^\d+\. /).size
      { headlines: Array.new(count) { |i| "Rewrite #{i}" } }.to_json
    end

    assert_equal 3, rewriter(client).rewrite_all(%w[one two three]).size
    assert_equal 2, client.requests.size
  end

  def test_an_api_failure_falls_back_to_the_rule_based_rewriter
    client = FakeClient.new { raise "connection reset" }

    assert_equal ["Council approves bridge repair"],
                 rewriter(client).rewrite_all(["BREAKING: Council approves bridge repair"])
  end

  def test_a_short_answer_falls_back_rather_than_misaligning_headlines
    client = FakeClient.new { { headlines: ["Only one"] }.to_json }

    assert_equal ["First original", "Second original"],
                 rewriter(client).rewrite_all(["First original", "Second original"])
  end

  def test_a_blank_rewrite_keeps_the_original_headline
    client = FakeClient.new { { headlines: ["  "] }.to_json }

    assert_equal ["Original headline"], rewriter(client).rewrite_all(["Original headline"])
  end

  def test_house_style_is_appended_to_the_system_prompt
    client = FakeClient.new { { headlines: ["Rewritten"] }.to_json }
    Rehash::Rewriter::Claude.new(api_key: "k", batch_size: 5, style: "Be dry and literal.",
                                 client: client).rewrite_all(["Original"])

    assert_match(/Be dry and literal\./, client.requests.first[:system_])
  end

  def test_missing_api_key_is_reported_as_a_failure_and_falls_back
    rewriter = Rehash::Rewriter::Claude.new(api_key: nil, logger: Rehash.logger)

    assert_equal ["Council approves bridge repair"],
                 rewriter.rewrite_all(["BREAKING: Council approves bridge repair"])
    refute rewriter.available?
  end
end
