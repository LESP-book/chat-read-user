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

返回体中的 `receipts` 只包含当前登录用户自己发送消息的已读用户，并排除当前用户自己。

## 权限边界

- 必须登录。
- 当前用户必须有权限访问目标 chat channel。
- `message_ids` 必须属于该 channel。
- 不暴露整个频道所有成员的 read state。
- 普通 channel 消息使用 `user_chat_channel_memberships.last_read_message_id` 判定。
- thread reply 使用 `user_chat_thread_memberships.last_read_message_id` 判定；该表没有可靠读取时间，因此 `last_read_at` 返回 `null`，并在 `meta.notes` 记录原因。

## 设置

- `chat_read_receipts_enabled`：默认开启。
- `chat_read_receipts_refresh_interval_seconds`：默认 3 秒，最小 1 秒。

## 验证

在 Discourse 根目录通过开发容器运行：

```bash
timeout 60 docker exec -u discourse:discourse -w /src -e RAILS_ENV=test discourse_dev bin/rspec plugins/chat-read-user/spec/requests/receipts_controller_spec.rb
docker exec -u discourse:discourse -w /src discourse_dev pnpm eslint plugins/chat-read-user/assets/javascripts/discourse/api-initializers/chat-read-receipts.js
```
