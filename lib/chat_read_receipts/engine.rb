# frozen_string_literal: true

module ::ChatReadReceipts
  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME
    isolate_namespace ChatReadReceipts

    config.autoload_paths << File.join(config.root, "app/queries")

    config.after_initialize do
      Discourse::Application.routes.append do
        post "/chat-read-receipts/receipts" => "chat_read_receipts/receipts#create"
      end
    end
  end
end
