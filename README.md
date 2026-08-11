# PowerLeft

PowerLeft brings battery levels from supported 2.4 GHz mice and keyboards into the native macOS Batteries widget.

## Features

- Supports Jingzao JZM5 and protocol-compatible Keychron 2.4 GHz devices.
- Discovers Keychron keyboards and mice from their receiver reports, including new product IDs without an app update.
- Handles multiple Keychron receivers at the same time.
- Displays battery level and charging state in macOS.
- Hides disconnected devices automatically.
- Polls devices in the background without keeping a vendor driver open.
- Uses independent device drivers so more mice and keyboards can be added easily.

Keychron devices are shown as `Keychron Keyboard 0xPPPP` or `Keychron Mouse 0xPPPP`, using the accessory PID reported by the receiver. No model requires a device-specific application driver.

## Development

Open `PowerLeft.xcodeproj` in Xcode to build and debug the app. For a command-line Release build:

```bash
./build.sh
```

The script writes the ad-hoc signed app to `dist/PowerLeft.app`.
