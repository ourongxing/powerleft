import AppKit
import Darwin

if CommandLine.arguments.contains("--once") {
    for driver in DriverRegistry.all {
        do {
            for reading in try driver.readBatteries() {
                print("\(reading.device.identifier)\t\(reading.device.name)\t\(reading.battery.percent)%\t\(reading.battery.isCharging ? "charging" : "battery")")
            }
        } catch BridgeError.noReceiver {
            continue
        } catch {
            fputs("\(driver.name): \(error)\n", stderr)
        }
    }
    exit(EXIT_SUCCESS)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
