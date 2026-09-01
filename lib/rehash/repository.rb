# frozen_string_literal: true

require "uri"

module Rehash
  # All the SQL the app needs: storing crawled links, listing them in
  # reddit-ish orders, and recording votes.
  class Repository
    PER_PAGE = 25
    SORTS = %w[hot new top].freeze

    def initialize(db)
      @db = db
    end

    # Insert a crawled item. Returns :created, :updated or :skipped.
    # A link is identified by its URL, so re-crawling never duplicates it —
    # but a changed rewrite (e.g. after switching rewriters) is picked up.
    def upsert_post(item)
      url = item.fetch(:url)
      existing = @db.first("SELECT id, title, rewriter FROM posts WHERE url = ?", [url])
      now = Time.now.to_i
      created_at = item[:published_at]&.to_i || now

      if existing
        return :skipped if existing["title"] == item[:title] && existing["rewriter"] == item[:rewriter].to_s

        @db.execute(
          "UPDATE posts SET title = ?, rewriter = ?, summary = COALESCE(?, summary) WHERE id = ?",
          [item[:title], item[:rewriter].to_s, item[:summary], existing["id"]]
        )
        return :updated
      end

      @db.execute(<<~SQL, [
        INSERT INTO posts
          (url, domain, original_title, title, rewriter, summary, author,
           source_key, source_name, community, published_at, crawled_at, ups, downs, hot)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 0, ?)
      SQL
        url,
        domain_for(url),
        item.fetch(:original_title),
        item.fetch(:title),
        item[:rewriter].to_s,
        item[:summary],
        item[:author],
        item.fetch(:source_key),
        item.fetch(:source_name),
        item.fetch(:community),
        item[:published_at]&.to_i,
        now,
        Ranking.hot(1, 0, created_at)
      ])
      :created
    end

    def posts(sort: "hot", community: nil, query: nil, page: 1, per_page: PER_PAGE)
      sort = SORTS.include?(sort.to_s) ? sort.to_s : "hot"
      page = [page.to_i, 1].max
      where = []
      params = []

      if community && community != "all"
        where << "community = ?"
        params << community.to_s.downcase
      end

      if query && !query.strip.empty?
        where << "(title LIKE ? OR original_title LIKE ? OR domain LIKE ?)"
        like = "%#{query.strip}%"
        3.times { params << like }
      end

      clause = where.empty? ? "" : "WHERE #{where.join(' AND ')}"
      order = case sort
              when "new" then "COALESCE(published_at, crawled_at) DESC"
              when "top" then "(ups - downs) DESC, hot DESC"
              else "hot DESC"
              end

      rows = @db.query(
        "SELECT * FROM posts #{clause} ORDER BY #{order} LIMIT ? OFFSET ?",
        params + [per_page + 1, (page - 1) * per_page]
      )
      more = rows.size > per_page
      [rows.first(per_page), more]
    end

    def post(id)
      @db.first("SELECT * FROM posts WHERE id = ?", [id.to_i])
    end

    def communities
      @db.query("SELECT community, COUNT(*) AS n FROM posts GROUP BY community ORDER BY n DESC")
    end

    def stats
      {
        posts: @db.value("SELECT COUNT(*) FROM posts").to_i,
        sources: @db.value("SELECT COUNT(DISTINCT source_key) FROM posts").to_i,
        votes: @db.value("SELECT COUNT(*) FROM votes").to_i,
        newest: @db.value("SELECT MAX(crawled_at) FROM posts")
      }
    end

    # Votes cast by one (cookie-identified) voter, as {post_id => -1|1}.
    def votes_by(voter, post_ids)
      return {} if voter.nil? || post_ids.empty?

      placeholders = (["?"] * post_ids.size).join(",")
      rows = @db.query(
        "SELECT post_id, value FROM votes WHERE voter = ? AND post_id IN (#{placeholders})",
        [voter, *post_ids]
      )
      rows.to_h { |r| [r["post_id"], r["value"]] }
    end

    # Casting the same vote twice removes it, exactly like reddit's arrows.
    # Returns the post's new score, or nil when the post is gone.
    def vote(post_id, voter, value)
      value = value.to_i.clamp(-1, 1)
      post_id = post_id.to_i

      @db.transaction do
        post = @db.first("SELECT id, ups, downs, published_at, crawled_at FROM posts WHERE id = ?", [post_id])
        next nil if post.nil?

        current = @db.value("SELECT value FROM votes WHERE post_id = ? AND voter = ?", [post_id, voter]).to_i
        value = 0 if value == current # toggle off

        @db.execute("DELETE FROM votes WHERE post_id = ? AND voter = ?", [post_id, voter])
        if value != 0
          @db.execute(
            "INSERT INTO votes (post_id, voter, value, created_at) VALUES (?, ?, ?, ?)",
            [post_id, voter, value, Time.now.to_i]
          )
        end

        ups = post["ups"] + (value == 1 ? 1 : 0) - (current == 1 ? 1 : 0)
        downs = post["downs"] + (value == -1 ? 1 : 0) - (current == -1 ? 1 : 0)
        created_at = post["published_at"] || post["crawled_at"]

        @db.execute(
          "UPDATE posts SET ups = ?, downs = ?, hot = ? WHERE id = ?",
          [ups, downs, Ranking.hot(ups, downs, created_at), post_id]
        )
        { score: ups - downs, value: value }
      end
    end

    # Re-derives `hot` for every post; run after changing the ranking constants.
    def rescore!
      @db.query("SELECT id, ups, downs, published_at, crawled_at FROM posts").each do |row|
        created_at = row["published_at"] || row["crawled_at"]
        @db.execute("UPDATE posts SET hot = ? WHERE id = ?",
                    [Ranking.hot(row["ups"], row["downs"], created_at), row["id"]])
      end
    end

    def prune!(older_than_days)
      cutoff = Time.now.to_i - (older_than_days * 86_400)
      @db.execute("DELETE FROM posts WHERE COALESCE(published_at, crawled_at) < ?", [cutoff])
    end

    def domain_for(url)
      host = URI.parse(url).host.to_s
      host.sub(/\Awww\./, "")
    rescue URI::InvalidURIError
      "unknown"
    end
  end
end
