# frozen_string_literal: true

# name: discourse-proxy-safe
# about: A safe, allowlisted reverse proxy for fetching remote Discourse content server-side.
# version: 0.1.0
# authors: You
# url: https://github.com/your-org/discourse-proxy-safe

enabled_site_setting :proxy_safe_enabled

after_initialize do
  module ::DiscourseProxySafe
    PLUGIN_NAME = "discourse-proxy-safe"

    autoload :ProxyController,
             "#{Rails.root}/plugins/discourse-proxy-safe/app/controllers/discourse_proxy_safe/proxy_controller"
  end

  Discourse::Application.routes.append do
    get "/discourse-proxy-safe" =>
          "discourse_proxy_safe/proxy#fetch",
          constraints: { format: :json }
  end
end