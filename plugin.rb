# frozen_string_literal: true

# name: discourse-proxy-safe
# about: A safe, allowlisted reverse proxy for fetching remote Discourse content server-side.
# version: 0.1.0
# authors: Denver Geeks
# url: https://github.com/denvergeeks/discourse-proxy-safe

enabled_site_setting :proxy_safe_enabled

module ::DiscourseProxySafe
  PLUGIN_NAME = "discourse-proxy-safe"
end

require_relative "lib/discourse_proxy_safe/engine"

after_initialize do
  require_relative "app/controllers/discourse_proxy_safe/proxy_controller"
end