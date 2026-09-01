# frozen_string_literal: true

require_relative "test_helper"

class WebTest < Minitest::Test
  include Rack::Test::Methods
  include TestHelpers

  def app = Rehash::Web

  def setup
    Rehash.db.execute("DELETE FROM votes")
    Rehash.db.execute("DELETE FROM posts")
    @repo = Rehash.repo
    @repo.upsert_post(sample_item(url: "https://a.example/ferry", title: "Storm delays ferry service",
                                  original_title: "BREAKING: Storm Delays Ferry Service - Example",
                                  community: "test"))
    @repo.upsert_post(sample_item(url: "https://b.example/bridge", title: "Council approves bridge repair",
                                  original_title: "Council approves bridge repair",
                                  community: "links"))
  end

  def post_id(title)
    @repo.posts(query: title).first.first["id"]
  end

  def test_front_page_lists_every_community
    get "/"

    assert last_response.ok?
    assert_includes last_response.body, "Storm delays ferry service"
    assert_includes last_response.body, "Council approves bridge repair"
    assert_includes last_response.body, "a.example"
  end

  def test_front_page_shows_the_original_headline_alongside_the_rewrite
    get "/"

    assert_includes last_response.body, "BREAKING: Storm Delays Ferry Service - Example"
    assert_includes last_response.body, "rewritten headline"
  end

  def test_community_pages_filter_the_listing
    get "/r/links"

    assert last_response.ok?
    assert_includes last_response.body, "Council approves bridge repair"
    refute_includes last_response.body, "Storm delays ferry service"
  end

  def test_search_filters_the_listing
    get "/", q: "ferry"

    assert_includes last_response.body, "Storm delays ferry service"
    refute_includes last_response.body, "Council approves bridge repair"
  end

  def test_sort_tabs_are_linked_and_marked
    get "/", sort: "new"

    assert last_response.ok?
    assert_match(/class="active"[^>]*>new|>new<\/a>/, last_response.body)
  end

  def test_voting_returns_the_new_score_as_json
    id = post_id("ferry")
    header "Accept", "application/json"
    post "/posts/#{id}/vote", value: "1"

    assert last_response.ok?
    assert_equal({ "score" => 2, "value" => 1 }, JSON.parse(last_response.body))
  end

  def test_voting_twice_takes_the_vote_back
    id = post_id("ferry")
    header "Accept", "application/json"
    post "/posts/#{id}/vote", value: "1"
    post "/posts/#{id}/vote", value: "1"

    assert_equal 1, JSON.parse(last_response.body)["score"]
  end

  def test_voting_without_javascript_redirects_back
    id = post_id("ferry")
    header "Accept", "text/html"
    post "/posts/#{id}/vote", { value: "1" }, "HTTP_REFERER" => "http://example.org/r/test"

    assert_equal 302, last_response.status
    assert last_response.headers["Location"].end_with?("/r/test")
  end

  def test_votes_are_tied_to_a_cookie_and_shown_as_selected
    id = post_id("ferry")
    header "Accept", "application/json"
    post "/posts/#{id}/vote", value: "1"

    header "Accept", "text/html"
    get "/"
    assert_includes last_response.body, "arrow up on"
  end

  def test_voting_on_a_missing_post_is_a_404
    post "/posts/9999/vote", value: "1"
    assert_equal 404, last_response.status
  end

  def test_feed_serves_rewritten_headlines_with_the_originals
    get "/feed.xml"

    assert last_response.ok?
    assert_includes last_response.content_type, "rss+xml"
    assert_includes last_response.body, "<title>Storm delays ferry service</title>"
    assert_includes last_response.body, "Originally: BREAKING: Storm Delays Ferry Service - Example"
  end

  def test_community_feed_is_filtered
    get "/r/links/feed.xml"

    assert_includes last_response.body, "Council approves bridge repair"
    refute_includes last_response.body, "Storm delays ferry service"
  end

  def test_about_page_lists_configured_sources
    get "/about"

    assert last_response.ok?
    assert_includes last_response.body, "Example Feed"
  end

  def test_health_check
    get "/healthz"

    payload = JSON.parse(last_response.body)
    assert_equal "ok", payload["status"]
    assert_equal 2, payload["posts"]
  end

  def test_unknown_paths_render_a_404_page
    get "/nope"

    assert_equal 404, last_response.status
    assert_includes last_response.body, "No such page"
  end

  def test_empty_listing_explains_how_to_populate_it
    Rehash.db.execute("DELETE FROM posts")
    get "/"

    assert_includes last_response.body, "bin/crawl"
  end
end
