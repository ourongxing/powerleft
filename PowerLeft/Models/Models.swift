import Foundation
import IOKit

let appName = "PowerLeft"

struct DeviceDescriptor {
    let name: String
    let identifier: String
    let category: String
    let vendorID: Int
    let receiverProductID: Int?
    let accessoryProductID: Int

    init(
        name: String,
        identifier: String,
        category: String,
        vendorID: Int,
        receiverProductID: Int?,
        accessoryProductID: Int
    ) {
        self.name = name
        self.identifier = identifier
        self.category = category
        self.vendorID = vendorID
        self.receiverProductID = receiverProductID
        self.accessoryProductID = accessoryProductID
    }
}

struct BatteryReading: Equatable {
    let percent: Int
    let isCharging: Bool
}

struct DeviceBatteryReading {
    let device: DeviceDescriptor
    let battery: BatteryReading
}

protocol BatteryDriver {
    var name: String { get }
    func readBatteries() throws -> [DeviceBatteryReading]
}

enum DriverRegistry {
    static let all: [any BatteryDriver] = [
        JZM5Driver(),
        KeychronDriver()
    ]
}

enum BridgeError: Error, CustomStringConvertible {
    case noReceiver(String)
    case open(IOReturn)
    case send(IOReturn)
    case noResponse(String)
    case invalidResponse(String)
    case powerSource(IOReturn)

    var description: String {
        switch self {
        case .noReceiver(let name):
            return "未找到 \(name) 2.4G 接收器"
        case .open(let result):
            return "打开 HID 接收器失败：\(Self.hex(result))"
        case .send(let result):
            return "发送查询失败：\(Self.hex(result))"
        case .noResponse(let detail):
            return detail
        case .invalidResponse(let detail):
            return "无效的电量回包：\(detail)"
        case .powerSource(let result):
            return "发布系统电源项失败：\(Self.hex(result))"
        }
    }

    private static func hex(_ result: IOReturn) -> String {
        "0x\(String(UInt32(bitPattern: result), radix: 16, uppercase: true))"
    }
}
