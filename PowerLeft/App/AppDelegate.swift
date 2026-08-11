import AppKit
import IOKit.hid
import ServiceManagement

private final class DeviceMonitor {
    let driverName: String
    let device: DeviceDescriptor
    let powerSource: PowerSource
    let statusItem: NSMenuItem
    var lastReading: BatteryReading?

    init(driverName: String, device: DeviceDescriptor, powerSource: PowerSource, statusItem: NSMenuItem) {
        self.driverName = driverName
        self.device = device
        self.powerSource = powerSource
        self.statusItem = statusItem
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let drivers = DriverRegistry.all
    private var timer: Timer?
    private var metadataObserver: NSObjectProtocol?
    private var monitors: [String: DeviceMonitor] = [:]
    private var deviceSeparatorItem: NSMenuItem?
    private var launchItem: NSMenuItem?
    private var permissionItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.delegate = self

        let deviceSeparator = NSMenuItem.separator()
        deviceSeparator.isHidden = true
        menu.addItem(deviceSeparator)
        deviceSeparatorItem = deviceSeparator

        let permission = NSMenuItem(title: permissionTitle, action: #selector(requestInputMonitoring), keyEquivalent: "")
        permission.target = self
        menu.addItem(permission)
        permissionItem = permission

        let launch = NSMenuItem(title: "开机启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launch.state = launchAtLoginEnabled ? .on : .off
        menu.addItem(launch)
        launchItem = launch

        let quit = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.image = NSImage(systemSymbolName: "battery.100percent", accessibilityDescription: appName)
        statusItem.button?.image?.isTemplate = true

        metadataObserver = NotificationCenter.default.addObserver(
            forName: KeychronProductCatalog.didUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateBattery()
        }

        DispatchQueue.main.async { [weak self] in self?.updateBattery() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.monitors.values.allSatisfy({ $0.lastReading == nil }) else { return }
            self.updateBattery()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.updateBattery() }
    }

    deinit {
        if let metadataObserver { NotificationCenter.default.removeObserver(metadataObserver) }
    }

    private var launchAtLoginEnabled: Bool { SMAppService.mainApp.status == .enabled }
    private var inputMonitoringGranted: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted }
    private var permissionTitle: String { inputMonitoringGranted ? "输入监控授权（已授权）" : "输入监控授权…" }

    func menuWillOpen(_ menu: NSMenu) {
        permissionItem?.title = permissionTitle
        permissionItem?.isEnabled = !inputMonitoringGranted
        launchItem?.state = launchAtLoginEnabled ? .on : .off
    }

    @objc private func requestInputMonitoring() {
        guard !inputMonitoringGranted else { return }
        if IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) { return }

        let alert = NSAlert()
        alert.messageText = "需要输入监控权限"
        alert.informativeText = "请在系统设置的“隐私与安全性 → 输入监控”中允许 PowerLeft。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后处理")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if launchAtLoginEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            launchItem?.state = launchAtLoginEnabled ? .on : .off
        } catch {
            present(error)
        }
    }

    private func updateBattery() {
        for driver in drivers {
            do {
                let readings = try driver.readBatteries()
                let connectedIdentifiers = Set(readings.map(\.device.identifier))
                let disconnected = monitors.values.filter {
                    $0.driverName == driver.name && !connectedIdentifiers.contains($0.device.identifier)
                }
                for monitor in disconnected {
                    markDisconnected(monitor)
                }
                for reading in readings {
                    try publish(reading, from: driver)
                }
            } catch BridgeError.noReceiver, BridgeError.noResponse {
                let disconnected = monitors.values.filter { $0.driverName == driver.name }
                for monitor in disconnected {
                    markDisconnected(monitor)
                }
            } catch {
                NSLog("\(appName) [\(driver.name)]: \(error)")
            }
        }
    }

    private func publish(_ reading: DeviceBatteryReading, from driver: any BatteryDriver) throws {
        guard (0...100).contains(reading.battery.percent) else {
            throw BridgeError.invalidResponse("\(reading.device.name) 电量为 \(reading.battery.percent)%")
        }

        let monitor: DeviceMonitor
        if let existing = monitors[reading.device.identifier], existing.device == reading.device {
            monitor = existing
        } else {
            if let existing = monitors[reading.device.identifier] {
                markDisconnected(existing)
            }
            guard let menu = statusItem.menu, let separator = deviceSeparatorItem else { return }
            let item = NSMenuItem(title: statusTitle(for: reading.device, reading: nil), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.insertItem(item, at: menu.index(of: separator))
            monitor = DeviceMonitor(
                driverName: driver.name,
                device: reading.device,
                powerSource: try PowerSource(device: reading.device),
                statusItem: item
            )
            monitors[reading.device.identifier] = monitor
        }

        monitor.lastReading = reading.battery
        try monitor.powerSource.publish(reading.battery)
        monitor.statusItem.title = statusTitle(for: monitor.device, reading: reading.battery)
        monitor.statusItem.isHidden = false
        updateDeviceSeparator()
    }

    private func statusTitle(for device: DeviceDescriptor, reading: BatteryReading?) -> String {
        guard let reading else { return "\(device.name)：--" }
        return "\(device.name)：\(reading.percent)%\(reading.isCharging ? "（充电中）" : "")"
    }

    private func markDisconnected(_ monitor: DeviceMonitor) {
        do {
            try monitor.powerSource.remove()
        } catch {
            present(error)
        }
        statusItem.menu?.removeItem(monitor.statusItem)
        monitors.removeValue(forKey: monitor.device.identifier)
        updateDeviceSeparator()
    }

    private func updateDeviceSeparator() {
        deviceSeparatorItem?.isHidden = monitors.values.allSatisfy(\.statusItem.isHidden)
    }

    private func present(_ error: Error) {
        NSLog("\(appName): \(error)")
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
