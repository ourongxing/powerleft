import Foundation
import IOKit.hid

struct JZM5Driver: BatteryDriver {
    let device = DeviceDescriptor(
        name: "京东京造 JZM5",
        identifier: "JZM5-2.4G",
        category: "Mouse",
        vendorID: 0x362D,
        receiverProductID: 0xD107,
        accessoryProductID: 0xD20F,
        supportsNearcast: true
    )

    func readBattery() throws -> BatteryReading {
        try HIDDeviceAccess.withManagementDevice(for: device) { receiver in
            let state = JZM5QueryState()
            let retained = Unmanaged.passRetained(state)
            defer { retained.release() }

            IOHIDDeviceRegisterInputReportCallback(
                receiver,
                state.buffer,
                state.bufferCapacity,
                jzm5InputCallback,
                retained.toOpaque()
            )
            IOHIDDeviceScheduleWithRunLoop(receiver, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            defer {
                IOHIDDeviceUnscheduleFromRunLoop(receiver, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            }

            var request = [UInt8](repeating: 0, count: 64)
            request[0] = 0xB3
            request[1] = 0x06
            let result = request.withUnsafeBytes {
                IOHIDDeviceSetReport(
                    receiver,
                    kIOHIDReportTypeOutput,
                    0xB3,
                    $0.bindMemory(to: UInt8.self).baseAddress!,
                    request.count
                )
            }
            guard result == kIOReturnSuccess else { throw BridgeError.send(result) }

            let deadline = Date().addingTimeInterval(3)
            while state.reading == nil && Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
            guard let reading = state.reading else {
                throw BridgeError.noResponse("3 秒内未收到 JZM5 B4/06 电量回包")
            }
            return reading
        }
    }
}

private final class JZM5QueryState {
    let bufferCapacity = 256
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 256)
    var reading: BatteryReading?

    init() { buffer.initialize(repeating: 0, count: bufferCapacity) }
    deinit {
        buffer.deinitialize(count: bufferCapacity)
        buffer.deallocate()
    }
}

private let jzm5InputCallback: IOHIDReportCallback = { context, _, _, _, reportID, report, length in
    guard let context, reportID == 0xB4 else { return }
    let state = Unmanaged<JZM5QueryState>.fromOpaque(context).takeUnretainedValue()
    var bytes = Array(UnsafeBufferPointer(start: report, count: length))
    if bytes.first == 0xB4 { bytes.removeFirst() }
    guard bytes.count > 19, bytes[0] == 0x06 else { return }
    state.reading = BatteryReading(
        percent: Int(bytes[19] & 0x7F),
        isCharging: (bytes[19] & 0x80) != 0
    )
}
