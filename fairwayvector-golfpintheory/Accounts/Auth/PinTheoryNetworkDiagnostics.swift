import Foundation
import Network

/// Deliberate allowlist: never inspect requests, error userInfo strings, URLs,
/// addresses, SSIDs, endpoint details, headers, bodies or credentials.
nonisolated enum PinTheoryNetworkDiagnostics {
    static func describe(_ error: URLError, path: NWPath? = nil) -> String {
        let restriction: String
        switch error.networkUnavailableReason {
        case .cellular?: restriction = "cellular access restricted"
        case .expensive?: restriction = "expensive network restricted"
        case .constrained?: restriction = "constrained network restricted"
        case .ultraConstrained?: restriction = "ultra-constrained network restricted"
        case nil: restriction = "not supplied by iOS"
        @unknown default: restriction = "unrecognized restriction"
        }
        var lines = ["URL loading code: \(error.code.rawValue)", "Request restriction: \(restriction)"]
        guard let path else { return lines.joined(separator: "\n") }
        let status: String
        switch path.status {
        case .satisfied: status = "available"
        case .unsatisfied: status = "unavailable"
        case .requiresConnection: status = "connection required"
        @unknown default: status = "unknown"
        }
        lines.append("Observed device path: \(status)")
        if path.status == .unsatisfied {
            let reason: String
            switch path.unsatisfiedReason {
            case .notAvailable: reason = "no available path"
            case .cellularDenied: reason = "cellular denied"
            case .wifiDenied: reason = "Wi-Fi denied"
            case .localNetworkDenied: reason = "local network denied"
            case .vpnInactive: reason = "required VPN inactive"
            @unknown default: reason = "unknown"
            }
            lines.append("Path reason: \(reason)")
        }
        let interfaces: [(NWInterface.InterfaceType, String)] = [(.wifi, "Wi-Fi"), (.cellular, "cellular"), (.wiredEthernet, "wired")]
        let used = interfaces.filter { path.usesInterfaceType($0.0) }.map(\.1)
        lines.append("Path type: \(used.isEmpty ? "other/none" : used.joined(separator: ", "))")
        lines.append("Path cost: \(path.isExpensive ? "expensive" : "ordinary"); low-data: \(path.isConstrained ? "yes" : "no")")
        lines.append("Path observation is not a test of server reachability.")
        return lines.joined(separator: "\n")
    }
}