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
    private let displayedDeviceDefaultsKey = "statusBarDeviceIdentifier"
    private let displaysBatteryDefaultsKey = "displaysBatteryInStatusBar"
    private var timer: Timer?
    private var metadataObserver: NSObjectProtocol?
    private var monitors: [String: DeviceMonitor] = [:]
    private var displayedDeviceIdentifier: String?
    private var displayedDeviceItem: NSMenuItem?
    private var displaysBatteryItem: NSMenuItem?
    private var launchItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        menu.delegate = self

        let displayedDevice = NSMenuItem(title: localized("Displayed Device"), action: nil, keyEquivalent: "")
        displayedDevice.submenu = NSMenu(title: localized("Displayed Device"))
        displayedDevice.isHidden = true
        menu.addItem(displayedDevice)
        displayedDeviceItem = displayedDevice

        let displaysBattery = NSMenuItem(
            title: localized("Show Battery Level in Menu Bar"),
            action: #selector(toggleBatteryInStatusBar),
            keyEquivalent: ""
        )
        displaysBattery.target = self
        displaysBattery.state = displaysBatteryInStatusBar ? .on : .off
        menu.addItem(displaysBattery)
        displaysBatteryItem = displaysBattery

        let deviceSeparator = NSMenuItem.separator()
        menu.addItem(deviceSeparator)

        let launch = NSMenuItem(title: localized("Launch at Login"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launch.target = self
        launch.state = launchAtLoginEnabled ? .on : .off
        menu.addItem(launch)
        launchItem = launch

        let quit = NSMenuItem(title: localized("Quit"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        updateStatusBarPresentation()

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
    func menuWillOpen(_ menu: NSMenu) {
        updateDisplayedDeviceMenu()
        displaysBatteryItem?.state = displaysBatteryInStatusBar ? .on : .off
        launchItem?.state = launchAtLoginEnabled ? .on : .off
    }

    @objc private func requestInputMonitoring() {
        guard !inputMonitoringGranted else { return }
        if IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) { return }

        let alert = NSAlert()
        alert.messageText = localized("Input Monitoring Permission Required")
        alert.informativeText = localized("Allow PowerLeft in System Settings under Privacy & Security → Input Monitoring.")
        alert.addButton(withTitle: localized("Open System Settings"))
        alert.addButton(withTitle: localized("Later"))
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
            throw BridgeError.invalidResponse(
                localized("%@ battery is %d%%", reading.device.name, reading.battery.percent)
            )
        }

        let monitor: DeviceMonitor
        if let existing = monitors[reading.device.identifier], existing.device == reading.device {
            monitor = existing
        } else {
            if let existing = monitors[reading.device.identifier] {
                markDisconnected(existing)
            }
            guard let menu = statusItem.menu, let displayedDeviceItem else { return }
            let item = NSMenuItem(title: statusTitle(for: reading.device, reading: nil), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.insertItem(item, at: menu.index(of: displayedDeviceItem))
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
        updateDeviceControls()
    }

    private func statusTitle(for device: DeviceDescriptor, reading: BatteryReading?) -> String {
        guard let reading else { return localized("%@: --", device.name) }
        return reading.isCharging
            ? localized("%@: %d%% (Charging)", device.name, reading.percent)
            : localized("%@: %d%%", device.name, reading.percent)
    }

    private func markDisconnected(_ monitor: DeviceMonitor) {
        do {
            try monitor.powerSource.remove()
        } catch {
            present(error)
        }
        statusItem.menu?.removeItem(monitor.statusItem)
        monitors.removeValue(forKey: monitor.device.identifier)
        updateDeviceControls()
    }

    private func updateDeviceControls() {
        updateDisplayedDeviceMenu()
        updateStatusBarPresentation()
    }

    private func updateDisplayedDeviceMenu() {
        guard let displayedDeviceItem, let submenu = displayedDeviceItem.submenu else { return }
        let available = availableMonitors
        displayedDeviceItem.isHidden = available.count < 2
        submenu.removeAllItems()

        let selectedIdentifier = displayedMonitor()?.device.identifier
        for monitor in available {
            let item = NSMenuItem(
                title: statusTitle(for: monitor.device, reading: monitor.lastReading),
                action: #selector(selectDisplayedDevice(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = monitor.device.identifier
            item.state = monitor.device.identifier == selectedIdentifier ? .on : .off
            submenu.addItem(item)
        }
    }

    private func updateStatusBarPresentation() {
        guard let button = statusItem.button else { return }
        guard displaysBatteryInStatusBar else {
            let image = NSImage(systemSymbolName: "battery.100percent", accessibilityDescription: appName)
            image?.isTemplate = true
            button.image = image
            button.title = ""
            button.toolTip = appName
            return
        }
        guard let monitor = displayedMonitor(), let reading = monitor.lastReading else {
            let image = NSImage(
                systemSymbolName: "battery.0percent",
                accessibilityDescription: localized("No Connected Device")
            )
            image?.isTemplate = true
            button.image = image
            button.title = ""
            button.toolTip = localized("%@: No Connected Device", appName)
            return
        }

        let symbolName = reading.isCharging ? "battery.100percent.bolt" : batterySymbol(for: reading.percent)
        let description = statusTitle(for: monitor.device, reading: reading)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        button.title = " \(reading.percent)%"
        button.toolTip = description
    }

    private var availableMonitors: [DeviceMonitor] {
        monitors.values
            .filter { $0.lastReading != nil && !$0.statusItem.isHidden }
            .sorted {
                let order = $0.device.name.localizedStandardCompare($1.device.name)
                return order == .orderedSame
                    ? $0.device.identifier < $1.device.identifier
                    : order == .orderedAscending
            }
    }

    private func displayedMonitor() -> DeviceMonitor? {
        let available = availableMonitors
        if let preferred = UserDefaults.standard.string(forKey: displayedDeviceDefaultsKey),
           let monitor = available.first(where: { $0.device.identifier == preferred }) {
            displayedDeviceIdentifier = preferred
            return monitor
        }
        if let displayedDeviceIdentifier,
           let monitor = available.first(where: { $0.device.identifier == displayedDeviceIdentifier }) {
            return monitor
        }
        displayedDeviceIdentifier = available.first?.device.identifier
        return available.first
    }

    private func batterySymbol(for percent: Int) -> String {
        switch percent {
        case ...10: return "battery.0percent"
        case ...35: return "battery.25percent"
        case ...60: return "battery.50percent"
        case ...85: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private var displaysBatteryInStatusBar: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: displaysBatteryDefaultsKey) != nil else { return true }
        return defaults.bool(forKey: displaysBatteryDefaultsKey)
    }

    @objc private func toggleBatteryInStatusBar() {
        UserDefaults.standard.set(!displaysBatteryInStatusBar, forKey: displaysBatteryDefaultsKey)
        displaysBatteryItem?.state = displaysBatteryInStatusBar ? .on : .off
        updateStatusBarPresentation()
    }

    @objc private func selectDisplayedDevice(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String,
              monitors[identifier]?.lastReading != nil else { return }
        UserDefaults.standard.set(identifier, forKey: displayedDeviceDefaultsKey)
        displayedDeviceIdentifier = identifier
        updateDisplayedDeviceMenu()
        updateStatusBarPresentation()
    }

    private func present(_ error: Error) {
        NSLog("\(appName): \(error)")
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
