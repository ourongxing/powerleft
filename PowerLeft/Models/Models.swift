import Foundation
import IOKit

let appName = "PowerLeft"

func localized(_ key: String, _ arguments: CVarArg...) -> String {
    String(
        format: NSLocalizedString(key, comment: ""),
        locale: Locale.current,
        arguments: arguments
    )
}

struct DeviceDescriptor: Equatable {
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
            return localized("No %@ 2.4 GHz receiver found", name)
        case .open(let result):
            return localized("Failed to open HID receiver: %@", Self.hex(result))
        case .send(let result):
            return localized("Failed to send query: %@", Self.hex(result))
        case .noResponse(let detail):
            return detail
        case .invalidResponse(let detail):
            return localized("Invalid battery report: %@", detail)
        case .powerSource(let result):
            return localized("Failed to publish system power source: %@", Self.hex(result))
        }
    }

    private static func hex(_ result: IOReturn) -> String {
        "0x\(String(UInt32(bitPattern: result), radix: 16, uppercase: true))"
    }
}
