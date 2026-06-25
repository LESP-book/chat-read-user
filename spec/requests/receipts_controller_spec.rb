# frozen_string_literal: true

RSpec.describe ChatReadReceipts::ReceiptsController do
  fab!(:current_user, :user)
  fab!(:reader, :user)
  fab!(:other_sender, :user)
  fab!(:channel) do
    Fabricate(:direct_message_channel, group: true, users: [current_user, reader, other_sender])
  end

  before do
    SiteSetting.chat_enabled = true
    SiteSetting.chat_allowed_groups = Group::AUTO_GROUPS[:everyone]
    SiteSetting.chat_read_receipts_enabled = true
  end

  def request_receipts(user: current_user, channel_id: channel.id, message_ids:)
    sign_in(user) if user

    post "/chat-read-receipts/receipts.json",
         params: {
           channel_id: channel_id,
           message_ids: message_ids,
         }
  end

  describe "#create" do
    it "rejects anonymous users" do
      message = Fabricate(:chat_message, chat_channel: channel, user: current_user)

      request_receipts(user: nil, message_ids: [message.id])

      expect(response.status).to eq(403)
    end

    it "rejects users without channel access" do
      outsider = Fabricate(:user)
      message = Fabricate(:chat_message, chat_channel: channel, user: current_user)

      request_receipts(user: outsider, message_ids: [message.id])

      expect(response.status).to eq(403)
    end

    it "rejects message_ids that do not belong to the requested channel" do
      other_channel = Fabricate(:direct_message_channel, users: [current_user, reader])
      message = Fabricate(:chat_message, chat_channel: other_channel, user: current_user)

      request_receipts(message_ids: [message.id])

      expect(response.status).to eq(400)
      expect(response.parsed_body["errors"].first).to match(/message_ids/)
    end

    it "does not return receipts for messages sent by other users" do
      message = Fabricate(:chat_message, chat_channel: channel, user: other_sender)
      channel.membership_for(reader).update!(last_read_message_id: message.id)

      request_receipts(message_ids: [message.id])

      expect(response.status).to eq(200)
      expect(response.parsed_body["receipts"]).to eq({})
    end

    it "returns receipts for current user's messages read by other users" do
      message = Fabricate(:chat_message, chat_channel: channel, user: current_user)
      read_at = 1.minute.ago
      channel
        .membership_for(reader)
        .update!(last_read_message_id: message.id, last_viewed_at: read_at)

      request_receipts(message_ids: [message.id])

      expect(response.status).to eq(200)

      receipt = response.parsed_body.dig("receipts", message.id.to_s).first
      expect(receipt["id"]).to eq(reader.id)
      expect(receipt["username"]).to eq(reader.username)
      expect(receipt["avatar_template"]).to eq(reader.avatar_template)
      expect(receipt["last_read_at"]).to eq(read_at.iso8601)
    end

    it "only returns users whose last_read_message_id is greater than or equal to the message id" do
      message_1 = Fabricate(:chat_message, chat_channel: channel, user: current_user)
      message_2 = Fabricate(:chat_message, chat_channel: channel, user: current_user)
      channel.membership_for(reader).update!(last_read_message_id: message_1.id)

      request_receipts(message_ids: [message_1.id, message_2.id])

      expect(response.status).to eq(200)
      expect(response.parsed_body.dig("receipts", message_1.id.to_s).map { |user| user["id"] }).to eq(
        [reader.id],
      )
      expect(response.parsed_body.dig("receipts", message_2.id.to_s)).to eq([])
    end

    it "shows each reader only on the latest current-user message they have read" do
      message_1 = Fabricate(:chat_message, chat_channel: channel, user: current_user)
      message_2 = Fabricate(:chat_message, chat_channel: channel, user: current_user)
      channel.membership_for(reader).update!(last_read_message_id: message_2.id)

      request_receipts(message_ids: [message_1.id, message_2.id])

      expect(response.status).to eq(200)
      expect(response.parsed_body.dig("receipts", message_1.id.to_s)).to eq([])
      expect(response.parsed_body.dig("receipts", message_2.id.to_s).map { |user| user["id"] }).to eq(
        [reader.id],
      )
    end

    it "excludes the current user from receipts" do
      message = Fabricate(:chat_message, chat_channel: channel, user: current_user)
      channel.membership_for(current_user).update!(last_read_message_id: message.id)
      channel.membership_for(reader).update!(last_read_message_id: message.id)

      request_receipts(message_ids: [message.id])

      expect(response.status).to eq(200)
      reader_ids = response.parsed_body.dig("receipts", message.id.to_s).map { |user| user["id"] }
      expect(reader_ids).to contain_exactly(reader.id)
    end

    it "uses thread memberships for thread replies" do
      thread_channel = Fabricate(:chat_channel, threading_enabled: true)
      thread_channel.add(current_user)
      thread_channel.add(reader)

      thread =
        Fabricate(
          :chat_thread,
          channel: thread_channel,
          original_message_user: current_user,
          old_om: true,
        )
      reply =
        Fabricate(:chat_message, chat_channel: thread_channel, thread: thread, user: current_user)

      Fabricate(
        :user_chat_thread_membership,
        user: reader,
        thread: thread,
        last_read_message_id: reply.id,
      )

      request_receipts(channel_id: thread_channel.id, message_ids: [reply.id])

      expect(response.status).to eq(200)
      receipt = response.parsed_body.dig("receipts", reply.id.to_s).first
      expect(receipt["id"]).to eq(reader.id)
      expect(receipt["last_read_at"]).to eq(nil)
      expect(response.parsed_body.dig("meta", "notes", reply.id.to_s)).to match(/no reliable read timestamp/)
    end
  end
end
