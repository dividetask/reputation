# frozen_string_literal: true

require "rss"
require "nokogiri"
require "uri"
require "time"

module Rehash
  # Walks the configured sources, turns whatever it finds into link items,
  # runs the headlines through the rewriter and stores the result.
  class Crawler
    Result = Struct.new(:created, :updated, :skipped, :errors, keyword_init: true) do
      def total = created + updated + skipped

      def to_s
        "#{created} new, #{updated} updated, #{skipped} unchanged, #{errors.size} errors"
      end
    end

    def initialize(config: Rehash.config, repo: Rehash.repo, rewriter: Rehash.rewriter,
                   fetcher: nil, logger: Rehash.logger)
      @config = config
      @repo = repo
      @rewriter = rewriter
      @logger = logger
      @fetcher = fetcher || Fetcher.new(
        user_agent: config.user_agent,
        timeout: config.timeout,
        respect_robots: config.respect_robots,
        delay: config.crawl_delay
      )
    end

    # `only` limits the run to a list of source keys or communities.
    def crawl_all(only: nil)
      result = Result.new(created: 0, updated: 0, skipped: 0, errors: [])

      selected(only).each do |source|
        begin
          crawl(source, into: result)
        rescue Fetcher::FetchError, Error => e
          @logger.warn("#{source.key}: #{e.message}")
          result.errors << "#{source.key}: #{e.message}"
        end
      end

      @logger.info("crawl finished — #{result}")
      result
    end

    def crawl(source, into: Result.new(created: 0, updated: 0, skipped: 0, errors: []))
      @logger.info("crawling #{source.key} (#{source.url})")
      response = @fetcher.get(source.url)
      items = extract(source, response).first(source.max_items)
      @logger.info("#{source.key}: #{items.size} items")

      rewrite!(items, source).each do |item|
        case @repo.upsert_post(item)
        when :created then into.created += 1
        when :updated then into.updated += 1
        else into.skipped += 1
        end
      end

      into
    end

    def extract(source, response)
      items = source.html? ? parse_html(source, response) : parse_feed(source, response)
      items
        .reject { |item| item[:url].to_s.empty? || item[:original_title].to_s.empty? }
        .uniq { |item| item[:url] }
    end

    private

    def selected(only)
      return @config.sources if only.nil? || Array(only).empty?

      wanted = Array(only).map(&:to_s)
      @config.sources.select { |s| wanted.include?(s.key) || wanted.include?(s.community) }
    end

    def parse_feed(source, response)
      feed = RSS::Parser.parse(response.body, false)
      raise Error, "#{source.key}: not a parseable feed" if feed.nil?

      feed.items.map do |item|
        {
          url: absolutize(feed_link(item), response.url),
          original_title: clean_text(feed_title(item)),
          summary: clean_text(feed_summary(item))&.slice(0, 500),
          author: feed_author(item),
          published_at: feed_date(item)
        }.merge(source_fields(source))
      end
    end

    def parse_html(source, response)
      doc = Nokogiri::HTML(response.body)
      sel = source.selectors

      doc.css(sel[:item].to_s).map do |node|
        title_node = sel[:title] ? node.at_css(sel[:title].to_s) : node
        link_node = sel[:link] ? node.at_css(sel[:link].to_s) : (node["href"] ? node : node.at_css("a[href]"))
        summary_node = sel[:summary] ? node.at_css(sel[:summary].to_s) : nil
        next if title_node.nil? || link_node.nil?

        {
          url: absolutize(link_node["href"], response.url),
          original_title: clean_text(title_node.text),
          summary: clean_text(summary_node&.text)&.slice(0, 500),
          author: nil,
          published_at: nil
        }.merge(source_fields(source))
      end.compact
    end

    def source_fields(source)
      {
        source_key: source.key,
        source_name: source.name,
        community: source.community
      }
    end

    # Titles are rewritten in one batch per source so an LLM-backed rewriter
    # can share a single request (and a single prompt) across the whole page.
    def rewrite!(items, source)
      titles = items.map { |item| item[:original_title] }
      rewritten = @rewriter.rewrite_all(titles, source: source)

      items.each_with_index do |item, index|
        item[:title] = rewritten[index].to_s.empty? ? item[:original_title] : rewritten[index]
        item[:rewriter] = @rewriter.name
      end
    end

    def absolutize(href, base)
      return nil if href.to_s.strip.empty?

      url = URI.join(base, href.to_s.strip)
      return nil unless url.is_a?(URI::HTTP)

      url.fragment = nil
      url.to_s
    rescue URI::Error
      nil
    end

    def clean_text(text)
      return nil if text.nil?

      text.to_s.gsub(/\s+/, " ").strip
    end

    def feed_title(item)
      title = item.respond_to?(:title) ? item.title : nil
      title.respond_to?(:content) ? title.content : title
    end

    def feed_link(item)
      link = item.link
      return link.href if link.respond_to?(:href)
      return link unless link.nil?

      item.respond_to?(:links) ? item.links.map(&:href).compact.first : nil
    end

    def feed_summary(item)
      raw = if item.respond_to?(:description) && item.description
              item.description
            elsif item.respond_to?(:summary) && item.summary
              item.summary.respond_to?(:content) ? item.summary.content : item.summary
            elsif item.respond_to?(:content) && item.content
              item.content.respond_to?(:content) ? item.content.content : item.content
            end
      raw && Nokogiri::HTML(raw.to_s).text
    end

    def feed_author(item)
      author = item.respond_to?(:author) ? item.author : nil
      return author.name.content if author.respond_to?(:name) && author.name.respond_to?(:content)

      author.is_a?(String) ? author : nil
    rescue StandardError
      nil
    end

    def feed_date(item)
      %i[pubDate date updated published dc_date].each do |method|
        next unless item.respond_to?(method)

        value = item.public_send(method)
        value = value.content if value.respond_to?(:content)
        return value.to_time if value.respond_to?(:to_time)
        return Time.parse(value.to_s) if value
      rescue StandardError
        next
      end
      nil
    end
  end
end
