import AppKit
import IOKit.hid
import ServiceManagement

private final class DeviceMonitor {
    let driver: any BatteryDriver
    let powerSource: PowerSource
    let statusItem: NSMenuItem
    var lastReading: BatteryReading?

    init(driver: any BatteryDriver, powerSource: PowerSource, statusItem: NSMenuItem) {
        self.driver = driver
        self.powerSource = powerSource
        self.statusItem = statusItem
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?
    private var monitors: [DeviceMonitor] = []
    private var deviceSeparatorItem: NSMenuItem?
    private var launchItem: NSMenuItem?
    private var permissionItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.delegate = self
        registerDrivers(in: menu)

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

        DispatchQueue.main.async { [weak self] in self?.updateBattery() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.monitors.allSatisfy({ $0.lastReading == nil }) else { return }
            self.updateBattery()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.updateBattery() }
    }

    private func registerDrivers(in menu: NSMenu) {
        for driver in DriverRegistry.all {
            do {
                let item = NSMenuItem(title: statusTitle(for: driver.device, reading: nil), action: nil, keyEquivalent: "")
                item.isEnabled = false
                item.isHidden = true
                menu.addItem(item)
                monitors.append(DeviceMonitor(
                    driver: driver,
                    powerSource: try PowerSource(device: driver.device),
                    statusItem: item
                ))
            } catch {
                NSLog("\(appName) [\(driver.device.name)]: \(error)")
            }
        }
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
        for monitor in monitors {
            do {
                let reading = try monitor.driver.readBattery()
                monitor.lastReading = reading
                try monitor.powerSource.publish(reading)
                monitor.statusItem.title = statusTitle(for: monitor.driver.device, reading: reading)
                monitor.statusItem.isHidden = false
                updateDeviceSeparator()
            } catch BridgeError.noReceiver {
                markDisconnected(monitor)
            } catch {
                NSLog("\(appName) [\(monitor.driver.device.name)]: \(error)")
            }
        }
    }

    private func statusTitle(for device: DeviceDescriptor, reading: BatteryReading?) -> String {
        guard let reading else { return "\(device.name)：--" }
        return "\(device.name)：\(reading.percent)%\(reading.isCharging ? "（充电中）" : "")"
    }

    private func markDisconnected(_ monitor: DeviceMonitor) {
        monitor.statusItem.isHidden = true
        monitor.lastReading = nil
        updateDeviceSeparator()
        do {
            try monitor.powerSource.publish(nil)
        } catch {
            present(error)
        }
    }

    private func updateDeviceSeparator() {
        deviceSeparatorItem?.isHidden = monitors.allSatisfy(\.statusItem.isHidden)
    }

    private func present(_ error: Error) {
        NSLog("\(appName): \(error)")
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
