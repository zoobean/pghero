module PgHero
  module Methods
    module Releases
      def github_token
        config["github_token"] || PgHero.config["github_token"] || ENV["PGHERO_GITHUB_TOKEN"]
      end

      def github_repo
        config["github_repo"] || PgHero.config["github_repo"] || ENV["PGHERO_GITHUB_REPO"]
      end

      def github_app_id
        config["github_app_id"] || PgHero.config["github_app_id"] || ENV["PGHERO_GITHUB_APP_ID"]
      end

      def github_installation_id
        config["github_installation_id"] || PgHero.config["github_installation_id"] || ENV["PGHERO_GITHUB_INSTALLATION_ID"]
      end

      def github_private_key
        config["github_private_key"] || PgHero.config["github_private_key"] || ENV["PGHERO_GITHUB_PRIVATE_KEY"]
      end

      def github_private_key_path
        config["github_private_key_path"] || PgHero.config["github_private_key_path"] || ENV["PGHERO_GITHUB_PRIVATE_KEY_PATH"]
      end

      def github_api_url
        config["github_api_url"] || PgHero.config["github_api_url"] || ENV["PGHERO_GITHUB_API_URL"] || "https://api.github.com"
      end

      def release_correlation_enabled?
        github_repo.to_s.size > 0 && (github_token.to_s.size > 0 || github_app_credentials?)
      end

      def github_app_credentials?
        github_app_id.to_s.size > 0 && (github_private_key.to_s.size > 0 || github_private_key_path.to_s.size > 0)
      end

      def releases(days: 14, limit: 20)
        return [] unless release_correlation_enabled?

        start_at = days.to_i.days.ago
        github_client
          .releases(github_repo, per_page: limit)
          .select { |release| release[:published_at] && release[:published_at] >= start_at }
          .sort_by { |release| release[:published_at] }
      rescue StandardError
        []
      end

      def correlate_query_release(query_hash, user: nil, days: 14, stats: nil)
        stats ||= query_hash_daily_stats(query_hash, user: user, current: true, start_at: days.to_i.days.ago)
        trend = query_hash_trend(query_hash, user: user, days: days, stats: stats)
        recent_releases = releases(days: days)

        regression_started_at = trend[:regression_started_at]
        correlated_release =
          if regression_started_at
            recent_releases.select { |release| release[:published_at] <= regression_started_at }.max_by { |release| release[:published_at] }
          end

        {
          enabled: release_correlation_enabled?,
          releases: recent_releases,
          trend: trend,
          correlated_release: correlated_release
        }
      end

      private

      def github_client
        @github_client ||= PgHero::GitHubClient.new(
          token: github_token,
          app_id: github_app_id,
          installation_id: github_installation_id,
          private_key: github_private_key,
          private_key_path: github_private_key_path,
          api_url: github_api_url
        )
      end
    end
  end
end
