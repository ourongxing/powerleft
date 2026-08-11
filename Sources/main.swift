import AppKit
import Darwin

if CommandLine.arguments.contains("--once") {
    for driver in DriverRegistry.all {
        do {
            let reading = try driver.readBattery()
            print("\(driver.device.identifier)\t\(reading.percent)%\t\(reading.isCharging ? "charging" : "battery")")
        } catch BridgeError.noReceiver {
            continue
        } catch {
            fputs("\(driver.device.identifier): \(error)\n", stderr)
        }
    }
    exit(EXIT_SUCCESS)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
