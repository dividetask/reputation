# frozen_string_literal: true

module Rehash
  # Optional in-process crawl loop, enabled by CRAWL_INTERVAL (seconds).
  # For anything serious, run `bin/crawl` from cron instead.
  class Scheduler
    def self.start(interval: Rehash.config.crawl_interval, logger: Rehash.logger)
      return nil unless interval.to_i.positive?

      logger.info("background crawler enabled — every #{interval}s")
      Thread.new do
        Thread.current.name = "rehash-crawler"
        Thread.current.abort_on_exception = false
        loop do
          begin
            Crawler.new.crawl_all
          rescue StandardError => e
            logger.error("background crawl failed: #{e.class}: #{e.message}")
          end
          sleep interval
        end
      end
    end
  end
end
