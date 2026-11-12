---
status: accepted
date: 2026-10-23
---

# Use SwiftUI for the native macOS app

Galmuri needs a persistent Mac editing experience with native file permissions, selection, keyboard navigation, and recovery. We chose SwiftUI at the maintainer's request after considering a native host that reused the existing HTML UI. The HTML prototype remains a design reference; its visual structure informs a new native interface rather than becoming the app runtime.

Foundation and limited AppKit integration may handle file access and OS integration. The local macOS target and development identity are recorded in [ADR 0003](0003-local-development-boundary.md); public distribution choices remain open. This decision does not establish that direct Chrome writes are safe.
