# PowerLeft

PowerLeft brings battery levels from supported 2.4 GHz mice and keyboards into the native macOS Batteries widget.

## Features

- Supports Jingzao JZM5 and Keychron M6 receivers.
- Displays battery level and charging state in macOS.
- Hides disconnected devices automatically.
- Polls devices in the background without keeping a vendor driver open.
- Uses independent device drivers so more mice and keyboards can be added easily.

## Development

Open `PowerLeft.xcodeproj` in Xcode to build and debug the app. For a command-line Release build:

```bash
./build.sh
```

The script writes the ad-hoc signed app to `dist/PowerLeft.app`.
