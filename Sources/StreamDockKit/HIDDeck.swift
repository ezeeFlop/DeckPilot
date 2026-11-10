import Foundation
import IOKit
import IOKit.hid

/// Liaison USB HID avec le boîtier : détection du branchement, envois en file, lecture des appuis.
///
/// `start()` doit être appelé depuis le fil principal ; les rappels y sont aussi délivrés.
public final class HIDDeck {
    public static let vendorID = 0x6603
    public static let productID = 0x1014
    public static let usagePage = 0xFFA0

    public var onConnect: (() -> Void)?
    public var onDisconnect: (() -> Void)?
    public var onInput: ((DeckInput) -> Void)?
    /// Appelé quand un envoi échoue, avec le code IOKit.
    public var onSendError: ((IOReturn) -> Void)?

    public private(set) var serialNumber: String?
    public var isConnected: Bool { lock.withLock { device != nil } }

    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private let lock = NSLock()
    private let writeQueue = DispatchQueue(label: "deck.hid.write", qos: .userInitiated)
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: DeckReports.inputSize)
    private var heartbeat: Timer?
    private var queued = 0

    /// Vrai tant que des envois attendent ; sert à ne pas empiler des images plus vite que le boîtier ne les prend.
    public var isBusy: Bool { lock.withLock { queued > 0 } }

    public init() {}

    deinit {
        stop()
        inputBuffer.deallocate()
    }

    public func start() {
        guard manager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [
            kIOHIDVendorIDKey: Self.vendorID,
            kIOHIDProductIDKey: Self.productID,
            kIOHIDPrimaryUsagePageKey: Self.usagePage,
        ]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            Unmanaged<HIDDeck>.fromOpaque(context!).takeUnretainedValue().attach(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            Unmanaged<HIDDeck>.fromOpaque(context!).takeUnretainedValue().detach(device)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
    }

    public func stop() {
        heartbeat?.invalidate()
        heartbeat = nil
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
        lock.withLock { device = nil }
    }

    // MARK: Envois

    public func send(_ command: DeckCommand) {
        enqueue(DeckReports.split(command.payload))
    }

    /// Envoie l'image d'une case. Elle n'apparaît qu'après un `send(.refresh)`.
    public func setImage(jpeg: [UInt8], slot: Int) {
        guard !jpeg.isEmpty, (1...255).contains(slot) else { return }
        enqueue(DeckReports.imageUpload(jpeg: jpeg, slot: UInt8(slot)))
    }

    /// Attend que tous les envois en file soient partis (pour la fermeture de l'application).
    public func drain() {
        writeQueue.sync {}
    }

    private func enqueue(_ reports: [[UInt8]]) {
        lock.withLock { queued += 1 }
        writeQueue.async { [weak self] in
            guard let self else { return }
            defer { self.lock.withLock { self.queued -= 1 } }
            guard let device = self.lock.withLock({ self.device }) else { return }
            for report in reports {
                let result = IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, report, report.count)
                if result != kIOReturnSuccess {
                    DispatchQueue.main.async {
                        self.onSendError?(result)
                        self.reopen(device)
                    }
                    return
                }
            }
        }
    }

    // MARK: Branchement

    private func attach(_ device: IOHIDDevice) {
        guard IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else { return }
        serialNumber = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(device, inputBuffer, DeckReports.inputSize, { context, _, _, _, _, report, length in
            let deck = Unmanaged<HIDDeck>.fromOpaque(context!).takeUnretainedValue()
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            if let input = DeckInput(report: bytes) { deck.onInput?(input) }
        }, context)
        lock.withLock { self.device = device }
        heartbeat?.invalidate()
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in self?.send(.heartbeat) }
        RunLoop.main.add(timer, forMode: .common)
        heartbeat = timer
        onConnect?()
    }

    /// Après un envoi refusé, la poignée est peut-être périmée : on la lâche et on reprend le boîtier s'il est toujours là.
    private func reopen(_ failed: IOHIDDevice) {
        guard lock.withLock({ device === failed }) else { return }
        detach(failed)
        IOHIDDeviceClose(failed, IOOptionBits(kIOHIDOptionsTypeNone))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, let manager = self.manager, !self.isConnected,
                  let present = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, let device = present.first
            else { return }
            self.attach(device)
        }
    }

    private func detach(_ removed: IOHIDDevice) {
        let wasCurrent = lock.withLock { () -> Bool in
            guard device === removed else { return false }
            device = nil
            return true
        }
        guard wasCurrent else { return }
        heartbeat?.invalidate()
        heartbeat = nil
        onDisconnect?()
    }
}
