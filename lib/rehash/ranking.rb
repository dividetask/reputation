# frozen_string_literal: true

module Rehash
  # Reddit's "hot" ordering: a link's score decays against its age, so a story
  # needs exponentially more votes the older it gets.
  module Ranking
    EPOCH = 1_134_028_003 # reddit's own epoch, kept for comparable numbers
    GRAVITY = 45_000.0    # seconds; ~12.5h buys one order of magnitude

    module_function

    def hot(ups, downs, created_at)
      score = ups - downs
      order = Math.log10([score.abs, 1].max)
      sign = score <=> 0
      seconds = created_at.to_i - EPOCH
      ((sign * order) + (seconds / GRAVITY)).round(7)
    end

    # Wilson lower bound — the "best" ordering; stable for small vote counts.
    def confidence(ups, downs, z = 1.281551565545)
      n = ups + downs
      return 0.0 if n.zero?

      phat = ups.to_f / n
      left = phat + ((z * z) / (2 * n))
      right = z * Math.sqrt((phat * (1 - phat) + ((z * z) / (4 * n))) / n)
      under = 1 + ((z * z) / n)
      ((left - right) / under).round(7)
    end
  end
end
