# frozen_string_literal: true

DiscourseProxySafe::Engine.routes.draw do
  get "/fetch" => "proxy#fetch", defaults: { format: :json }
  get "/fetch_external" => "proxy#fetch_external", defaults: { format: :json }
end

Discourse::Application.routes.draw do
  mount ::DiscourseProxySafe::Engine, at: "/discourse-proxy-safe"
end
