# frozen_string_literal: true

# name: chat-read-user
# about: Restores chat read receipt avatars through a permission-protected server API.
# version: 0.1.0
# authors: kuma
# url: https://github.com/kuma/chat-read-user

enabled_site_setting :chat_read_receipts_enabled

register_asset "stylesheets/common/chat-read-receipts.scss"

module ::ChatReadReceipts
  PLUGIN_NAME = "chat-read-user"
end

require_relative "lib/chat_read_receipts/engine"
