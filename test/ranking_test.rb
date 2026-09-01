# frozen_string_literal: true

require_relative "test_helper"

class RankingTest < Minitest::Test
  include TestHelpers

  def test_newer_post_outranks_older_post_with_equal_score
    now = Time.now.to_i
    assert Rehash::Ranking.hot(10, 0, now) > Rehash::Ranking.hot(10, 0, now - 86_400)
  end

  def test_more_votes_outrank_fewer_at_the_same_age
    now = Time.now.to_i
    assert Rehash::Ranking.hot(100, 0, now) > Rehash::Ranking.hot(10, 0, now)
  end

  def test_an_order_of_magnitude_of_votes_beats_half_a_day_of_age
    now = Time.now.to_i
    assert Rehash::Ranking.hot(100, 0, now - 43_200) > Rehash::Ranking.hot(10, 0, now)
  end

  def test_downvotes_sink_a_post_below_an_unvoted_one
    now = Time.now.to_i
    assert Rehash::Ranking.hot(1, 50, now) < Rehash::Ranking.hot(1, 0, now)
  end

  def test_confidence_prefers_a_consistent_record_over_a_lucky_one
    assert Rehash::Ranking.confidence(90, 10) > Rehash::Ranking.confidence(3, 0)
    assert_equal 0.0, Rehash::Ranking.confidence(0, 0)
  end
end
