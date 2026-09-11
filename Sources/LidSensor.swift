import Combine
import Foundation
import IOKit
import IOKit.hid

@MainActor
final class LidSensor: ObservableObject {
    @Published private(set) var angle: Double?
    @Published private(set) var error: String?
    var onAngle: ((Double) -> Void)?

    private var worker: LidSensorWorker?
    private var generation: UInt = 0

    func start() {
        guard worker == nil else { return }
        generation &+= 1
        let currentGeneration = generation
        error = nil
        angle = nil
        let newWorker = LidSensorWorker { [weak self] result in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == currentGeneration else { return }
                switch result {
                case .success(let value):
                    self.angle = value
                    self.error = nil
                    self.onAngle?(value)
                case .failure(let failure):
                    self.error = failure.message
                    self.angle = nil
                    self.worker = nil
                }
            }
        }
        worker = newWorker
        newWorker.start()
    }

    func stop() {
        generation &+= 1
        worker?.stop()
        worker = nil
        angle = nil
    }

    deinit {
        worker?.stop()
    }
}

private struct LidSensorFailure: Error {
    let message: String
}

// Device ownership and every HID operation stay on this serial queue.
private final class LidSensorWorker {
    private let queue = DispatchQueue(label: "app.foldglass.lid-sensor", qos: .userInteractive)
    private let deliver: (Result<Double, LidSensorFailure>) -> Void
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var timer: DispatchSourceTimer?
    private var report = [UInt8](repeating: 0, count: 8)
    private let options = IOOptionBits(kIOHIDOptionsTypeNone)

    init(deliver: @escaping (Result<Double, LidSensorFailure>) -> Void) {
        self.deliver = deliver
    }

    func start() {
        queue.async { [self] in open() }
    }

    func stop() {
        queue.async { [self] in close() }
    }

    private func open() {
        let newManager = IOHIDManagerCreate(kCFAllocatorDefault, options)
        manager = newManager
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: 0x05AC,
            kIOHIDProductIDKey: 0x8104,
            kIOHIDDeviceUsagePageKey: 0x20,
            kIOHIDDeviceUsageKey: 0x8A
        ]
        IOHIDManagerSetDeviceMatching(newManager, matching as CFDictionary)
        let managerStatus = IOHIDManagerOpen(newManager, options)
        guard managerStatus == kIOReturnSuccess else {
            fail("не удалось открыть HID", code: managerStatus)
            return
        }
        guard let devices = IOHIDManagerCopyDevices(newManager) as? Set<IOHIDDevice>,
              let foundDevice = devices.first else {
            fail("датчик угла крышки не найден")
            return
        }
        let deviceStatus = IOHIDDeviceOpen(foundDevice, options)
        guard deviceStatus == kIOReturnSuccess else {
            fail("не удалось открыть датчик крышки", code: deviceStatus)
            return
        }
        device = foundDevice
        let newTimer = DispatchSource.makeTimerSource(queue: queue)
        newTimer.schedule(deadline: .now(), repeating: 1.0 / 30.0, leeway: .milliseconds(2))
        newTimer.setEventHandler { [weak self] in self?.read() }
        timer = newTimer
        newTimer.resume()
    }

    private func read() {
        guard let device else { return }
        var length = report.count
        let status = IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, 1, &report, &length)
        guard status == kIOReturnSuccess else {
            fail("не удалось прочитать угол крышки", code: status)
            return
        }
        guard length == 3, report[0] == 1 else {
            fail("датчик крышки вернул неизвестный формат данных")
            return
        }
        let value = UInt16(report[1]) | (UInt16(report[2]) << 8)
        guard value <= 360 else {
            fail("датчик крышки вернул недопустимый угол: \(value)")
            return
        }
        deliver(.success(Double(value)))
    }

    private func fail(_ message: String, code: IOReturn? = nil) {
        let detail = code.map { String(format: " (IOKit 0x%08x)", $0) } ?? ""
        close()
        deliver(.failure(LidSensorFailure(message: message + detail)))
    }

    private func close() {
        timer?.cancel()
        timer = nil
        if let device {
            IOHIDDeviceClose(device, options)
            self.device = nil
        }
        if let manager {
            IOHIDManagerClose(manager, options)
            self.manager = nil
        }
    }
}
