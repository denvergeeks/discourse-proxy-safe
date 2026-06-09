# frozen_string_literal: true

module ::DiscourseProxySafe
  class Engine < ::Rails::Engine
    engine_name DiscourseProxySafe::PLUGIN_NAME
    isolate_namespace DiscourseProxySafe
  end
end