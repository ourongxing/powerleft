import AppIntents
import Foundation

struct DeviceBatteryEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "设备电量")
    static let defaultQuery = DeviceBatteryEntityQuery()

    var id: String { identifier }

    @Property(title: "设备标识符")
    var identifier: String

    @Property(title: "设备名称")
    var name: String

    @Property(title: "设备类型")
    var category: String

    @Property(title: "电量")
    var percent: Int

    @Property(title: "正在充电")
    var isCharging: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(percent)% · \(isCharging ? "充电中" : "使用电池")"
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
    static let title: LocalizedStringResource = "获取设备电量"
    static let description = IntentDescription("获取 PowerLeft 当前检测到的已连接设备及其实时电量和充电状态。")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<[DeviceBatteryEntity]> & ProvidesDialog {
        let devices = DeviceBatteryIntentReader.read()
        let dialog: IntentDialog = devices.isEmpty
            ? "没有检测到已连接的设备。"
            : "已获取 \(devices.count) 个设备的电量。"
        return .result(value: devices, dialog: dialog)
    }
}

struct PowerLeftShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetDeviceBatteriesIntent(),
            phrases: [
                "使用 \(.applicationName) 获取设备电量",
                "在 \(.applicationName) 中获取设备电量"
            ],
            shortTitle: "获取设备电量",
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
