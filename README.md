# PriType (Project Primitive Type)

**PriType** is a modern, Swift-based Korean Input Method for macOS. It aims to provide a native, stable, and customizable Hangul typing experience, built on top of the robust `libhangul` engine.

## ✨ Features

- **Pure Swift Implementation**: Native macOS input method built with Swift and InputMethodKit.
- **Stable & Fast**: 
  - Optimized for rapid typing without character loss.
  - Correctly handles input source switching events.
- **Smart Behavior**:
  - **Caps Lock Support**: Types lowercase Hangul even when Caps Lock is on (prevents `ㄲ` when you want `ㄱ`).
  - **Standard Double Consonant**: Types `ㄱ` + `ㄱ` as `ㄱㄱ` (requires `Shift` for `ㄲ`), giving you more control.
- **Native Aesthetics**:
  - Includes **High-Resolution Icons** (Retina ready) extracted and recreated from genuine system assets.
  - Fully supports the macOS Input Source Switcher (HUD) with proper icons.
  - Native selection and candidate UI integration.

## 🛠️ Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/your-username/PriType-Swift.git
   cd PriType-Swift
   ```

2. **Run the installer**
   The included script will build the project and install it to `~/Library/Input Methods`.
   ```bash
   ./install.sh
   ```

3. **Activate**
   - **Log out** and log back in (or restart your Mac) to let the system recognize the new input method.
   - Go to **System Settings** > **Keyboard** > **Input Sources**.
   - Click **Edit...** (or `+`).
   - Select **Korean** (or **Korea**) from the sidebar.
   - Add **PriType** to your list.

## ⌨️ Usage

- Switch to **PriType** using your standard input switching shortcut (e.g., `Control + Space`).
- Type Hangul naturally.
- Use `Shift` for double consonants (`ㄲ`, `ㄸ`, `ㅃ`, `ㅆ`, `ㅉ`).
- `Caps Lock` behaves smartly: input remains Hangul, preventing accidental English or double-consonant shifts.

## 🏗️ Development

- **Build**: `swift build -c release`
- **Icon Generation**: To regenerate icons, see the Python scripts in the history or use the `PriType.iconset` source.

## 📄 License

Based on `libhangul`. See LICENSE for details.
