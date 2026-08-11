import Foundation
import IOKit

private typealias PowerSourceID = UnsafeMutableRawPointer
@_silgen_name("IOPSCreatePowerSource") private func IOPSCreatePowerSource(_ source: UnsafeMutablePointer<PowerSourceID?>) -> IOReturn
@_silgen_name("IOPSSetPowerSourceDetails") private func IOPSSetPowerSourceDetails(_ source: PowerSourceID, _ details: CFDictionary) -> IOReturn
@_silgen_name("IOPSReleasePowerSource") private func IOPSReleasePowerSource(_ source: PowerSourceID) -> IOReturn

final class PowerSource {
    private var source: PowerSourceID?
    private let device: DeviceDescriptor

    init(device: DeviceDescriptor) throws {
        self.device = device
        let result = IOPSCreatePowerSource(&source)
        guard result == kIOReturnSuccess, source != nil else { throw BridgeError.powerSource(result) }
    }

    deinit {
        if let source { _ = IOPSReleasePowerSource(source) }
    }

    func remove() throws {
        guard let source else { return }
        let result = IOPSReleasePowerSource(source)
        guard result == kIOReturnSuccess else { throw BridgeError.powerSource(result) }
        self.source = nil
    }

    func publish(_ reading: BatteryReading?) throws {
        let details: [String: Any] = [
            "Name": device.name,
            "Type": "Accessory Source",
            "Power Source State": "Battery Power",
            "Transport Type": "USB",
            "Accessory Category": device.category,
            "Accessory Identifier": device.identifier,
            "Vendor ID": device.vendorID,
            "Product ID": device.accessoryProductID,
            "Is Charging": reading?.isCharging ?? false,
            "Is Present": reading != nil,
            "Current Capacity": reading?.percent ?? 0,
            "Max Capacity": 100
        ]
        guard let source else { throw BridgeError.powerSource(kIOReturnNoDevice) }
        let result = IOPSSetPowerSourceDetails(source, details as CFDictionary)
        guard result == kIOReturnSuccess else { throw BridgeError.powerSource(result) }
    }
}
