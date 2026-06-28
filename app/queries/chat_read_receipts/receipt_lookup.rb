# frozen_string_literal: true

module ChatReadReceipts
  class ReceiptLookup
    THREAD_READ_TIMESTAMP_UNAVAILABLE =
      "chat thread memberships store last_read_message_id but no reliable read timestamp"

    def self.call(...)
      new(...).call
    end

    def initialize(channel:, current_user:, guardian:, message_ids:)
      @channel = channel
      @current_user = current_user
      @guardian = guardian
      @message_ids = message_ids
    end

    def call
      return { receipts: {}, meta: meta } if message_ids.empty?

      ensure_messages_belong_to_channel!

      receipt_eligible_messages = visible_messages.select { |message| show_receipts_for_message?(message) }
      return { receipts: {}, meta: meta } if receipt_eligible_messages.empty?

      receipts = {}
      visible_messages.each { |message| receipts[message.id.to_s] = [] }

      attach_channel_receipts!(
        receipts,
        visible_messages.reject { |message| thread_reply?(message) },
        receipt_eligible_messages.reject { |message| thread_reply?(message) },
      )
      attach_thread_receipts!(
        receipts,
        visible_messages.select { |message| thread_reply?(message) },
        receipt_eligible_messages.select { |message| thread_reply?(message) },
      )

      { receipts: receipts, meta: meta }
    end

    private

    attr_reader :channel, :current_user, :guardian, :message_ids

    def meta
      @meta ||= { notes: {}, skipped: {} }
    end

    def ensure_messages_belong_to_channel!
      fetched_ids = messages.map(&:id)
      return if (message_ids - fetched_ids).empty?

      raise Discourse::InvalidParameters.new(:message_ids)
    end

    def messages
      @messages ||=
        ::Chat::Message
          .with_deleted
          .includes(:chat_channel, :thread)
          .where(id: message_ids, chat_channel_id: channel.id)
          .to_a
    end

    def visible_messages
      @visible_messages ||=
        messages.select do |message|
          visible = message.deleted_at.blank? || message.user_id == current_user.id || guardian.is_staff?
          meta[:skipped][message.id.to_s] = "message is not visible to current user" if !visible
          visible
        end
    end

    def thread_reply?(message)
      message.thread_reply?
    end

    def show_receipts_for_message?(message)
      SiteSetting.chat_read_receipts_show_on_all_visible_messages || message.user_id == current_user.id
    end

    def attach_channel_receipts!(receipts, channel_messages, own_channel_messages)
      return if channel_messages.empty? || own_channel_messages.empty?

      messages_by_id = channel_messages.index_by(&:id)

      memberships =
        ::Chat::UserChatChannelMembership
          .includes(:user)
          .where(chat_channel_id: channel.id)
          .where.not(user_id: current_user.id)
          .where.not(last_read_message_id: nil)

      memberships.each do |membership|
        next if latest_read_message(own_channel_messages, membership.last_read_message_id).blank?

        message = messages_by_id[membership.last_read_message_id]
        next if message.blank?

        receipts[message.id.to_s] << serialize_user(membership.user, membership.last_viewed_at)
      end
    end

    def attach_thread_receipts!(receipts, thread_messages, own_thread_messages)
      return if thread_messages.empty? || own_thread_messages.empty?

      thread_ids = thread_messages.map(&:thread_id).uniq
      memberships_by_thread_id =
        ::Chat::UserChatThreadMembership
          .includes(:user)
          .where(thread_id: thread_ids)
          .where.not(user_id: current_user.id)
          .where.not(last_read_message_id: nil)
          .group_by(&:thread_id)

      thread_messages.each { |message| meta[:notes][message.id.to_s] = THREAD_READ_TIMESTAMP_UNAVAILABLE }

      thread_messages.group_by(&:thread_id).each do |thread_id, messages|
        own_messages = own_thread_messages.select { |message| message.thread_id == thread_id }
        next if own_messages.empty?

        messages_by_id = messages.index_by(&:id)

        memberships_by_thread_id.fetch(thread_id, []).each do |membership|
          next if latest_read_message(own_messages, membership.last_read_message_id).blank?

          message = messages_by_id[membership.last_read_message_id]
          next if message.blank?

          receipts[message.id.to_s] << serialize_user(membership.user, nil)
        end
      end
    end

    def latest_read_message(messages, last_read_message_id)
      messages.select { |message| message.id <= last_read_message_id }.max_by(&:id)
    end

    def serialize_user(user, last_read_at)
      {
        id: user.id,
        username: user.username,
        name: user.name,
        avatar_template: user.avatar_template,
        last_read_at: last_read_at&.iso8601,
      }
    end
  end
end
