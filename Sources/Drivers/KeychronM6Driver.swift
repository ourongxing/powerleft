import IOKit.hid

struct KeychronM6Driver: BatteryDriver {
    let device = DeviceDescriptor(
        name: "Keychron M6",
        identifier: "Keychron-M6-2.4G",
        category: "Mouse",
        vendorID: 0x3434,
        receiverProductID: 0xD030,
        accessoryProductID: 0xD03F
    )

    func readBattery() throws -> BatteryReading {
        try HIDDeviceAccess.withManagementDevice(for: device) { receiver in
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

            let percent = Int(report[11])
            guard (0...100).contains(percent) else {
                throw BridgeError.invalidResponse("Keychron M6 电量为 \(percent)%")
            }
            return BatteryReading(percent: percent, isCharging: (report[12] & 0x03) != 0)
        }
    }
}
