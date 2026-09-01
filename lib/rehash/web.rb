# frozen_string_literal: true

require "sinatra/base"
require "securerandom"
require "cgi"
require "json"
require_relative "../rehash"

module Rehash
  # The reddit-style front end: ranked link listings, per-community sections
  # and cookie-identified voting.
  class Web < Sinatra::Base
    set :root, Rehash::ROOT.to_s
    set :views, Rehash::ROOT.join("views").to_s
    set :public_folder, Rehash::ROOT.join("public").to_s
    set :static, true
    set :show_exceptions, false
    set :raise_errors, false
    set :logging, !Rehash.test?

    VOTER_COOKIE = "rehash_voter"

    helpers do
      def repo = Rehash.repo

      def voter
        @voter ||= begin
          existing = request.cookies[VOTER_COOKIE]
          id = existing && existing.match?(/\A[0-9a-f]{32}\z/) ? existing : SecureRandom.hex(16)
          unless existing == id
            response.set_cookie(VOTER_COOKIE,
                                value: id, path: "/", httponly: true,
                                same_site: :lax, max_age: 60 * 60 * 24 * 365)
          end
          id
        end
      end

      def h(text) = CGI.escapeHTML(text.to_s)

      def time_ago(timestamp)
        return "just now" if timestamp.nil?

        seconds = Time.now.to_i - timestamp.to_i
        return "just now" if seconds < 60

        [[31_536_000, "year"], [2_592_000, "month"], [86_400, "day"],
         [3600, "hour"], [60, "minute"]].each do |span, label|
          next if seconds < span

          count = seconds / span
          return "#{count} #{label}#{'s' unless count == 1} ago"
        end
        "just now"
      end

      def score_of(post) = post["ups"].to_i - post["downs"].to_i

      def link_to_sort(sort)
        params_for(sort: sort, page: nil)
      end

      def params_for(overrides = {})
        merged = { "sort" => @sort, "q" => @query, "page" => @page }
                 .merge(overrides.transform_keys(&:to_s))
        merged.delete("page") if merged["page"].to_i <= 1
        merged.delete("sort") if merged["sort"] == "hot"

        query = merged.reject { |_, value| value.nil? || value.to_s.empty? }
                      .map { |key, value| "#{CGI.escape(key)}=#{CGI.escape(value.to_s)}" }
                      .join("&")
        base = @community && @community != "all" ? "/r/#{@community}" : "/"
        query.empty? ? base : "#{base}?#{query}"
      end

      def community_path(name) = name == "all" ? "/" : "/r/#{name}"

      def rewritten?(post) = post["title"] != post["original_title"]
    end

    before do
      @sort = params["sort"].to_s.empty? ? "hot" : params["sort"].to_s
      @query = params["q"]
      @page = [params["page"].to_i, 1].max
      @communities = repo.communities
      @stats = repo.stats
    end

    get "/" do
      render_listing(nil)
    end

    get "/r/:community" do
      render_listing(params["community"].to_s.downcase)
    end

    post "/posts/:id/vote" do
      result = repo.vote(params["id"], voter, params["value"])
      halt 404, "no such post" if result.nil?

      if request.env["HTTP_ACCEPT"].to_s.include?("application/json")
        content_type :json
        { score: result[:score], value: result[:value] }.to_json
      else
        redirect(back_path)
      end
    end

    get "/about" do
      @title = "About"
      erb :about
    end

    get "/feed.xml" do
      feed_for(nil)
    end

    get "/r/:community/feed.xml" do
      feed_for(params["community"].to_s.downcase)
    end

    get "/healthz" do
      content_type :json
      { status: "ok", posts: @stats[:posts], rewriter: Rehash.rewriter.name }.to_json
    end

    not_found do
      @title = "Not found"
      status 404
      erb :not_found
    end

    error do |e|
      Rehash.logger.error("#{e.class}: #{e.message}")
      @title = "Something broke"
      @error = e
      status 500
      erb :error
    end

    private

    def render_listing(community)
      @community = community
      @title = community ? "/r/#{community}" : "front page"
      @posts, @more = repo.posts(sort: @sort, community: community, query: @query, page: @page)
      @votes = repo.votes_by(request.cookies[VOTER_COOKIE], @posts.map { |p| p["id"] })
      erb :index
    end

    def feed_for(community)
      @community = community
      @posts, = repo.posts(sort: "new", community: community, per_page: 50)
      content_type "application/rss+xml"
      erb :feed, layout: false
    end

    def back_path
      referer = request.referer.to_s
      referer.start_with?(request.base_url) ? referer.sub(request.base_url, "") : "/"
    end
  end
end
