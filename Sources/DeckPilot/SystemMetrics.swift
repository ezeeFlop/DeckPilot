import DeckCore
import Foundation
import IOKit.ps

/// Mesures du Mac, en pourcentage.
final class SystemMetrics {
    private var previousTicks: (busy: Double, total: Double)?
    private var lastCPU: (value: Double, at: Date)?

    func read(_ metric: SystemMetric) -> Double? {
        switch metric {
        case .cpu: return cpu()
        case .memory: return memory()
        case .disk: return disk()
        case .battery: return battery()
        }
    }

    /// Part du temps processeur occupée depuis la lecture précédente.
    /// Plusieurs cases peuvent la demander au même instant : la mesure est partagée pendant une seconde,
    /// sinon la seconde case mesurerait un intervalle nul.
    private func cpu() -> Double? {
        if let lastCPU, Date().timeIntervalSince(lastCPU.at) < 1 { return lastCPU.value }
        guard let value = measureCPU() else { return nil }
        lastCPU = (value, Date())
        return value
    }

    private func measureCPU() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = Double(info.cpu_ticks.0), system = Double(info.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2), nice = Double(info.cpu_ticks.3)
        let current = (busy: user + system + nice, total: user + system + nice + idle)
        defer { previousTicks = current }
        guard let previous = previousTicks, current.total > previous.total else { return 0 }
        return (current.busy - previous.busy) / (current.total - previous.total) * 100
    }

    /// Mémoire utilisée : pages actives, câblées et compressées, rapportées à la mémoire installée.
    private func memory() -> Double? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pages = Double(stats.active_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)
        return pages * Double(vm_kernel_page_size) / Double(ProcessInfo.processInfo.physicalMemory) * 100
    }

    /// Espace occupé sur le disque de démarrage.
    private func disk() -> Double? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity, total > 0,
              let available = values.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return (1 - Double(available) / Double(total)) * 100
    }

    /// Charge de la batterie ; `nil` sur un Mac qui n'en a pas.
    private func battery() -> Double? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  let current = info[kIOPSCurrentCapacityKey] as? Double,
                  let maximum = info[kIOPSMaxCapacityKey] as? Double, maximum > 0
            else { continue }
            return current / maximum * 100
        }
        return nil
    }
}
