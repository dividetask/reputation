# frozen_string_literal: true

require "sqlite3"
require "fileutils"
require "monitor"

module Rehash
  # Thin SQLite wrapper: owns the connection, the schema and a mutex so the
  # multi-threaded web server and the crawler can share one handle.
  class Database
    include MonitorMixin

    SCHEMA = <<~SQL
      CREATE TABLE IF NOT EXISTS posts (
        id             INTEGER PRIMARY KEY,
        url            TEXT    NOT NULL UNIQUE,
        domain         TEXT    NOT NULL,
        original_title TEXT    NOT NULL,
        title          TEXT    NOT NULL,
        rewriter       TEXT,
        summary        TEXT,
        author         TEXT,
        source_key     TEXT    NOT NULL,
        source_name    TEXT    NOT NULL,
        community      TEXT    NOT NULL,
        published_at   INTEGER,
        crawled_at     INTEGER NOT NULL,
        ups            INTEGER NOT NULL DEFAULT 1,
        downs          INTEGER NOT NULL DEFAULT 0,
        hot            REAL    NOT NULL DEFAULT 0
      );

      CREATE INDEX IF NOT EXISTS idx_posts_hot        ON posts (hot DESC);
      CREATE INDEX IF NOT EXISTS idx_posts_community  ON posts (community, hot DESC);
      CREATE INDEX IF NOT EXISTS idx_posts_published  ON posts (published_at DESC);

      CREATE TABLE IF NOT EXISTS votes (
        post_id    INTEGER NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
        voter      TEXT    NOT NULL,
        value      INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        PRIMARY KEY (post_id, voter)
      );

      CREATE INDEX IF NOT EXISTS idx_votes_voter ON votes (voter);
    SQL

    attr_reader :path

    def initialize(path)
      super()
      @path = path.to_s
      FileUtils.mkdir_p(File.dirname(@path)) unless @path == ":memory:"
      @conn = SQLite3::Database.new(@path)
      @conn.results_as_hash = true
      @conn.busy_timeout = 5_000
      @conn.execute("PRAGMA journal_mode = WAL") unless @path == ":memory:"
      @conn.execute("PRAGMA foreign_keys = ON")
      migrate!
    end

    def migrate!
      synchronize { @conn.execute_batch(SCHEMA) }
      self
    end

    def query(sql, params = [])
      synchronize { @conn.execute(sql, params) }
    end

    def first(sql, params = [])
      query(sql, params).first
    end

    def value(sql, params = [])
      row = first(sql, params)
      row&.values&.first
    end

    def execute(sql, params = [])
      synchronize do
        @conn.execute(sql, params)
        @conn.changes
      end
    end

    def transaction(&block)
      synchronize { @conn.transaction(&block) }
    end

    def last_insert_row_id
      synchronize { @conn.last_insert_row_id }
    end

    def close
      synchronize { @conn.close unless @conn.closed? }
    end
  end
end
