# frozen_string_literal: true

require_relative "test_helper"

class CrawlerTest < Minitest::Test
  include TestHelpers

  def setup
    @config = Rehash::Config.load(File.expand_path("fixtures/sources.yml", __dir__))
    @repo = fresh_repo
    @fetcher = StubFetcher.new(
      "https://example.com/feed.xml" => fixture("feed.xml"),
      "https://example.com/list" => fixture("page.html")
    )
    @crawler = Rehash::Crawler.new(
      config: @config, repo: @repo, rewriter: Rehash::Rewriter.build(:rule_based),
      fetcher: @fetcher, logger: Rehash.logger
    )
  end

  def feed_source = @config.source("example-feed")
  def page_source = @config.source("example-page")

  def test_parses_a_feed_into_items
    items = @crawler.extract(feed_source, @fetcher.get(feed_source.url))

    assert_equal 2, items.size # the duplicate link is dropped
    first = items.first
    assert_equal "https://example.com/bridge", first[:url]
    assert_equal "BREAKING: Council Approves Bridge Repair - Example Feed", first[:original_title]
    assert_equal "The vote was 7-2.", first[:summary]
    assert_equal Time.utc(2025, 9, 1, 9, 0, 0), first[:published_at].utc
    assert_equal "test", first[:community]
  end

  def test_scrapes_an_html_page_with_selectors
    items = @crawler.extract(page_source, @fetcher.get(page_source.url))

    assert_equal 2, items.size # the row without a link is skipped
    assert_equal "https://example.com/first-thing", items.first[:url]
    assert_equal "The First Thing", items.first[:original_title]
    assert_equal "A blurb about the first thing.", items.first[:summary]
    assert_equal "https://elsewhere.example/second", items.last[:url]
  end

  def test_crawling_rewrites_headlines_and_stores_them
    @crawler.crawl(feed_source)
    posts, = @repo.posts(sort: "new")

    assert_equal 2, posts.size
    bridge = posts.find { |p| p["url"] == "https://example.com/bridge" }
    assert_equal "Council Approves Bridge Repair", bridge["title"]
    assert_equal "BREAKING: Council Approves Bridge Repair - Example Feed", bridge["original_title"]
    assert_equal "rule_based", bridge["rewriter"]
  end

  def test_a_second_crawl_adds_nothing_new
    @crawler.crawl_all
    first = @repo.stats[:posts]
    result = @crawler.crawl_all

    assert_equal first, @repo.stats[:posts]
    assert_equal 0, result.created
    assert_equal result.total, result.skipped
  end

  def test_crawl_all_covers_every_source_and_can_be_narrowed
    result = @crawler.crawl_all
    assert_equal 4, result.created
    assert_empty result.errors
    assert_equal %w[links test], @repo.communities.map { |c| c["community"] }.sort

    narrowed = Rehash::Crawler.new(config: @config, repo: fresh_repo,
                                   rewriter: Rehash::Rewriter.build(:none),
                                   fetcher: @fetcher, logger: Rehash.logger)
    assert_equal 2, narrowed.crawl_all(only: %w[links]).created
  end

  def test_a_failing_source_is_reported_without_stopping_the_crawl
    crawler = Rehash::Crawler.new(
      config: @config, repo: @repo, rewriter: Rehash::Rewriter.build(:none),
      fetcher: StubFetcher.new("https://example.com/list" => fixture("page.html")),
      logger: Rehash.logger
    )
    result = crawler.crawl_all

    assert_equal 2, result.created
    assert_equal 1, result.errors.size
    assert_match(/example-feed/, result.errors.first)
  end
end
