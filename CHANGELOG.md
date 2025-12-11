# Changelog

All notable changes to PriType-Swift will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Localization support with L10n.swift for type-safe string access
- Korean (ko) and English (en) Localizable.strings
- Multi-monitor Finder heuristic tests
- SwiftLint configuration (.swiftlint.yml)
- Extended KeyCode constants with helper methods

### Changed
- InputSourceManager refactored to TIS API only (removed shell commands)
- HangulComposer separated TextConvenience logic to dedicated handler
- Adapter classes refactored with BaseClientAdapter inheritance
- Finder detection improved with validAttributesForMarkedText

### Security
- Removed all shell command execution (PlistBuddy, killall cfprefsd)
- Added -strict-concurrency=complete Swift flag

## [1.0.0] - 2025-12-11

### Added
- Initial release of PriType-Swift
- Hangul composition using libhangul-swift
- Korean/English toggle via Right Command or Control+Space
- SwiftUI-based settings window
- Auto-capitalize and double-space period features
- Finder desktop detection for floating window prevention
- Secure input field detection (password fields)
- Debug-only logging with complete release removal
