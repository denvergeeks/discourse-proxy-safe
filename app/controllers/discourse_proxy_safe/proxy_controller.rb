# frozen_string_literal: true

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
  ].freeze

  def fetch
    cached = read_cache
    if cached
      render json: cached, status: 200
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
      render json: {
               error: "Remote response exceeded the maximum allowed size.",
             },
             status: 502
      return
    end

    body = response.body
    write_cache(body)

    render plain: body,
           content_type: "application/json",
           status: response.code.to_i
  end

  private

  def check_plugin_enabled
    unless SiteSetting.proxy_safe_enabled
      render json: { error: "Proxy is disabled." }, status: 404
    end
  end

  def check_access_level
    level = SiteSetting.proxy_safe_access_level

    case level
    when "logged_in"
      unless current_user
        render json: { error: "You must be logged in to use this proxy." },
               status: 403
      end
    when "session"
      unless current_user && request.session[:current_user_id].present?
        render json: { error: "A valid session is required to use this proxy." },
               status: 403
      end
    when "public"
      # no restriction
    else
      render json: { error: "Invalid access level configured." }, status: 500
    end
  end

  def check_rate_limit
    limit = SiteSetting.proxy_safe_rate_limit_per_minute.to_i
    return if limit <= 0

    key = rate_limit_key
    count = Discourse.redis.incr(key)
    Discourse.redis.expire(key, 60) if count == 1

    if count > limit
      render json: {
               error: "Rate limit exceeded. Please wait before retrying.",
             },
             status: 429
    end
  end

  def rate_limit_key
    identifier =
      if current_user
        "user:#{current_user.id}"
      else
        "ip:#{request.remote_ip}"
      end
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

    unless %w[http https].include?(uri.scheme)
      render json: { error: "Only http and https URLs are permitted." },
             status: 400
      return
    end

    if uri.host.blank?
      render json: { error: "URL has no host." }, status: 400
      return
    end

    allowed = SiteSetting.proxy_safe_allowed_domains
                .split("|")
                .map(&:strip)
                .reject(&:blank?)

    unless allowed.include?(uri.host.downcase)
      render json: {
               error:
                 "Domain '#{uri.host}' is not in the proxy allowlist.",
             },
             status: 403
      return
    end

    @proxy_uri = uri
  end

  def fetch_remote
    timeout = SiteSetting.proxy_safe_request_timeout_seconds.to_i

    uri = @proxy_uri.to_s

    connection =
      Faraday.new do |f|
        f.options.timeout = timeout
        f.options.open_timeout = [timeout, 5].min
        f.adapter Faraday.default_adapter
      end

    connection.get(uri) do |req|
      req.headers["Accept"] = "application/json, text/plain, */*"
      req.headers["User-Agent"] = "discourse-proxy-safe/0.1 (+#{Discourse.base_url})"
    end
  rescue Faraday::TimeoutError, Faraday::ConnectionFailed
    nil
  end

  def acceptable_content_type?(response)
    ct = response.headers["content-type"].to_s.downcase
    ALLOWED_CONTENT_TYPES.any? { |allowed| ct.include?(allowed) }
  end

  def acceptable_size?(response)
    max_bytes = SiteSetting.proxy_safe_max_response_size_kb.to_i * 1024
    response.body.bytesize <= max_bytes
  end

  def cache_key
    "#{CACHE_KEY_PREFIX}:response:#{Digest::SHA256.hexdigest(@proxy_uri.to_s)}"
  end

  def read_cache
    ttl = SiteSetting.proxy_safe_cache_seconds.to_i
    return nil if ttl <= 0
    Discourse.redis.get(cache_key)
  end

  def write_cache(body)
    ttl = SiteSetting.proxy_safe_cache_seconds.to_i
    return if ttl <= 0
    Discourse.redis.setex(cache_key, ttl, body)
  end
end