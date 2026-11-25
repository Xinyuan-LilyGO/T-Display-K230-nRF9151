# Changelog

[English](./CHANGELOG.MD) | [中文](./CHANGELOG_CN.MD)

## v1.99.3 - 2026-11-25

- Added a configurable IPv4 DNS fallback for modem-offloaded socket requests
  when the cellular PDP context does not provide DNS servers.
- Enabled the DNS fallback in the K230 Serial LTE Modem profile with
  `223.5.5.5` as the default resolver.
- Updated the Serial LTE Modem application version to `1.99.3` so the installed
  firmware can be identified from the K230 modem information page.
