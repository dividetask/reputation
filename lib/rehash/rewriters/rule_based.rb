# frozen_string_literal: true

require "cgi"

module Rehash
  module Rewriter
    # A deterministic, offline rewriter. It cannot invent a better headline,
    # but it strips the furniture publishers hang off them: section labels,
    # the trailing outlet name, shouting, hype clauses and stray punctuation.
    class RuleBased < Base
      MAX_LENGTH = 110

      # "BREAKING: ", "WATCH — ", "Exclusive | " …
      LABEL = /\A\s*(breaking(?:\s+news)?|just\s+in|live(?:\s+updates?)?|watch|video|photos?|
                     exclusive|update|opinion|analysis|explainer|editorial|sponsored)\b\s*[:\-|—–]\s*/xi

      # Hype tacked onto the end: "…, and here's why", "… — you won't believe it".
      HYPE_CLAUSE = /\s*[,—–-]\s*(and\s+)?(here(?:'?s|\s+is)\s+(why|what|how)[^,]*|
                                            you\s+won'?t\s+believe[^,]*|
                                            this\s+is\s+why[^,]*|
                                            what\s+happens\s+next[^,]*)\.?\s*\z/xi

      # Hype worth dropping only when it opens the headline — cutting these
      # mid-sentence tends to leave the grammar broken.
      SHOUTY = /\A(shocking|stunning|epic|insane|jaw[- ]dropping|mind[- ]blowing|
                    unbelievable)\b[\s:—–-]+/xi

      # Acronyms worth keeping upright when a headline arrives in all caps.
      ACRONYMS = %w[
        US USA UK EU UN NATO NASA FBI CIA WHO NHS AI ML GPU CPU CEO CFO CTO COVID
        IPO GDP AP BBC CNN NPR API SEC FDA EPA NYC LA UFC NFL NBA MLB EV OPEC IMF
      ].freeze

      def self.accepted_options = %i[]

      def name = "rule_based"

      def rewrite(title, source: nil)
        text = normalize(CGI.unescapeHTML(title.to_s))
        return "" if text.empty?

        text = strip_wrapping_quotes(text)
        text = text.sub(LABEL, "")
        text = strip_outlet(text, source)
        text = deshout(text) if shouting?(text)
        text = text.sub(HYPE_CLAUSE, "")
        text = text.sub(SHOUTY, "")
        text = normalize(text).sub(/[.\s…]+\z/, "")
        text = truncate(text)
        capitalize_first(text)
      end

      private

      def normalize(text)
        text.tr("‘’", "'")
            .tr("“”", '"')
            .gsub(" ", " ")
            .gsub(/\s+/, " ")
            .strip
      end

      def strip_wrapping_quotes(text)
        text =~ /\A"(.+)"\z/ ? Regexp.last_match(1) : text
      end

      # Drop a trailing outlet credit — " - Reuters", " | The Verge" — but only
      # when the tail is short and reads like a name rather than like the rest
      # of the sentence.
      def strip_outlet(text, source)
        parts = text.split(/\s+[|·]\s+|\s+[-–—]\s+/)
        return text if parts.size < 2

        tail = parts.last.strip
        head = text[0...(text.length - tail.length)].sub(/\s*[|·\-–—]\s*\z/, "").strip
        return text if head.split.size < 4
        return head if source && tail.casecmp?(source.name.to_s)
        return head if outlet_like?(tail)

        text
      end

      MINOR_WORDS = %w[the a an of and for at in on].freeze

      def outlet_like?(tail)
        words = tail.split
        return false if words.empty? || words.size > 4
        return false if tail.match?(/[.!?,;:]\z/)

        words.all? { |word| MINOR_WORDS.include?(word.downcase) || word.match?(/\A[A-Z]/) }
      end

      def shouting?(text)
        letters = text.gsub(/[^A-Za-z]/, "")
        return false if letters.length < 12

        letters.count("A-Z").to_f / letters.length > 0.85
      end

      def deshout(text)
        text.split(/(\s+)/).map do |word|
          bare = word.gsub(/[^A-Za-z]/, "")
          ACRONYMS.include?(bare) || bare == "I" ? word : word.downcase
        end.join
      end

      def truncate(text)
        return text if text.length <= MAX_LENGTH

        cut = text[0, MAX_LENGTH]
        cut = cut.sub(/\s+\S*\z/, "") if cut.length == MAX_LENGTH && text[MAX_LENGTH] != " "
        "#{cut.sub(/[\s,;:-]+\z/, '')}…"
      end

      def capitalize_first(text)
        return text if text.empty?

        text[0] = text[0].upcase
        text
      end
    end

    register(:rule_based, RuleBased)
  end
end
