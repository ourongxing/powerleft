# PowerLeft

PowerLeft brings battery levels from supported 2.4 GHz mice and keyboards into the native macOS Batteries widget.

## Features

- Supports Jingzao JZM5 and protocol-compatible Keychron 2.4 GHz devices.
- Discovers Keychron keyboards and mice from their receiver reports, including new product IDs without an app update.
- Handles multiple Keychron receivers at the same time.
- Displays the selected device's battery level and charging state directly in the menu bar.
- Lets you choose which device appears in the menu bar when multiple devices are connected.
- Provides a Shortcuts action that returns structured battery data for every connected device.
- Hides disconnected devices automatically.
- Polls devices in the background without keeping a vendor driver open.
- Uses independent device drivers so more mice and keyboards can be added easily.

PowerLeft resolves Keychron model names from the Keychron Launcher product service and caches them locally. The lookup runs only when a previously unseen product ID is connected. If the network or service is unavailable, the device remains usable and is shown as `Keychron Keyboard 0xPPPP` or `Keychron Mouse 0xPPPP`. No model requires a device-specific application driver.

## Development

Open `PowerLeft.xcodeproj` in Xcode to build and debug the app. For a command-line Release build:

```bash
./build.sh
```

The script writes the app to `dist/PowerLeft.app`. It automatically uses the first valid code-signing identity in the login keychain, or falls back to an ad-hoc signature when no identity is available. A signing identity with a Team Identifier is required for macOS Shortcuts to communicate with the App Intent.
