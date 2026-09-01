# frozen_string_literal: true

require "net/http"
require "uri"
require "monitor"

module Rehash
  # A small, polite HTTP client: identifies itself, follows redirects, obeys
  # robots.txt and keeps a per-host delay between requests.
  class Fetcher
    include MonitorMixin

    Response = Struct.new(:status, :body, :url, :content_type, keyword_init: true) do
      def ok? = status.between?(200, 299)
      def html? = content_type.to_s.include?("html")
    end

    class FetchError < Error; end
    class Disallowed < FetchError; end

    MAX_REDIRECTS = 5
    MAX_BYTES = 5 * 1024 * 1024

    def initialize(user_agent: "RehashBot/0.1", timeout: 12, respect_robots: true, delay: 1.0)
      super()
      @user_agent = user_agent
      @timeout = timeout
      @respect_robots = respect_robots
      @delay = delay
      @robots = {}
      @last_hit = {}
    end

    def get(url, redirects: MAX_REDIRECTS)
      uri = normalize(url)
      raise Disallowed, "robots.txt disallows #{uri}" unless allowed?(uri)

      throttle(uri.host)
      response = request(uri)

      case response
      when Net::HTTPRedirection
        raise FetchError, "too many redirects for #{url}" if redirects.zero?

        location = URI.join(uri, response["location"].to_s)
        return get(location, redirects: redirects - 1)
      when Net::HTTPSuccess
        Response.new(
          status: response.code.to_i,
          body: truncate(response.body.to_s),
          url: uri.to_s,
          content_type: response["content-type"]
        )
      else
        raise FetchError, "#{uri} returned #{response.code}"
      end
    end

    def allowed?(url)
      return true unless @respect_robots

      uri = normalize(url)
      rules = robots_for(uri)
      path = uri.path.empty? ? "/" : uri.path
      path += "?#{uri.query}" if uri.query
      rules.none? { |rule| path.start_with?(rule) }
    end

    private

    def normalize(url)
      uri = url.is_a?(URI) ? url : URI.parse(url.to_s.strip)
      raise FetchError, "unsupported URL: #{url}" unless uri.is_a?(URI::HTTP)

      uri
    end

    def request(uri)
      req = Net::HTTP::Get.new(uri)
      req["User-Agent"] = @user_agent
      req["Accept"] = "text/html,application/xhtml+xml,application/xml,application/rss+xml;q=0.9,*/*;q=0.8"

      Net::HTTP.start(uri.host, uri.port,
                      use_ssl: uri.scheme == "https",
                      open_timeout: @timeout,
                      read_timeout: @timeout) do |http|
        http.request(req)
      end
    rescue SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError, SocketError => e
      raise FetchError, "#{uri}: #{e.class}: #{e.message}"
    end

    def truncate(body)
      body.bytesize > MAX_BYTES ? body.byteslice(0, MAX_BYTES) : body
    end

    def throttle(host)
      wait = synchronize do
        last = @last_hit[host]
        @last_hit[host] = Time.now
        last ? @delay - (Time.now - last) : 0
      end
      sleep(wait) if wait.positive?
    end

    # Cached, deliberately simple robots.txt support: the `*` group plus any
    # group naming our own agent token. Unreachable robots.txt means "allowed".
    def robots_for(uri)
      key = "#{uri.scheme}://#{uri.host}:#{uri.port}"
      synchronize { return @robots[key] if @robots.key?(key) }

      rules = begin
        body = request(URI.join(key, "/robots.txt"))
        body.is_a?(Net::HTTPSuccess) ? parse_robots(body.body.to_s) : []
      rescue FetchError
        []
      end

      synchronize { @robots[key] = rules }
      rules
    end

    def parse_robots(text)
      token = @user_agent.split("/").first.to_s.downcase
      groups = Hash.new { |h, k| h[k] = [] }
      agents = []
      previous_field = nil

      text.each_line do |line|
        field, value = line.sub(/#.*/, "").strip.split(":", 2)
        next if value.nil?

        field = field.strip.downcase
        value = value.strip

        case field
        when "user-agent"
          agents = [] unless previous_field == "user-agent"
          agents << value.downcase
        when "disallow"
          agents.each { |agent| groups[agent] << value unless value.empty? }
        end
        previous_field = field
      end

      (groups["*"] + groups[token]).uniq
    end
  end
end
