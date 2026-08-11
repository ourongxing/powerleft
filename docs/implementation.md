# Implementation

PowerLeft is a small HID-to-IOKit bridge. It reads battery data from vendor-specific 2.4 GHz receiver protocols, normalizes the result, and publishes each connected peripheral as a native macOS accessory power source.

## Data flow

```text
2.4 GHz receiver
        │
        ▼
BatteryDriver
        │ BatteryReading
        ▼
DeviceMonitor
        ├── menu bar status
        └── macOS Accessory Power Source
```

Each polling cycle asks every registered driver for all of its `DeviceBatteryReading` values. A successful reading creates or updates the matching menu and macOS power source. Devices omitted from a successful receiver scan are hidden. A missing receiver hides all devices previously published by that driver, while a transient protocol error keeps the last valid reading.

## Components

- `PowerLeft/Models/Models.swift` defines `DeviceDescriptor`, `BatteryReading`, `BatteryDriver`, errors, and `DriverRegistry`.
- `PowerLeft/Services/HIDDeviceAccess.swift` matches and opens the receiver management interface, then guarantees cleanup.
- `PowerLeft/Drivers` contains one independent implementation per supported device.
- `PowerLeft/Services/PowerSource.swift` publishes normalized readings through the macOS IOKit power-source interface.
- `PowerLeft/App/AppDelegate.swift` handles generic polling, menu state, connection state, and launch-at-login behavior.
- `PowerLeft/App/main.swift` starts the menu bar app or runs the `--once` diagnostic mode.

## HID access

The current drivers use the receiver management interface at Usage Page `0x008C`, Usage `0x01`. Matching the management interface directly avoids opening ordinary mouse or keyboard interfaces that may be held by input-customization software.

`HIDDeviceAccess.withManagementDevice` owns the common lifecycle:

1. Match the receiver VID, PID, usage page, and usage.
2. Open the matching `IOHIDDevice`.
3. Execute the driver-specific query.
4. Close the device and manager on every exit path.

## Device protocols

### Jingzao JZM5

The JZM5 driver sends a 64-byte Output Report with Report ID `0xB3` and command `0x06`. It waits up to three seconds for Input Report `0xB4`.

The response byte at payload offset 19 stores both values:

```text
percent     = payload[19] & 0x7F
isCharging  = (payload[19] & 0x80) != 0
```

### Keychron 2.4 GHz devices

The Keychron driver matches every Keychron management interface rather than a fixed receiver PID, allowing 1K, 8K, and newer receiver variants to be discovered. It sends command `0x06` through Feature Report `0x51`, waits 200 ms for the receiver to prepare its response, and then reads the 21-byte report. This matches the request-response timing used by Keychron Launcher instead of relying on a cached report. The response includes connection state and the paired accessory VID/PID as well as its battery state.

```text
connected   = report[2] == 1
vendor ID   = report[4] << 8 | report[5]
product ID  = report[7] << 8 | report[6]
percent     = report[11]
isCharging  = (report[12] & 0x03) != 0
```

Disconnected receivers produce no reading, so their previous menu and battery-widget entries are removed. The percentage and reported Keychron VID are validated before publication. Accessory PID and receiver location form the stable identifier, allowing multiple Keychron receivers to be shown independently.

The VID/PID is also converted to the decimal VPID used by the Keychron Launcher product service. Metadata for an unseen VPID is resolved asynchronously and cached in `UserDefaults`; a successful lookup immediately refreshes the matching power source with its model name and accessory category. Network failures retain the category-and-PID fallback and are retried after a cooldown, so HID polling never depends on the service.

## macOS power-source publication

Each reading provides a `DeviceDescriptor` containing its display name, category, receiver VID/PID, accessory PID, and stable identifier. `PowerSource` converts this metadata and the latest reading into an `Accessory Source` dictionary and submits it through `IOPSSetPowerSourceDetails`.

The source is released when its receiver is disconnected, which unregisters it from the macOS Batteries widget. Merely marking a source absent can leave a blank accessory behind in the widget. The IOKit power-source API used here is undocumented and may change in future macOS releases.

## Menu bar presentation

The menu bar item combines an SF Symbols battery glyph with the selected device's exact percentage. Charging uses the battery-and-bolt symbol, while battery operation selects the nearest useful quarter-level glyph. Its tooltip and accessibility description include the device name and charging state.

When two or more devices are connected, the menu exposes a `菜单栏显示` submenu with the active device checkmarked. The explicit selection is stored in `UserDefaults`. If that device disconnects, the menu bar temporarily falls back to an available device and automatically restores the saved selection when it reconnects. The selector stays hidden when zero or one device is connected.

## Driver extension

Adding a device requires only a new `BatteryDriver` implementation and one registry entry:

1. Add a driver under `PowerLeft/Drivers` and include it in the PowerLeft target.
2. Define its `DeviceDescriptor`.
3. Implement `readBatteries()` using the device protocol.
4. Validate the returned percentage and charging state.
5. Register the driver in `DriverRegistry.all`.

Polling, disconnected-device hiding, menu presentation, and power-source publication remain generic. Keyboard drivers use `Keyboard` as their accessory category.

## Diagnostics

The same registry can be queried without starting the menu bar app:

```bash
dist/PowerLeft.app/Contents/MacOS/PowerLeft --once
```

Only connected devices are printed. This mode is intended for protocol development and hardware regression testing.
