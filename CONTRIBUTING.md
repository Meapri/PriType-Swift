# Contributing to PriType-Swift

Thank you for your interest in contributing to PriType-Swift! This document provides guidelines for contributing to the project.

## Development Setup

### Prerequisites
- macOS 14 (Sonoma) or later
- Xcode 15+ with Swift 6.0
- Accessibility permissions (System Settings → Privacy & Security → Accessibility)

### Building
```bash
git clone https://github.com/your-org/PriType-Swift.git
cd PriType-Swift
swift build
```

### Running Tests
```bash
swift run PriTypeVerify
```

## Code Style

### Swift Guidelines
- Follow [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- Use meaningful variable names (avoid single letters except in closures)
- Document all public APIs with DocC-style comments

### Formatting
- Configure SwiftLint: `.swiftlint.yml` is included
- Maximum line length: 150 characters (warning), 200 (error)
- Use 4-space indentation

## Pull Request Process

1. **Fork** the repository and create your branch from `main`
2. **Test** your changes with `swift run PriTypeVerify`
3. **Update** documentation if you're changing public APIs
4. **Update** CHANGELOG.md under `[Unreleased]` section
5. **Submit** your PR with a clear description

## Reporting Issues

Please include:
- macOS version
- Steps to reproduce
- Expected vs actual behavior
- Debug logs (if applicable, from `~/Library/Logs/PriType/`)

## License

By contributing, you agree that your contributions will be licensed under the project's license.
