# frozen_string_literal: true

ENV["APP_ENV"] = "test"
ENV["RACK_ENV"] = "test"
ENV["DATABASE_PATH"] = ":memory:"
ENV["REWRITER"] ||= "rule_based"
ENV["SOURCES_FILE"] ||= File.expand_path("fixtures/sources.yml", __dir__)

require "minitest/autorun"
require "rack/test"
require_relative "../lib/rehash"
require_relative "../lib/rehash/web"

module TestHelpers
  def fixture(name)
    File.read(File.expand_path("fixtures/#{name}", __dir__))
  end

  def fresh_repo
    Rehash::Repository.new(Rehash::Database.new(":memory:"))
  end

  def sample_source(overrides = {})
    Rehash::Source.new({
      key: "example", name: "Example", community: "test",
      type: :feed, url: "https://example.com/feed.xml",
      max_items: 25, selectors: {}
    }.merge(overrides))
  end

  def sample_item(overrides = {})
    {
      url: "https://example.com/a-story",
      original_title: "A Story Happened - Example",
      title: "A story happened",
      rewriter: "rule_based",
      summary: "Some summary.",
      author: nil,
      source_key: "example",
      source_name: "Example",
      community: "test",
      published_at: Time.now.to_i
    }.merge(overrides)
  end

  # A fetcher that serves canned bodies instead of touching the network.
  class StubFetcher
    def initialize(responses) = @responses = responses

    def get(url, **)
      body = @responses.fetch(url.to_s) { raise Rehash::Fetcher::FetchError, "unexpected fetch: #{url}" }
      Rehash::Fetcher::Response.new(status: 200, body: body, url: url.to_s, content_type: "text/xml")
    end
  end
end
