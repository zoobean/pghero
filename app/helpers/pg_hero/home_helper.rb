module PgHero
  module HomeHelper
    def pghero_pretty_ident(table, schema: nil)
      ident = table
      if schema && schema != "public"
        ident = "#{schema}.#{table}"
      end
      if /\A[a-z0-9_]+\z/.match?(ident)
        ident
      else
        @database.quote_ident(ident)
      end
    end

    def pghero_js_value(value)
      json_escape(value.to_json(root: false)).html_safe
    end

    def pghero_remove_index(query)
      if query[:columns]
        columns = query[:columns].map(&:to_sym)
        columns = columns.first if columns.size == 1
      end
      ret = String.new("remove_index #{query[:table].to_sym.inspect}")
      ret << ", name: #{(query[:name] || query[:index]).to_s.inspect}"
      ret << ", column: #{columns.inspect}" if columns
      ret
    end

    def pghero_formatted_vacuum_times(time)
      content_tag(:span, title: pghero_formatted_date_time(time)) do
        "#{time_ago_in_words(time, include_seconds: true).sub(/(over|about|almost) /, "").sub("less than", "<")} ago"
      end
    end

    def pghero_formatted_date_time(time)
      l time.in_time_zone(@time_zone), format: :long
    end

    def pghero_health_score_class(score)
      if score >= 85
        "success"
      elsif score >= 60
        "warning"
      else
        "danger"
      end
    end

    def pghero_query_trend_label(trend)
      return "Not enough data" unless trend && trend[:change_pct]

      change = number_with_precision(trend[:change_pct].abs, precision: 0)

      case trend[:direction]
      when :regressing
        "+#{change}% slower"
      when :improving
        "-#{change}% faster"
      else
        "#{change}% stable"
      end
    end

    def pghero_query_trend_class(trend)
      return "trend-muted" unless trend

      case trend[:direction]
      when :regressing
        "trend-regressing"
      when :improving
        "trend-improving"
      else
        "trend-stable"
      end
    end

    def pghero_github_commit_url(repo, sha)
      return unless repo.present? && sha.present?

      "https://github.com/#{repo}/commit/#{sha}"
    end
  end
end
