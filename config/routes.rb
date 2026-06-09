# frozen_string_literal: true

DiscourseProxySafe::Engine.routes.draw do
  get "/fetch" => "proxy#fetch"
end

Discourse::Application.routes.draw do
  mount ::DiscourseProxySafe::Engine, at: "/discourse-proxy-safe"
end