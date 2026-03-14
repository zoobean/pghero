require_relative "test_helper"

class HealthTest < Minitest::Test
  FakeDatabase = Class.new do
    include PgHero::Methods::Health

    def query_stats_enabled?
      true
    end

    def historical_query_stats_enabled?
      true
    end

    def query_stats(**)
      [{average_time: 120, calls: 150}]
    end

    def slow_queries(query_stats:)
      query_stats
    end

    def unused_indexes(max_scans:)
      [{index: "users_old_idx"}, {index: "users_stale_idx"}]
    end

    def table_hit_rate
      0.97
    end

    def index_hit_rate
      0.995
    end

    def autovacuum_danger
      [{table: "users"}]
    end

    def connection_states
      {"active" => 430, "idle in transaction" => 25}
    end

    def total_connections_threshold
      500
    end

    def cache_hit_rate_threshold
      99
    end
  end

  def test_health_score
    health = FakeDatabase.new.health_score

    assert_equal 71, health[:score]
    assert_equal 5, health[:components].size
    assert_equal "Slow Queries", health[:components].first[:title]
    assert_equal "Connections", health[:components].last[:title]
  end
end
