# frozen_string_literal: true

require "rails_helper"

RSpec.describe "DiscourseProxySafe::ProxyController", type: :request do
  fab!(:current_user) { Fabricate(:user) }

  let(:json_url) { "https://remote.example.com/t/123.json" }
  let(:html_url) { "https://blog.example.com/" }
  let(:json_headers) { { "content-type" => "application/json; charset=utf-8" } }
  let(:html_headers) { { "content-type" => "text/html; charset=utf-8" } }
  let(:text_headers) { { "content-type" => "text/plain; charset=utf-8" } }
  let(:xml_headers) { { "content-type" => "application/xml; charset=utf-8" } }
  let(:json_body) { '{"id":123,"title":"Remote topic"}' }
  let(:html_body) do
    <<~HTML
      <!doctype html>
      <html>
        <head>
          <title>Example Blog</title>
          <meta property="og:title" content="Example Blog Title">
          <meta property="og:description" content="Example blog description">
        </head>
        <body>
          <h1>Example Blog Heading</h1>
        </body>
      </html>
    HTML
  end
  let(:text_body) { "Plain text preview body" }

  before do
    SiteSetting.proxy_safe_enabled = true
    SiteSetting.proxy_safe_access_level = "public"
    SiteSetting.proxy_safe_rate_limit_per_minute = 0
    SiteSetting.proxy_safe_request_timeout_seconds = 5
    SiteSetting.proxy_safe_max_response_size_kb = 100
    SiteSetting.proxy_safe_cache_seconds = 0
    SiteSetting.proxy_safe_block_private_networks = false
    SiteSetting.proxy_safe_subdomain_policy = "always_include_subdomains"
    SiteSetting.proxy_safe_allowed_domains = "remote.example.com|blog.example.com|example.com"
  end

  def build_faraday_connection_stub(expected_url:, response: nil, error: nil, &request_assertions)
    connection = instance_double(Faraday::Connection)

    allow(Faraday).to receive(:new).and_return(connection)

    allow(connection).to receive(:get).with(expected_url) do |&block|
      request = Struct.new(:headers).new({})
      block.call(request) if block
      request_assertions&.call(request)

      raise error if error

      response
    end
  end

  describe "GET /discourse-proxy-safe/fetch.json" do
    it "returns proxied JSON for an allowed remote topic URL" do
      build_faraday_connection_stub(
        expected_url: json_url,
        response: OpenStruct.new(status: 200, headers: json_headers, body: json_body)
      )

      get "/discourse-proxy-safe/fetch.json", params: { url: json_url }

      expect(response.status).to eq(200)
      expect(response.media_type).to eq("application/json")
      expect(response.body).to eq(json_body)
    end

    it "rejects upstream HTML on the JSON-only route" do
      build_faraday_connection_stub(
        expected_url: html_url,
        response: OpenStruct.new(status: 200, headers: html_headers, body: html_body)
      )

      get "/discourse-proxy-safe/fetch.json", params: { url: html_url }

      expect(response.status).to eq(502)
      expect(response.parsed_body["error"]).to eq("Remote returned an unsupported content type.")
    end

    it "passes through known upstream 404 JSON responses" do
      error =
        Faraday::ClientError.new(
          "upstream error",
          response: {
            status: 404,
            headers: json_headers,
            body: '{"error":"Not Found"}',
          }
        )

      build_faraday_connection_stub(expected_url: json_url, error: error)

      get "/discourse-proxy-safe/fetch.json", params: { url: json_url }

      expect(response.status).to eq(404)
      expect(response.media_type).to eq("application/json")
      expect(response.body).to eq('{"error":"Not Found"}')
    end

    it "returns 403 for a host not on the allowlist" do
      get "/discourse-proxy-safe/fetch.json", params: { url: "https://notallowed.example.net/t/1.json" }

      expect(response.status).to eq(403)
      expect(response.parsed_body["error"]).to include("not in the proxy allowlist")
    end

    it "returns 400 when the url parameter is missing" do
      get "/discourse-proxy-safe/fetch.json"

      expect(response.status).to eq(400)
      expect(response.parsed_body["error"]).to eq("Missing url parameter.")
    end

    it "returns 400 for a non-http URL" do
      get "/discourse-proxy-safe/fetch.json", params: { url: "javascript:alert(1)" }

      expect(response.status).to eq(400)
      expect(response.parsed_body["error"]).to eq("Only http and https URLs are permitted.")
    end

    it "returns 404 when the plugin is disabled" do
      SiteSetting.proxy_safe_enabled = false

      get "/discourse-proxy-safe/fetch.json", params: { url: json_url }

      expect(response.status).to eq(404)
      expect(response.parsed_body["error"]).to eq("Proxy is disabled.")
    end

    it "requires login when access level is logged_in" do
      SiteSetting.proxy_safe_access_level = "logged_in"

      get "/discourse-proxy-safe/fetch.json", params: { url: json_url }

      expect(response.status).to eq(403)
      expect(response.parsed_body["error"]).to eq("You must be logged in to use this proxy.")
    end

    it "allows a logged-in user when access level is logged_in" do
      SiteSetting.proxy_safe_access_level = "logged_in"
      sign_in(current_user)

      build_faraday_connection_stub(
        expected_url: json_url,
        response: OpenStruct.new(status: 200, headers: json_headers, body: json_body)
      )

      get "/discourse-proxy-safe/fetch.json", params: { url: json_url }

      expect(response.status).to eq(200)
      expect(response.media_type).to eq("application/json")
    end

    it "enforces rate limiting" do
      SiteSetting.proxy_safe_rate_limit_per_minute = 1

      build_faraday_connection_stub(
        expected_url: json_url,
        response: OpenStruct.new(status: 200, headers: json_headers, body: json_body)
      )

      get "/discourse-proxy-safe/fetch.json", params: { url: json_url }
      expect(response.status).to eq(200)

      get "/discourse-proxy-safe/fetch.json", params: { url: json_url }
      expect(response.status).to eq(429)
      expect(response.headers["Retry-After"]).to eq("60")
      expect(response.parsed_body["error"]).to eq("Rate limit exceeded. Please wait before retrying.")
    end

    it "rejects oversized responses" do
      SiteSetting.proxy_safe_max_response_size_kb = 1

      oversized_body = "x" * 2048

      build_faraday_connection_stub(
        expected_url: json_url,
        response: OpenStruct.new(status: 200, headers: json_headers, body: oversized_body)
      )

      get "/discourse-proxy-safe/fetch.json", params: { url: json_url }

      expect(response.status).to eq(502)
      expect(response.parsed_body["error"]).to eq("Remote response exceeded the maximum allowed size.")
    end

    it "sends a JSON-only Accept header upstream" do
      build_faraday_connection_stub(
        expected_url: json_url,
        response: OpenStruct.new(status: 200, headers: json_headers, body: json_body)
      ) do |request|
        expect(request.headers["Accept"]).to eq(
          "application/json, application/problem+json, */*"
        )
        expect(request.headers["User-Agent"]).to include("discourse-proxy-safe/")
      end

      get "/discourse-proxy-safe/fetch.json", params: { url: json_url }

      expect(response.status).to eq(200)
    end
  end

  describe "GET /discourse-proxy-safe/fetch_external.json" do
    it "returns proxied HTML for an allowed external URL" do
      build_faraday_connection_stub(
        expected_url: html_url,
        response: OpenStruct.new(status: 200, headers: html_headers, body: html_body)
      )

      get "/discourse-proxy-safe/fetch_external.json", params: { url: html_url }

      expect(response.status).to eq(200)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include("Example Blog")
    end

    it "returns proxied plain text for an allowed external URL" do
      build_faraday_connection_stub(
        expected_url: html_url,
        response: OpenStruct.new(status: 200, headers: text_headers, body: text_body)
      )

      get "/discourse-proxy-safe/fetch_external.json", params: { url: html_url }

      expect(response.status).to eq(200)
      expect(response.media_type).to eq("text/plain")
      expect(response.body).to eq(text_body)
    end

    it "also accepts JSON on the external route" do
      build_faraday_connection_stub(
        expected_url: json_url,
        response: OpenStruct.new(status: 200, headers: json_headers, body: json_body)
      )

      get "/discourse-proxy-safe/fetch_external.json", params: { url: json_url }

      expect(response.status).to eq(200)
      expect(response.media_type).to eq("application/json")
      expect(response.body).to eq(json_body)
    end

    it "passes through known upstream 404 HTML responses" do
      error =
        Faraday::ClientError.new(
          "upstream error",
          response: {
            status: 404,
            headers: html_headers,
            body: "<html><body>Not found</body></html>",
          }
        )

      build_faraday_connection_stub(expected_url: html_url, error: error)

      get "/discourse-proxy-safe/fetch_external.json", params: { url: html_url }

      expect(response.status).to eq(404)
      expect(response.media_type).to eq("text/html")
      expect(response.body).to include("Not found")
    end

    it "rejects a host not on the allowlist" do
      get "/discourse-proxy-safe/fetch_external.json", params: { url: "https://notallowed.example.net/" }

      expect(response.status).to eq(403)
      expect(response.parsed_body["error"]).to include("not in the proxy allowlist")
    end

    it "returns 502 for unsupported upstream content types" do
      build_faraday_connection_stub(
        expected_url: html_url,
        response: OpenStruct.new(status: 200, headers: xml_headers, body: "<feed />")
      )

      get "/discourse-proxy-safe/fetch_external.json", params: { url: html_url }

      expect(response.status).to eq(502)
      expect(response.parsed_body["error"]).to eq("Remote returned an unsupported content type.")
    end

    it "sends the broader external Accept header upstream" do
      build_faraday_connection_stub(
        expected_url: html_url,
        response: OpenStruct.new(status: 200, headers: html_headers, body: html_body)
      ) do |request|
        expect(request.headers["Accept"]).to eq(
          "application/json, application/problem+json, text/plain, text/html, */*"
        )
        expect(request.headers["User-Agent"]).to include("discourse-proxy-safe/")
      end

      get "/discourse-proxy-safe/fetch_external.json", params: { url: html_url }

      expect(response.status).to eq(200)
    end
  end

  describe "caching" do
    before do
      SiteSetting.proxy_safe_cache_seconds = 60
    end

    it "caches JSON-route responses separately from external-route responses for the same URL" do
      shared_url = "https://example.com/resource"

      first_connection = instance_double(Faraday::Connection)
      second_connection = instance_double(Faraday::Connection)

      allow(Faraday).to receive(:new).and_return(first_connection, second_connection)

      allow(first_connection).to receive(:get).with(shared_url) do |&block|
        request = Struct.new(:headers).new({})
        block.call(request) if block
        OpenStruct.new(status: 200, headers: json_headers, body: '{"route":"json"}')
      end

      allow(second_connection).to receive(:get).with(shared_url) do |&block|
        request = Struct.new(:headers).new({})
        block.call(request) if block
        OpenStruct.new(status: 200, headers: html_headers, body: "<html><body>external route</body></html>")
      end

      get "/discourse-proxy-safe/fetch.json", params: { url: shared_url }
      expect(response.status).to eq(200)
      expect(response.body).to eq('{"route":"json"}')

      get "/discourse-proxy-safe/fetch_external.json", params: { url: shared_url }
      expect(response.status).to eq(200)
      expect(response.body).to include("external route")

      get "/discourse-proxy-safe/fetch.json", params: { url: shared_url }
      expect(response.status).to eq(200)
      expect(response.body).to eq('{"route":"json"}')

      get "/discourse-proxy-safe/fetch_external.json", params: { url: shared_url }
      expect(response.status).to eq(200)
      expect(response.body).to include("external route")
    end
  end
end
