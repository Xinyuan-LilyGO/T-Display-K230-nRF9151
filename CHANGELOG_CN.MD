# 版本变更记录

[English](./CHANGELOG.MD) | [中文](./CHANGELOG_CN.MD)

## v1.99.3 - 2026-11-25

- 当蜂窝 PDP 上下文未提供 DNS 服务器时，为 modem offload socket 请求增加可配置的
  IPv4 DNS fallback。
- 在 K230 Serial LTE Modem 配置中默认启用 DNS fallback，默认解析服务器为
  `223.5.5.5`。
- 将 Serial LTE Modem 应用版本更新为 `1.99.3`，可在 K230 Modem Information 页面
  确认当前安装的固件版本。
