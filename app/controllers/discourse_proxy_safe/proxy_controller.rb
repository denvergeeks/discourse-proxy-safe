# frozen_string_literal: true

require "digest"
require "json"
require "uri"

class DiscourseProxySafe::ProxyController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :check_plugin_enabled
  before_action :check_access_level
  before_action :check_rate_limit
  before_action :validate_url

  CACHE_KEY_PREFIX = "discourse_proxy_safe"

  ALLOWED_CONTENT_TYPES = %w[
    application/json
    text/plain
    text/html
  ].freeze

  def fetch
    cached = read_cache
    if cached
      render plain: cached[:body], content_type: cached[:content_type], status: 200
      return
    end

    response = fetch_remote

    unless response
      render json: { error: "Remote fetch failed or timed out." }, status: 502
      return
    end

    unless acceptable_content_type?(response)
      render json: { error: "Remote returned an unsupported content type." }, status: 502
      return
    end

    unless acceptable_size?(response)
      render json: { error: "Remote response exceeded the maximum allowed size." }, status: 502
      return
    end

    body = response.body.to_s
    status = normalize_status(response.status)
    content_type = normalized_response_content_type(response)

    write_cache(body, content_type) if status == 200

    render plain: body, content_type: content_type, status: status
  rescue => e
    Rails.logger.error(
      "[discourse-proxy-safe] Unhandled error in fetch: #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
    )
    render json: { error: "An unexpected error occurred." }, status: 500
  end

  private

  def check_plugin_enabled
    return if SiteSetting.proxy_safe_enabled

    render json: { error: "Proxy is disabled." }, status: 404
  end

  def check_access_level
    case SiteSetting.proxy_safe_access_level
    when "public"
      nil
    when "logged_in"
      return if current_user

      render json: { error: "You must be logged in to use this proxy." }, status: 403
    when "session"
      return if current_user && request.session[:current_user_id].present?

      render json: { error: "A valid session is required." }, status: 403
    else
      render json: { error: "Invalid access level configured." }, status: 500
    end
  end

  def check_rate_limit
    limit = SiteSetting.proxy_safe_rate_limit_per_minute.to_i
    return if limit <= 0

    count = Discourse.redis.incr(rate_limit_key)
    Discourse.redis.expire(rate_limit_key, 60) if count == 1

    return if count <= limit

    render json: { error: "Rate limit exceeded. Please wait before retrying." }, status: 429
  end

  def rate_limit_key
    identifier = current_user ? "user:#{current_user.id}" : "ip:#{request.remote_ip}"
    "#{CACHE_KEY_PREFIX}:rate:#{identifier}"
  end

  def validate_url
    raw = params[:url].to_s.strip

    if raw.blank?
      render json: { error: "Missing url parameter." }, status: 400
      return
    end

    begin
      uri = URI.parse(raw)
    rescue URI::InvalidURIError
      render json: { error: "Invalid URL." }, status: 400
      return
    end

    unless %w[http https].include?(uri.scheme.to_s)
      render json: { error: "Only http and https URLs are permitted." }, status: 400
      return
    end

    if uri.host.blank?
      render json: { error: "URL has no host." }, status: 400
      return
    end

    allowed_domains =
      SiteSetting.proxy_safe_allowed_domains
        .to_s
        .split("|")
        .map(&:strip)
        .reject(&:blank?)
        .map(&:downcase)

    unless allowed_domain?(uri.host, allowed_domains)
      render json: {
        error: "Domain '#{uri.host}' is not in the proxy allowlist.",
      }, status: 403
      return
    end

    @proxy_uri = uri
  end

  def allowed_domain?(host, allowed_domains)
    host = host.to_s.downcase
    allowed_domains.any? do |allowed|
      host == allowed || host.end_with?(".#{allowed}")
    end
  end

  def fetch_remote
    timeout = SiteSetting.proxy_safe_request_timeout_seconds.to_i

    connection =
      Faraday.new do |f|
        f.options.timeout = timeout
        f.options.open_timeout = [timeout, 5].min
        f.adapter Faraday.default_adapter
      end

    connection.get(@proxy_uri.to_s) do |req|
      req.headers["Accept"] = "text/html, application/json, text/plain, */*"
      req.headers["User-Agent"] = "discourse-proxy-safe/0.1 (+#{Discourse.base_url})"
    end
  rescue Faraday::TimeoutError, Faraday::ConnectionFailed, Faraday::SSLError, Faraday::Error => e
    Rails.logger.warn(
      "[discourse-proxy-safe] Fetch failed for #{@proxy_uri}: #{e.class}: #{e.message}"
    )
    nil
  rescue => e
    Rails.logger.error(
      "[discourse-proxy-safe] Unexpected fetch error for #{@proxy_uri}: #{e.class}: #{e.message}"
    )
    nil
  end

  def acceptable_content_type?(response)
    content_type = response.headers["content-type"].to_s.downcase
    ALLOWED_CONTENT_TYPES.any? { |allowed| content_type.include?(allowed) }
  end

  def acceptable_size?(response)
    max_bytes = SiteSetting.proxy_safe_max_response_size_kb.to_i * 1024
    response.body.to_s.bytesize <= max_bytes
  end

  def cache_key
    digest = Digest::SHA256.hexdigest(@proxy_uri.to_s)
    "#{CACHE_KEY_PREFIX}:response:#{digest}"
  end

  def read_cache
    ttl = SiteSetting.proxy_safe_cache_seconds.to_i
    return nil if ttl <= 0

    raw = Discourse.redis.get(cache_key)
    return nil if raw.blank?

    parsed = JSON.parse(raw)
    {
      body: parsed["body"].to_s,
      content_type: parsed["content_type"].presence || "text/plain",
    }
  rescue JSON::ParserError
    {
      body: raw,
      content_type: "text/plain",
    }
  end

  def write_cache(body, content_type)
    ttl = SiteSetting.proxy_safe_cache_seconds.to_i
    return if ttl <= 0

    payload = {
      body: body,
      content_type: content_type.presence || "text/plain",
    }

    Discourse.redis.setex(cache_key, ttl, payload.to_json)
  end

  def normalized_response_content_type(response)
    response.headers["content-type"].presence || "text/plain"
  end

  def normalize_status(status)
    code = status.to_i
    code.between?(100, 599) ? code : 200
  end
end
