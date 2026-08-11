import Foundation
import IOKit.hid

enum HIDDeviceAccess {
    private static let accessLock = NSLock()

    static func withManagementDevice<T>(
        for descriptor: DeviceDescriptor,
        _ body: (IOHIDDevice) throws -> T
    ) throws -> T {
        let values = try withManagementDevices(for: descriptor, limit: 1, body)
        guard let value = values.first else { throw BridgeError.noReceiver(descriptor.name) }
        return value
    }

    static func withManagementDevices<T>(
        for descriptor: DeviceDescriptor,
        limit: Int = .max,
        _ body: (IOHIDDevice) throws -> T
    ) throws -> [T] {
        accessLock.lock()
        defer { accessLock.unlock() }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        var matching = [
            kIOHIDVendorIDKey as String: descriptor.vendorID,
            kIOHIDPrimaryUsagePageKey as String: 0x008C,
            kIOHIDPrimaryUsageKey as String: 0x0001
        ]
        if let productID = descriptor.receiverProductID {
            matching[kIOHIDProductIDKey as String] = productID
        }
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let managerResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard managerResult == kIOReturnSuccess else { throw BridgeError.open(managerResult) }
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !devices.isEmpty else {
            throw BridgeError.noReceiver(descriptor.name)
        }

        return try devices.prefix(limit).map { receiver in
            let openResult = IOHIDDeviceOpen(receiver, IOOptionBits(kIOHIDOptionsTypeNone))
            guard openResult == kIOReturnSuccess else { throw BridgeError.open(openResult) }
            defer { IOHIDDeviceClose(receiver, IOOptionBits(kIOHIDOptionsTypeNone)) }
            return try body(receiver)
        }
    }

    static func locationID(of device: IOHIDDevice) -> Int {
        (IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? NSNumber)?.intValue ?? 0
    }
}
