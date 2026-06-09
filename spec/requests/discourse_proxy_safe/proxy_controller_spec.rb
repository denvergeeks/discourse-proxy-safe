# frozen_string_literal: true

require "rails_helper"

RSpec.describe DiscourseProxySafe::ProxyController, type: :request do
  before do
    SiteSetting.proxy_safe_enabled = true
    SiteSetting.proxy_safe_access_level = "public"
    SiteSetting.proxy_safe_allowed_domains = "meta.discourse.org"
    SiteSetting.proxy_safe_subdomain_policy = "always_include_subdomains"
    SiteSetting.proxy_safe_block_private_networks = true
    SiteSetting.proxy_safe_rate_limit_per_minute = 20
    SiteSetting.proxy_safe_cache_seconds = 0
    SiteSetting.proxy_safe_max_response_size_kb = 256
    SiteSetting.proxy_safe_request_timeout_seconds = 8
    SiteSetting.proxy_safe_only_json = true
  end

  describe "GET /discourse-proxy-safe/fetch.json" do
    it "returns 400 when the url param is missing" do
      get "/discourse-proxy-safe/fetch.json"

      expect(response.status).to eq(400)
      expect(response.parsed_body["error"]).to eq("Missing url parameter.")
    end

    it "returns 400 for an invalid url" do
      get "/discourse-proxy-safe/fetch.json", params: { url: "not-a-url" }

      expect(response.status).to eq(400)
      expect(response.parsed_body["error"]).to eq("Invalid URL.")
    end

    it "returns 400 for a non-http url" do
      get "/discourse-proxy-safe/fetch.json",
          params: { url: "ftp://meta.discourse.org/file.json" }

      expect(response.status).to eq(400)
      expect(response.parsed_body["error"]).to eq("Only http and https URLs are permitted.")
    end

    it "returns 403 for a host outside the allowlist" do
      get "/discourse-proxy-safe/fetch.json",
          params: { url: "https://example.org/t/topic/123.json" }

      expect(response.status).to eq(403)
      expect(response.parsed_body["error"]).to include("not in the proxy allowlist")
    end

    it "blocks localhost targets" do
      get "/discourse-proxy-safe/fetch.json",
          params: { url: "http://localhost:3000/test.json" }

      expect(response.status).to eq(403)
      expect(response.parsed_body["error"]).to eq("Localhost targets are not permitted.")
    end

    it "blocks loopback ip targets when private-network blocking is enabled" do
      get "/discourse-proxy-safe/fetch.json",
          params: { url: "http://127.0.0.1/test.json" }

      expect(response.status).to eq(403)
      expect(response.parsed_body["error"]).to eq("Private-network targets are not permitted.")
    end

    it "rejects subdomains when subdomain policy is exact_only" do
      SiteSetting.proxy_safe_subdomain_policy = "exact_only"

      get "/discourse-proxy-safe/fetch.json",
          params: { url: "https://sub.meta.discourse.org/t/topic/123.json" }

      expect(response.status).to eq(403)
      expect(response.parsed_body["error"]).to include("not in the proxy allowlist")
    end

    it "allows subdomains when subdomain policy is always_include_subdomains" do
      SiteSetting.proxy_safe_subdomain_policy = "always_include_subdomains"

      allow(Resolv).to receive(:getaddresses)
        .with("sub.meta.discourse.org")
        .and_return(["184.105.99.43"])

      allow_any_instance_of(DiscourseProxySafe::ProxyController)
        .to receive(:fetch_remote)
        .and_return(
          OpenStruct.new(
            status: 200,
            headers: { "content-type" => "application/json" },
            body: '{"ok":true}'
          )
        )

      get "/discourse-proxy-safe/fetch.json",
          params: { url: "https://sub.meta.discourse.org/t/topic/123.json" }

      expect(response.status).to eq(200)
      expect(response.body).to eq('{"ok":true}')
    end

    it "requires login when access level is logged_in" do
      SiteSetting.proxy_safe_access_level = "logged_in"

      get "/discourse-proxy-safe/fetch.json",
          params: { url: "https://meta.discourse.org/t/topic/123.json" }

      expect(response.status).to eq(403)
      expect(response.parsed_body["error"]).to eq("You must be logged in to use this proxy.")
    end

    it "returns 429 when the rate limit is exceeded" do
      SiteSetting.proxy_safe_rate_limit_per_minute = 1

      allow(Resolv).to receive(:getaddresses)
        .with("meta.discourse.org")
        .and_return(["184.105.99.43"])

      allow_any_instance_of(DiscourseProxySafe::ProxyController)
        .to receive(:fetch_remote)
        .and_return(
          OpenStruct.new(
            status: 200,
            headers: { "content-type" => "application/json" },
            body: '{"ok":true}'
          )
        )

      get "/discourse-proxy-safe/fetch.json",
          params: { url: "https://meta.discourse.org/t/topic/123.json" }
      expect(response.status).to eq(200)

      get "/discourse-proxy-safe/fetch.json",
          params: { url: "https://meta.discourse.org/t/topic/123.json" }

      expect(response.status).to eq(429)
      expect(response.headers["Retry-After"]).to eq("60")
    end

    it "rejects non-json content when json-only mode is enabled" do
      allow(Resolv).to receive(:getaddresses)
        .with("meta.discourse.org")
        .and_return(["184.105.99.43"])

      allow_any_instance_of(DiscourseProxySafe::ProxyController)
        .to receive(:fetch_remote)
        .and_return(
          OpenStruct.new(
            status: 200,
            headers: { "content-type" => "text/html; charset=utf-8" },
            body: "<html></html>"
          )
        )

      get "/discourse-proxy-safe/fetch.json",
          params: { url: "https://meta.discourse.org/t/topic/123" }

      expect(response.status).to eq(502)
      expect(response.parsed_body["error"]).to eq("Remote returned an unsupported content type.")
    end

    it "allows broader content types when json-only mode is disabled" do
      SiteSetting.proxy_safe_only_json = false

      allow(Resolv).to receive(:getaddresses)
        .with("meta.discourse.org")
        .and_return(["184.105.99.43"])

      allow_any_instance_of(DiscourseProxySafe::ProxyController)
        .to receive(:fetch_remote)
        .and_return(
          OpenStruct.new(
            status: 200,
            headers: { "content-type" => "text/html; charset=utf-8" },
            body: "<html></html>"
          )
        )

      get "/discourse-proxy-safe/fetch.json",
          params: { url: "https://meta.discourse.org/t/topic/123" }

      expect(response.status).to eq(200)
      expect(response.body).to eq("<html></html>")
    end
  end
end