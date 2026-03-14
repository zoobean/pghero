require_relative "test_helper"

class GitHubClientTest < Minitest::Test
  def test_releases
    client = PgHero::GitHubClient.new(token: "test-token", api_url: "https://api.github.com")

    with_stubbed_methods(client, get_json: ->(*, **) { [{"id" => 1, "name" => "v1.2.3", "tag_name" => "v1.2.3", "target_commitish" => "abcdef1", "html_url" => "https://github.com/acme/widgets/releases/tag/v1.2.3", "published_at" => "2026-03-01T12:00:00Z"}] }) do
      releases = client.releases("acme/widgets")

      assert_equal 1, releases.size
      assert_equal "v1.2.3", releases.first[:name]
      assert_equal "abcdef1", releases.first[:sha]
    end
  end

  def test_generates_app_jwt
    rsa_key = OpenSSL::PKey::RSA.generate(2048)
    client = PgHero::GitHubClient.new(app_id: "123", private_key: rsa_key.to_pem)

    jwt = client.send(:app_jwt)

    assert_equal 3, jwt.split(".").size
  end
end
