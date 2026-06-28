# chat-read-user

这是一个独立 Discourse 插件，用服务端 API 恢复聊天消息的“已读用户头像”能力。

## API

`POST /chat-read-receipts/receipts`

请求体：

```json
{
  "channel_id": 123,
  "message_ids": [1001, 1002, 1003]
}
```

返回体中的 `receipts` 按“读者实际读到的可见消息 ID”分组。默认情况下，读者必须至少读过请求集合中当前登录用户自己发送的一条消息，且会排除当前用户自己。开启 `chat_read_receipts_show_on_all_visible_messages` 后，则按当前登录用户可见的所有请求消息计算。

## 权限边界

- 必须登录。
- 当前用户必须有权限访问目标 chat channel。
- `message_ids` 必须属于该 channel。
- 不暴露整个频道所有成员的 read state。
- 默认只显示当前用户自己消息上的已读；开启 `chat_read_receipts_show_on_all_visible_messages` 后，显示当前用户可见消息上的已读。
- 不把读者强行挂到上一条当前用户消息；如果读者实际读到的消息不在本次请求集合里，则不伪造已读头像位置。
- 普通 channel 消息使用 `user_chat_channel_memberships.last_read_message_id` 判定。
- thread reply 使用 `user_chat_thread_memberships.last_read_message_id` 判定；该表没有可靠读取时间，因此 `last_read_at` 返回 `null`，并在 `meta.notes` 记录原因。

## 设置

- `chat_read_receipts_enabled`：默认开启。
- `chat_read_receipts_refresh_interval_seconds`：默认 3 秒，最小 1 秒。
- `chat_read_receipts_inline_avatar_count`：行内展示的头像数量，默认 5，超过后折叠为 `+N`；点击后仍显示完整名单。
- `chat_read_receipts_show_on_all_visible_messages`：默认关闭；开启后，有频道访问权限的用户可以看到所有可见消息上的已读用户。

## 验证

在 Discourse 根目录通过开发容器运行：

```bash
timeout 60 docker exec -u discourse:discourse -w /src -e RAILS_ENV=test discourse_dev bin/rspec plugins/chat-read-user/spec/requests/receipts_controller_spec.rb
docker exec -u discourse:discourse -w /src discourse_dev pnpm eslint plugins/chat-read-user/assets/javascripts/discourse/api-initializers/chat-read-receipts.js
```
