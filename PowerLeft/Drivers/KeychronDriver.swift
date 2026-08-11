import Foundation
import IOKit.hid

struct KeychronDriver: BatteryDriver {
    let name = "Keychron"

    private let receiver = DeviceDescriptor(
        name: "Keychron",
        identifier: "Keychron-2.4G",
        category: "Keyboard",
        vendorID: 0x3434,
        receiverProductID: nil,
        accessoryProductID: 0
    )

    func readBatteries() throws -> [DeviceBatteryReading] {
        try HIDDeviceAccess.withManagementDevices(for: receiver) { device in
            try readBattery(from: device)
        }.compactMap { $0 }
    }

    private func readBattery(from receiver: IOHIDDevice) throws -> DeviceBatteryReading? {
        guard receiver.productName.localizedCaseInsensitiveContains("Keychron Link") else { return nil }

        var report = [UInt8](repeating: 0, count: 21)
        report[0] = 0x51
        var reportLength = report.count
        let result = report.withUnsafeMutableBytes { bytes in
            IOHIDDeviceGetReport(
                receiver,
                kIOHIDReportTypeFeature,
                0x51,
                bytes.bindMemory(to: UInt8.self).baseAddress!,
                &reportLength
            )
        }
        guard result == kIOReturnSuccess else { throw BridgeError.send(result) }
        guard reportLength > 12, report[0] == 0x51 else {
            throw BridgeError.invalidResponse("Keychron 0x51 Feature Report 长度或报告 ID 不正确")
        }

        let vendorID = Int(report[4]) << 8 | Int(report[5])
        let productID = Int(report[7]) << 8 | Int(report[6])
        guard report[2] == 1, vendorID != 0, productID != 0 else { return nil }
        guard vendorID == receiver.vendorID else {
            throw BridgeError.invalidResponse("Keychron 配对设备 VID 为 0x\(hex(vendorID))")
        }

        let percent = Int(report[11])
        guard (0...100).contains(percent) else {
            throw BridgeError.invalidResponse("Keychron 设备电量为 \(percent)%")
        }

        let locationID = HIDDeviceAccess.locationID(of: receiver)
        let category = category(for: productID)
        let descriptor = DeviceDescriptor(
            name: productName(for: productID, category: category),
            identifier: "Keychron-\(hex(productID))-\(String(locationID, radix: 16, uppercase: true))",
            category: category,
            vendorID: vendorID,
            receiverProductID: receiver.productID,
            accessoryProductID: productID
        )
        let battery = BatteryReading(percent: percent, isCharging: (report[12] & 0x03) != 0)
        return DeviceBatteryReading(device: descriptor, battery: battery)
    }

    private func category(for productID: Int) -> String {
        // Keychron mice use the D0xx product range; keyboards use their model PID.
        productID & 0xFF00 == 0xD000 ? "Mouse" : "Keyboard"
    }

    private func productName(for productID: Int, category: String) -> String {
        return "Keychron \(category) 0x\(hex(productID))"
    }

    private func hex(_ value: Int) -> String {
        String(value, radix: 16, uppercase: true).leftPadding(toLength: 4, withPad: "0")
    }
}

private extension String {
    func leftPadding(toLength: Int, withPad character: Character) -> String {
        String(repeating: String(character), count: max(0, toLength - count)) + self
    }
}

private extension IOHIDDevice {
    var productName: String {
        IOHIDDeviceGetProperty(self, kIOHIDProductKey as CFString) as? String ?? ""
    }

    var vendorID: Int {
        (IOHIDDeviceGetProperty(self, kIOHIDVendorIDKey as CFString) as? NSNumber)?.intValue ?? 0
    }

    var productID: Int {
        (IOHIDDeviceGetProperty(self, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0
    }
}
