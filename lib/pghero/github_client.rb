require "base64"
require "openssl"
require "cgi"
require "json"
require "net/http"
require "time"

module PgHero
  class GitHubClient
    def initialize(token: nil, app_id: nil, installation_id: nil, private_key: nil, private_key_path: nil, api_url: "https://api.github.com")
      @token = token
      @app_id = app_id
      @installation_id = installation_id
      @private_key = private_key
      @private_key_path = private_key_path
      @api_url = api_url.sub(%r{/+\z}, "")
    end

    def releases(repo, per_page: 20)
      path = "/repos/#{repo}/releases?per_page=#{per_page.to_i}"
      get_json(path, repo: repo).filter_map do |release|
        next if release["draft"]
        {
          id: release["id"],
          name: release["name"],
          tag_name: release["tag_name"],
          sha: release["target_commitish"],
          body: release["body"],
          url: release["html_url"],
          published_at: parse_time(release["published_at"])
        }
      end
    end

    private

    def get_json(path_or_url, repo: nil, jwt: false)
      uri = path_or_url.start_with?("http") ? URI(path_or_url) : URI("#{@api_url}#{path_or_url}")
      request = Net::HTTP::Get.new(uri)
      add_default_headers(request, repo: repo, jwt: jwt)

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: 5, open_timeout: 5) do |http|
        http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        raise PgHero::Error, "GitHub API request failed with #{response.code}"
      end

      JSON.parse(response.body)
    end

    def post_json(path, body = nil, repo: nil, jwt: false)
      uri = URI("#{@api_url}#{path}")
      request = Net::HTTP::Post.new(uri)
      add_default_headers(request, repo: repo, jwt: jwt)
      request.body = JSON.generate(body) if body

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: 5, open_timeout: 5) do |http|
        http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        raise PgHero::Error, "GitHub API request failed with #{response.code}"
      end

      JSON.parse(response.body)
    end

    def add_default_headers(request, repo:, jwt:)
      request["Accept"] = "application/vnd.github+json"
      request["Authorization"] = "Bearer #{jwt ? app_jwt : access_token(repo)}"
      request["User-Agent"] = "pghero"
      request["X-GitHub-Api-Version"] = "2022-11-28"
      request["Content-Type"] = "application/json"
    end

    def access_token(repo)
      return @token if @token.to_s.size > 0

      if @installation_access_token.nil? || @installation_access_token_expires_at.nil? || Time.now >= (@installation_access_token_expires_at - 60)
        refresh_installation_access_token(repo)
      end

      @installation_access_token
    end

    def refresh_installation_access_token(repo)
      installation_id = @installation_id || fetch_installation_id(repo)
      response = post_json("/app/installations/#{installation_id}/access_tokens", nil, repo: repo, jwt: true)
      @installation_access_token = response["token"]
      @installation_access_token_expires_at = parse_time(response["expires_at"])
    end

    def fetch_installation_id(repo)
      response = get_json("/repos/#{repo}/installation", repo: repo, jwt: true)
      response.fetch("id")
    end

    def app_jwt
      return @app_jwt if @app_jwt_expires_at && Time.now < (@app_jwt_expires_at - 30)

      now = Time.now.to_i
      header = base64url_encode(JSON.generate({alg: "RS256", typ: "JWT"}))
      payload = base64url_encode(JSON.generate({iat: now - 60, exp: now + 540, iss: @app_id}))
      signature = private_key_object.sign(OpenSSL::Digest::SHA256.new, "#{header}.#{payload}")
      @app_jwt = "#{header}.#{payload}.#{base64url_encode(signature)}"
      @app_jwt_expires_at = Time.at(now + 540)
      @app_jwt
    end

    def private_key_object
      @private_key_object ||= OpenSSL::PKey::RSA.new(load_private_key)
    end

    def load_private_key
      return @private_key if @private_key.to_s.size > 0
      return File.read(@private_key_path) if @private_key_path.to_s.size > 0

      raise PgHero::Error, "GitHub private key not configured"
    end

    def base64url_encode(value)
      Base64.urlsafe_encode64(value).delete("=")
    end

    def parse_time(value)
      value ? Time.parse(value) : nil
    end
  end
end
