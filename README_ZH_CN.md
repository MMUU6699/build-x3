# Build X

Build X 是适用于手机与桌面的 Flutter 聊天客户端。所有模型文本请求都通过 Mistral Conversations API 使用 `mistral-medium-latest`。

## 开始使用

1. 安装 Flutter 3.44.9 或更高版本，然后运行 `flutter pub get`。
2. 在受支持的设备上运行 `flutter run`。
3. 打开 **设置 → Mistral 连接**，保存 Mistral API 密钥。

密钥保存在平台安全存储中。每个本地聊天会保存对应的 Mistral 会话 ID，以便后续消息继续同一会话。Mistral 账户可能产生 API 费用。

搜索设置可以保存供未来使用的技能和浏览器账号；目前尚未实现浏览器登录自动化。可以在 **设置 → 记忆** 中查看、编辑、归档和删除记忆。

为兼容已有数据，内部 Dart 包名和磁盘数据格式保留原有标识。本项目基于[上游源码](https://github.com/Chevey339/kelivo)，许可条款见 [LICENSE](LICENSE)。
