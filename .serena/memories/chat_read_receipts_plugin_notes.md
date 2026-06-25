# chat-read-user 插件记录

- 目标：为 Discourse 2026.06 的 chat 恢复“已读用户头像”能力，不能修改 Discourse core。
- 本地依据：普通 channel 已读状态来自 `user_chat_channel_memberships.last_read_message_id`，读取时间可用 `last_viewed_at`；thread reply 已读状态来自 `user_chat_thread_memberships.last_read_message_id`，该表没有可靠 read timestamp。
- API：`POST /chat-read-receipts/receipts`，只返回当前登录用户自己发送消息的已读用户，排除当前用户，不暴露全频道 read state。
- 权限：继承 `Chat::ApiController`，使用 `guardian.ensure_can_join_chat_channel!` 校验 channel 访问；`message_ids` 必须属于 channel。
- 已读头像分配规则：虽然 `last_read_message_id >= message.id` 表示 reader 已读所有更早消息，但 API 只把每个 reader 挂到其已读到的最新一条当前用户消息下，避免同一 reader 在多条消息下重复显示。
- 前端：`apiInitializer` + `api.decorateChatMessage`，只在当前用户自己的可见消息容器上渲染 `.crr-read-receipt`，失败时 `console.warn` 且移除插件头像。
- 设置：`chat_read_receipts_enabled` 默认 true；`chat_read_receipts_refresh_interval_seconds` 默认 3，最小 1 秒，避免 0/负数导致浏览器紧密轮询。
- 验证：容器内 request spec 9 examples 0 failures；ESLint 通过；Ruby 语法检查通过；`git diff --check` 通过；内置浏览器在 `http://localhost:3000/chat/c/general/2` 检查到仅 1 个 `.crr-read-receipt`，不再每条消息重复显示 user7。