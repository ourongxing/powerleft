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
        ├── macOS Accessory Power Source
        └── optional AirBattery Nearcast
```

Each polling cycle asks every registered driver for a `BatteryReading`. A successful reading updates the menu and its macOS power source. A missing receiver hides both. A transient protocol error keeps the last valid reading.

## Components

- `Sources/Models.swift` defines `DeviceDescriptor`, `BatteryReading`, `BatteryDriver`, errors, and `DriverRegistry`.
- `Sources/HIDDeviceAccess.swift` matches and opens the receiver management interface, then guarantees cleanup.
- `Sources/Drivers` contains one independent implementation per supported device.
- `Sources/PowerSource.swift` publishes normalized readings through the macOS IOKit power-source interface.
- `Sources/AppDelegate.swift` handles generic polling, menu state, connection state, and launch-at-login behavior.
- `Sources/NearcastSender.swift` provides the optional AirBattery integration.
- `Sources/main.swift` starts the menu bar app or runs the `--once` diagnostic mode.

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

### Keychron M6

The Keychron M6 driver reads a 21-byte Feature Report with Report ID `0x51`.

```text
percent     = report[11]
isCharging  = (report[12] & 0x03) != 0
```

The percentage is validated against the `0...100` range before publication.

## macOS power-source publication

Each driver provides a `DeviceDescriptor` containing its display name, category, receiver VID/PID, accessory PID, and stable identifier. `PowerSource` converts this metadata and the latest reading into an `Accessory Source` dictionary and submits it through `IOPSSetPowerSourceDetails`.

The source is marked absent when its receiver is disconnected, which removes it from the macOS Batteries widget. The IOKit power-source API used here is undocumented and may change in future macOS releases.

## Driver extension

Adding a device requires only a new `BatteryDriver` implementation and one registry entry:

1. Add a driver under `Sources/Drivers`.
2. Define its `DeviceDescriptor`.
3. Implement `readBattery()` using the device protocol.
4. Validate the returned percentage and charging state.
5. Register the driver in `DriverRegistry.all`.

Polling, disconnected-device hiding, menu presentation, and power-source publication remain generic. Keyboard drivers use `Keyboard` as their accessory category.

## Diagnostics

The same registry can be queried without starting the menu bar app:

```bash
dist/PowerLeft.app/Contents/MacOS/PowerLeft --once
```

Only connected devices are printed. This mode is intended for protocol development and hardware regression testing.
