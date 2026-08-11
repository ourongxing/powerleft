import AppIntents
import Foundation

struct DeviceBatteryEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Device Battery")
    static let defaultQuery = DeviceBatteryEntityQuery()

    var id: String { identifier }

    @Property(title: "Device Identifier")
    var identifier: String

    @Property(title: "Device Name")
    var name: String

    @Property(title: "Device Type")
    var category: String

    @Property(title: "Battery Level")
    var percent: Int

    @Property(title: "Is Charging")
    var isCharging: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(percent)% · \(isCharging ? String(localized: "Charging") : String(localized: "On Battery"))"
        )
    }

    init(reading: DeviceBatteryReading) {
        identifier = reading.device.identifier
        name = reading.device.name
        category = reading.device.category
        percent = reading.battery.percent
        isCharging = reading.battery.isCharging
    }
}

struct DeviceBatteryEntityQuery: EntityQuery {
    func entities(for identifiers: [DeviceBatteryEntity.ID]) async throws -> [DeviceBatteryEntity] {
        let identifiers = Set(identifiers)
        return DeviceBatteryIntentReader.read().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [DeviceBatteryEntity] {
        DeviceBatteryIntentReader.read()
    }
}

struct GetDeviceBatteriesIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Device Batteries"
    static let description = IntentDescription(
        "Get the current battery level and charging state of devices connected to PowerLeft."
    )
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<[DeviceBatteryEntity]> & ProvidesDialog {
        let devices = DeviceBatteryIntentReader.read()
        let dialog: IntentDialog = devices.isEmpty
            ? "No connected devices were detected."
            : "Device battery data retrieved."
        return .result(value: devices, dialog: dialog)
    }
}

struct PowerLeftShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetDeviceBatteriesIntent(),
            phrases: [
                "Get device batteries with \(.applicationName)",
                "Use \(.applicationName) to get device batteries"
            ],
            shortTitle: "Get Device Batteries",
            systemImageName: "battery.100percent"
        )
    }
}

private enum DeviceBatteryIntentReader {
    static func read() -> [DeviceBatteryEntity] {
        var devices: [DeviceBatteryEntity] = []
        for driver in DriverRegistry.all {
            do {
                devices.append(contentsOf: try driver.readBatteries().map(DeviceBatteryEntity.init))
            } catch BridgeError.noReceiver, BridgeError.noResponse {
                continue
            } catch {
                NSLog("\(appName) Shortcuts [\(driver.name)]: \(error)")
            }
        }
        return devices.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }
}
