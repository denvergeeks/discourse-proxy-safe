# frozen_string_literal: true

require "rails_helper"

RSpec.describe "DiscourseProxySafe outbound Accept headers", type: :request do
  let(:json_url) { "https://remote.example.com/t/123.json" }
  let(:html_url) { "https://blog.example.com/" }
  let(:json_headers) { { "content-type" => "application/json; charset=utf-8" } }
  let(:html_headers) { { "content-type" => "text/html; charset=utf-8" } }

  before do
    SiteSetting.proxy_safe_enabled = true
    SiteSetting.proxy_safe_access_level = "public"
    SiteSetting.proxy_safe_rate_limit_per_minute = 0
    SiteSetting.proxy_safe_request_timeout_seconds = 5
    SiteSetting.proxy_safe_max_response_size_kb = 100
    SiteSetting.proxy_safe_cache_seconds = 0
    SiteSetting.proxy_safe_block_private_networks = false
    SiteSetting.proxy_safe_subdomain_policy = "always_include_subdomains"
    SiteSetting.proxy_safe_allowed_domains = "remote.example.com|blog.example.com"
  end

  def expect_upstream_accept_header(expected_url:, expected_accept:, response:)
    connection = instance_double(Faraday::Connection)

    allow(Faraday).to receive(:new).and_return(connection)

    allow(connection).to receive(:get).with(expected_url) do |&block|
      request = Struct.new(:headers).new({})
      block.call(request) if block

      expect(request.headers["Accept"]).to eq(expected_accept)
      expect(request.headers["User-Agent"]).to include("discourse-proxy-safe/")

      response
    end
  end

  it "uses a JSON-only Accept header for /fetch.json" do
    expect_upstream_accept_header(
      expected_url: json_url,
      expected_accept: "application/json, application/problem+json, */*",
      response: OpenStruct.new(status: 200, headers: json_headers, body: '{"ok":true}')
    )

    get "/discourse-proxy-safe/fetch.json", params: { url: json_url }

    expect(response.status).to eq(200)
  end

  it "uses a broader Accept header for /fetch_external.json" do
    expect_upstream_accept_header(
      expected_url: html_url,
      expected_accept: "application/json, application/problem+json, text/plain, text/html, */*",
      response: OpenStruct.new(status: 200, headers: html_headers, body: "<html></html>")
    )

    get "/discourse-proxy-safe/fetch_external.json", params: { url: html_url }

    expect(response.status).to eq(200)
  end
end
