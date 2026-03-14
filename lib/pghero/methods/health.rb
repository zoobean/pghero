module PgHero
  module Methods
    module Health
      def health_score
        connection_state_totals = connection_states
        total_connections = connection_state_totals.values.sum
        idle_connections = connection_state_totals["idle in transaction"].to_i

        recent_query_stats =
          if query_stats_enabled?
            query_stats(historical: historical_query_stats_enabled?, start_at: 24.hours.ago)
          else
            []
          end

        slow_query_count = query_stats_enabled? ? slow_queries(query_stats: recent_query_stats).size : nil
        unused_index_count = unused_indexes(max_scans: 0).size
        table_hit_rate_value = table_hit_rate
        index_hit_rate_value = index_hit_rate
        autovacuum_issue_count = autovacuum_danger.size

        components = [
          health_component_for_slow_queries(slow_query_count),
          health_component_for_unused_indexes(unused_index_count),
          health_component_for_cache(table_hit_rate_value, index_hit_rate_value),
          health_component_for_autovacuum(autovacuum_issue_count),
          health_component_for_connections(total_connections, idle_connections)
        ]

        {
          score: components.sum { |component| component[:score] },
          components: components,
          metrics: {
            slow_queries: slow_query_count,
            unused_indexes: unused_index_count,
            table_hit_rate: table_hit_rate_value,
            index_hit_rate: index_hit_rate_value,
            autovacuum_issues: autovacuum_issue_count,
            total_connections: total_connections,
            idle_connections: idle_connections
          }
        }
      end

      private

      def build_health_component(key, title, score, value, details)
        {
          key: key,
          title: title,
          score: score,
          max_score: 20,
          value: value,
          details: details,
          status:
            if score >= 18
              "success"
            elsif score >= 10
              "warning"
            else
              "danger"
            end
        }
      end

      def health_component_for_slow_queries(slow_query_count)
        if slow_query_count.nil?
          build_health_component(:slow_queries, "Slow Queries", 10, "Unavailable", "Enable query stats to score slow queries.")
        else
          penalty = [slow_query_count * 2, 20].min
          build_health_component(
            :slow_queries,
            "Slow Queries",
            20 - penalty,
            slow_query_count,
            slow_query_count.zero? ? "No slow queries in the last 24 hours." : "#{slow_query_count} slow queries crossed the threshold in the last 24 hours."
          )
        end
      end

      def health_component_for_unused_indexes(unused_index_count)
        penalty = [unused_index_count, 20].min
        build_health_component(
          :unused_indexes,
          "Unused Indexes",
          20 - penalty,
          unused_index_count,
          unused_index_count.zero? ? "No unused indexes detected." : "#{unused_index_count} indexes have zero scans."
        )
      end

      def health_component_for_cache(table_hit_rate_value, index_hit_rate_value)
        rates = [table_hit_rate_value, index_hit_rate_value].compact

        if rates.empty?
          build_health_component(:cache_hit_rate, "Cache Hit Rate", 10, "Unavailable", "Cache hit rate data is not available.")
        else
          target_rate = cache_hit_rate_threshold / 100.0
          worst_rate = rates.min
          penalty = [((target_rate - worst_rate) * 400).round, 0].max
          penalty = [penalty, 20].min
          build_health_component(
            :cache_hit_rate,
            "Cache Hit Rate",
            20 - penalty,
            "#{(worst_rate * 100).round(1)}%",
            "Table #{(table_hit_rate_value.to_f * 100).round(1)}% / Index #{(index_hit_rate_value.to_f * 100).round(1)}%"
          )
        end
      end

      def health_component_for_autovacuum(autovacuum_issue_count)
        penalty = [autovacuum_issue_count * 5, 20].min
        build_health_component(
          :autovacuum,
          "Autovacuum",
          20 - penalty,
          autovacuum_issue_count,
          autovacuum_issue_count.zero? ? "Autovacuum looks healthy." : "#{autovacuum_issue_count} tables are nearing the freeze age limit."
        )
      end

      def health_component_for_connections(total_connections, idle_connections)
        saturation = total_connections_threshold > 0 ? total_connections.to_f / total_connections_threshold : 0

        penalty = 0
        penalty += if saturation >= 1
          12
        elsif saturation >= 0.85
          8
        elsif saturation >= 0.7
          4
        else
          0
        end

        penalty += if idle_connections >= 100
          8
        elsif idle_connections >= 20
          4
        elsif idle_connections >= 5
          2
        else
          0
        end

        build_health_component(
          :connections,
          "Connections",
          [20 - penalty, 0].max,
          total_connections,
          "#{idle_connections} idle in transaction. Threshold #{total_connections_threshold}."
        )
      end
    end
  end
end
