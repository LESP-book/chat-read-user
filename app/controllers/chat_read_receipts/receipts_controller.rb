# frozen_string_literal: true

module ChatReadReceipts
  class ReceiptsController < ::Chat::ApiController
    requires_plugin PLUGIN_NAME

    def create
      raise Discourse::InvalidAccess if !SiteSetting.chat_read_receipts_enabled

      channel = find_channel
      guardian.ensure_can_join_chat_channel!(channel)

      render_json_dump(
        ReceiptLookup.call(
          channel: channel,
          current_user: current_user,
          guardian: guardian,
          message_ids: parsed_message_ids,
        ),
      )
    end

    private

    def find_channel
      channel = ::Chat::Channel.find_by(id: parsed_channel_id)
      raise Discourse::NotFound if channel.blank?

      channel
    end

    def parsed_channel_id
      @parsed_channel_id ||= parse_positive_integer(params.require(:channel_id), :channel_id)
    end

    def parsed_message_ids
      raw_message_ids = params.require(:message_ids)
      raise Discourse::InvalidParameters.new(:message_ids) if !raw_message_ids.is_a?(Array)

      @parsed_message_ids ||=
        raw_message_ids.map { |message_id| parse_positive_integer(message_id, :message_ids) }.uniq
    end

    def parse_positive_integer(value, param_name)
      integer = Integer(value)
      raise ArgumentError if integer <= 0

      integer
    rescue ArgumentError, TypeError
      raise Discourse::InvalidParameters.new(param_name)
    end
  end
end
