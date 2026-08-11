import Foundation
import IOKit.hid

enum HIDDeviceAccess {
    static func withManagementDevice<T>(
        for descriptor: DeviceDescriptor,
        _ body: (IOHIDDevice) throws -> T
    ) throws -> T {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey as String: descriptor.vendorID,
            kIOHIDProductIDKey as String: descriptor.receiverProductID,
            kIOHIDPrimaryUsagePageKey as String: 0x008C,
            kIOHIDPrimaryUsageKey as String: 0x0001
        ] as CFDictionary)

        let managerResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard managerResult == kIOReturnSuccess else { throw BridgeError.open(managerResult) }
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let receiver = devices.first else {
            throw BridgeError.noReceiver(descriptor.name)
        }

        let openResult = IOHIDDeviceOpen(receiver, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else { throw BridgeError.open(openResult) }
        defer { IOHIDDeviceClose(receiver, IOOptionBits(kIOHIDOptionsTypeNone)) }

        return try body(receiver)
    }
}
