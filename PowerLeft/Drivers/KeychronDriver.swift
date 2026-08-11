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

        var request = [UInt8](repeating: 0, count: 21)
        request[0] = 0x51
        request[1] = 0x06
        let sendResult = request.withUnsafeBytes { bytes in
            IOHIDDeviceSetReport(
                receiver,
                kIOHIDReportTypeFeature,
                0x51,
                bytes.bindMemory(to: UInt8.self).baseAddress!,
                request.count
            )
        }
        guard sendResult == kIOReturnSuccess else { throw BridgeError.send(sendResult) }
        Thread.sleep(forTimeInterval: 0.2)

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
        let fallbackCategory = category(for: productID)
        let metadata = KeychronProductCatalog.shared.metadata(vendorID: vendorID, productID: productID)
        let category = metadata?.category ?? fallbackCategory
        let descriptor = DeviceDescriptor(
            name: metadata?.name ?? productName(for: productID, category: category),
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

struct KeychronProductMetadata: Codable {
    let name: String
    let category: String
}

final class KeychronProductCatalog {
    static let shared = KeychronProductCatalog()
    static let didUpdate = Notification.Name("KeychronProductCatalogDidUpdate")

    private let defaultsKey = "keychronProductMetadata"
    private let retryInterval: TimeInterval = 6 * 60 * 60
    private let lock = NSLock()
    private var cache: [String: KeychronProductMetadata]
    private var lastAttempt: [String: Date] = [:]
    private let session: URLSession

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let cached = try? JSONDecoder().decode([String: KeychronProductMetadata].self, from: data) {
            cache = cached
        } else {
            cache = [:]
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.timeoutIntervalForResource = 10
        session = URLSession(configuration: configuration)
    }

    func metadata(vendorID: Int, productID: Int) -> KeychronProductMetadata? {
        let key = Self.key(vendorID: vendorID, productID: productID)
        lock.lock()
        if let metadata = cache[key] {
            lock.unlock()
            return metadata
        }
        if let attempt = lastAttempt[key], Date().timeIntervalSince(attempt) < retryInterval {
            lock.unlock()
            return nil
        }
        lastAttempt[key] = Date()
        lock.unlock()

        fetch(vendorID: vendorID, productID: productID, key: key)
        return nil
    }

    private func fetch(vendorID: Int, productID: Int, key: String) {
        let vpid = vendorID << 16 | productID
        guard let url = URL(string: "https://launcher.keychron.com/vapi/v2/product/\(vpid)") else { return }
        session.dataTask(with: url) { [weak self] data, _, error in
            guard let self, error == nil, let data,
                  let response = try? JSONDecoder().decode(ProductResponse.self, from: data),
                  response.code == 200,
                  let product = response.data?.product,
                  let categoryType = response.data?.category.type,
                  Self.hex(product.vid) == vendorID,
                  Self.hex(product.pid) == productID else { return }

            let name = product.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, let category = Self.category(for: categoryType) else { return }
            let metadata = KeychronProductMetadata(name: name, category: category)

            self.lock.lock()
            self.cache[key] = metadata
            let encoded = try? JSONEncoder().encode(self.cache)
            self.lock.unlock()
            if let encoded { UserDefaults.standard.set(encoded, forKey: self.defaultsKey) }

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.didUpdate, object: nil)
            }
        }.resume()
    }

    private static func key(vendorID: Int, productID: Int) -> String {
        String(format: "%04X:%04X", vendorID, productID)
    }

    private static func hex(_ value: String) -> Int? {
        Int(value.replacingOccurrences(of: "0x", with: "", options: .caseInsensitive), radix: 16)
    }

    private static func category(for type: Int) -> String? {
        switch type {
        case 0: return "Keyboard"
        case 1, 3: return "Mouse"
        default: return nil
        }
    }
}

private struct ProductResponse: Decodable {
    let code: Int
    let data: ProductData?
}

private struct ProductData: Decodable {
    let product: Product
    let category: ProductCategory
}

private struct Product: Decodable {
    let name: String
    let pid: String
    let vid: String
}

private struct ProductCategory: Decodable {
    let type: Int
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
