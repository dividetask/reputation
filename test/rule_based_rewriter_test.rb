# frozen_string_literal: true

require_relative "test_helper"

class RuleBasedRewriterTest < Minitest::Test
  include TestHelpers

  def setup
    @rewriter = Rehash::Rewriter::RuleBased.new
  end

  def rewrite(title, source: nil) = @rewriter.rewrite(title, source: source)

  def test_strips_section_labels
    assert_equal "Council approves bridge repair", rewrite("BREAKING: Council approves bridge repair")
    assert_equal "Ferry service resumes", rewrite("Watch | Ferry service resumes")
  end

  def test_strips_the_trailing_outlet_name
    assert_equal "Markets tumble as investors flee",
                 rewrite("Markets tumble as investors flee - Reuters")
    assert_equal "Scientists find water on a distant moon",
                 rewrite("Scientists find water on a distant moon | The Guardian")
  end

  def test_keeps_a_trailing_clause_that_is_part_of_the_sentence
    title = "Nvidia beats earnings - analysts say the boom is not over yet"
    assert_equal title, rewrite(title)
  end

  def test_strips_the_outlet_named_by_the_source
    source = sample_source(name: "Example Feed")
    assert_equal "Council approves bridge repair",
                 rewrite("Council approves bridge repair - Example Feed", source: source)
  end

  def test_de_shouts_all_caps_headlines_but_keeps_acronyms
    assert_equal "NASA confirms the US launch date",
                 rewrite("NASA CONFIRMS THE US LAUNCH DATE")
  end

  def test_drops_teaser_clauses
    assert_equal "New study links coffee to longer life",
                 rewrite("New study links coffee to longer life, and here's why")
  end

  def test_unescapes_entities_and_collapses_whitespace
    assert_equal '"Quoted" headline from a feed',
                 rewrite("  &quot;Quoted&quot;   headline  from a feed  ")
  end

  def test_truncates_at_a_word_boundary
    long = "#{'word ' * 40}end"
    result = rewrite(long)
    assert_operator result.length, :<=, Rehash::Rewriter::RuleBased::MAX_LENGTH + 1
    assert result.end_with?("…")
    refute_match(/\s…\z/, result)
  end

  def test_leaves_a_clean_headline_alone
    title = "Storm delays ferry service"
    assert_equal title, rewrite(title)
  end

  def test_passthrough_rewriter_changes_nothing
    rewriter = Rehash::Rewriter.build(:none)
    assert_equal "BREAKING: Anything - Reuters", rewriter.rewrite("BREAKING: Anything - Reuters")
    assert_equal "none", rewriter.name
  end
end
