# frozen_string_literal: true

require_relative "test_helper"

class RepositoryTest < Minitest::Test
  include TestHelpers

  def setup
    @repo = fresh_repo
  end

  def test_stores_a_post_and_derives_its_domain
    assert_equal :created, @repo.upsert_post(sample_item)
    post = @repo.posts.first.first
    assert_equal "example.com", post["domain"]
    assert_equal 1, post["ups"]
    assert_equal "A story happened", post["title"]
  end

  def test_recrawling_the_same_url_does_not_duplicate_it
    @repo.upsert_post(sample_item)
    assert_equal :skipped, @repo.upsert_post(sample_item)
    assert_equal 1, @repo.stats[:posts]
  end

  def test_a_changed_rewrite_updates_the_existing_post
    @repo.upsert_post(sample_item)
    assert_equal :updated, @repo.upsert_post(sample_item(title: "A better headline"))
    assert_equal 1, @repo.stats[:posts]
    assert_equal "A better headline", @repo.posts.first.first["title"]
  end

  def test_voting_moves_the_score_and_records_the_voter
    @repo.upsert_post(sample_item)
    id = @repo.posts.first.first["id"]

    assert_equal({ score: 2, value: 1 }, @repo.vote(id, "voter-1", 1))
    assert_equal 1, @repo.votes_by("voter-1", [id])[id]
    assert_equal 1, @repo.stats[:votes]
  end

  def test_voting_the_same_way_twice_takes_the_vote_back
    @repo.upsert_post(sample_item)
    id = @repo.posts.first.first["id"]

    @repo.vote(id, "voter-1", 1)
    assert_equal({ score: 1, value: 0 }, @repo.vote(id, "voter-1", 1))
    assert_empty @repo.votes_by("voter-1", [id])
  end

  def test_switching_from_up_to_down_moves_two_points
    @repo.upsert_post(sample_item)
    id = @repo.posts.first.first["id"]

    @repo.vote(id, "voter-1", 1)
    assert_equal({ score: 0, value: -1 }, @repo.vote(id, "voter-1", -1))
  end

  def test_voting_on_a_missing_post_returns_nil
    assert_nil @repo.vote(999, "voter-1", 1)
  end

  def test_listing_filters_by_community_and_query
    @repo.upsert_post(sample_item(url: "https://a.example/1", title: "Ferry news", community: "test"))
    @repo.upsert_post(sample_item(url: "https://b.example/2", title: "Bridge news", community: "links"))

    assert_equal 1, @repo.posts(community: "links").first.size
    assert_equal "Ferry news", @repo.posts(query: "ferry").first.first["title"]
    assert_empty @repo.posts(query: "nothing here").first
  end

  def test_sorting_by_new_uses_publication_time
    old = Time.now.to_i - 86_400
    @repo.upsert_post(sample_item(url: "https://a.example/old", title: "Old", published_at: old))
    @repo.upsert_post(sample_item(url: "https://b.example/new", title: "New"))

    assert_equal %w[New Old], @repo.posts(sort: "new").first.map { |p| p["title"] }
  end

  def test_sorting_by_top_uses_raw_score
    @repo.upsert_post(sample_item(url: "https://a.example/1", title: "Quiet"))
    @repo.upsert_post(sample_item(url: "https://b.example/2", title: "Popular"))
    popular = @repo.posts(query: "Popular").first.first["id"]
    5.times { |i| @repo.vote(popular, "voter-#{i}", 1) }

    assert_equal "Popular", @repo.posts(sort: "top").first.first["title"]
  end

  def test_pagination_reports_whether_more_rows_exist
    3.times { |i| @repo.upsert_post(sample_item(url: "https://a.example/#{i}")) }

    page, more = @repo.posts(per_page: 2)
    assert_equal 2, page.size
    assert more

    page, more = @repo.posts(per_page: 2, page: 2)
    assert_equal 1, page.size
    refute more
  end

  def test_prune_removes_old_links
    @repo.upsert_post(sample_item(url: "https://a.example/old", published_at: Time.now.to_i - (40 * 86_400)))
    @repo.upsert_post(sample_item(url: "https://b.example/new"))

    @repo.prune!(30)
    assert_equal 1, @repo.stats[:posts]
  end
end
