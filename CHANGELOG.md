# Changelog

## Unreleased

### Fixed
- Fixed macOS build failure caused by unconditional `UIKit` import in `DownloadManager`.
- Fixed request header merge order so request-level headers override global headers.
- Fixed timeout fallback behavior: request timeout now falls back to `CryoNetConfiguration.defaultTimeout` when `RequestModel.overtime <= 0`.
- Fixed stream request behavior to apply timeout and include parameters (`GET` query + non-`GET` body fallback).
- Fixed `DownloadManager.pauseTask` so it no longer mutates non-downloading tasks into `paused`.
- Fixed upload queue accounting on pause/resume to keep concurrency counters and scheduling consistent.
- Fixed invalid download URL handling to avoid runtime crash (`fatalError`) and mark task as `failed`.
- Fixed upload completion path to avoid multi-writer task state races by handling interceptor/model parsing inside actor flow.
- Fixed manager pool cleanup APIs to be awaitable (`async`) and complete cleanup before returning.
- Fixed Sendable diagnostics on interceptor JSON model APIs by tightening generic constraints.

### Added
- Added and expanded unit tests for:
  - default overtime semantics,
  - download pause/cancel/remove behavior,
  - invalid download URL behavior,
  - awaitable pool removal behavior for download/upload managers.
- Added documentation updates in README for timeout priority and async pool cleanup APIs.
