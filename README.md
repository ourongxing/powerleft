# PowerLeft

PowerLeft reads battery data from supported 2.4 GHz HID receivers and publishes each connected device as a native macOS accessory power source. Battery levels then appear in the macOS Batteries widget without requiring a vendor driver to remain open.

Disconnected devices are hidden automatically. PowerLeft polls connected receivers once per minute and keeps the last valid reading if a receiver is present but a single query fails.

![PowerLeft devices in the macOS Batteries widget](assets/macos-battery-widgets.png)

## Supported devices

| Device | Receiver VID | Receiver PID | Connection |
| --- | --- | --- | --- |
| Jingzao JZM5 | `0x362D` | `0xD107` | 2.4 GHz |
| Keychron M6 | `0x3434` | `0xD030` | 2.4 GHz |

Bluetooth mode is not supported. The device must already be paired with its receiver.

## Installation

1. Download `PowerLeft.app.zip` from Releases.
2. Extract the archive and move `PowerLeft.app` to `/Applications`.
3. Launch PowerLeft and select **Input Monitoring Permission** from its menu bar item.
4. Allow PowerLeft under **System Settings → Privacy & Security → Input Monitoring**, then restart the app.

Releases are ad-hoc signed and are not notarized with an Apple Developer ID. If macOS blocks the downloaded app, remove the quarantine attribute from PowerLeft only:

```bash
sudo xattr -dr com.apple.quarantine /Applications/PowerLeft.app
```

Do not disable Gatekeeper globally.

## AirBattery Nearcast

AirBattery is optional. PowerLeft publishes directly to the macOS Batteries widget without it. Nearcast integration currently applies to the JZM5 only.

1. Enable Nearcast in [AirBattery](https://github.com/lihaoyun6/AirBattery).
2. Copy the AirBattery Nearcast group ID into PowerLeft preferences:

   ```bash
   defaults write local.jzm5.batterytray nearcastGroupID \
     "$(defaults read com.lihaoyun6.AirBattery ncGroupID)"
   ```

3. Restart PowerLeft and allow local network access when prompted.

The group ID stays in PowerLeft preferences and is not embedded in the app or uploaded. Repeat the command if AirBattery resets its group ID.

## Build from source

Requirements:

- macOS 13 or later
- Xcode Command Line Tools
- Apple Silicon Mac for the default build target

```bash
./build.sh
open dist/PowerLeft.app
```

The build script creates an ad-hoc signed app at `dist/PowerLeft.app`.

Run a single hardware diagnostic without starting the menu bar app:

```bash
dist/PowerLeft.app/Contents/MacOS/PowerLeft --once
```

## Architecture

```text
Sources/
├── Drivers/
│   ├── JZM5Driver.swift
│   └── KeychronM6Driver.swift
├── AppDelegate.swift
├── HIDDeviceAccess.swift
├── Models.swift
├── NearcastSender.swift
├── PowerSource.swift
└── main.swift
```

- `BatteryDriver` defines the common interface for device-specific battery readers.
- `HIDDeviceAccess` owns shared HID matching, opening, and cleanup.
- `DriverRegistry` is the single registration point for supported devices.
- `AppDelegate` handles polling, menu state, and connection state generically.
- `PowerSource` publishes validated readings to the macOS Batteries widget.

### Add a device

1. Add a `BatteryDriver` implementation under `Sources/Drivers`.
2. Define its name, accessory category, VID/PID values, and stable identifier.
3. Implement its HID query in `readBattery()` and return a validated `BatteryReading`.
4. Register the driver in `DriverRegistry.all` in `Sources/Models.swift`.

The shared layer automatically handles polling, menu presentation, disconnected-device hiding, and macOS power-source publishing. Use `Keyboard` as the accessory category for keyboard drivers.

## Protocol notes

PowerLeft opens only the receiver management interface at Usage Page `0x008C`, Usage `0x01`.

- JZM5 sends Output Report `0xB3 + 0x06` and parses the battery state from Input Report `0xB4`.
- Keychron M6 reads battery and charging state from Feature Report `0x51`.

PowerLeft uses an undocumented macOS IOKit power-source interface. A future macOS release may change or remove this behavior. A browser-based device configurator may also hold exclusive access to the HID interface; close it before troubleshooting PowerLeft.

## Contributors

- LANMIN-X
- OpenAI Codex — protocol analysis, macOS bridge implementation, and project architecture
