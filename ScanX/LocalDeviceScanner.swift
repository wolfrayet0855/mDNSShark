import Foundation
import Network
import os

class LocalDeviceScanner: ObservableObject {
    @Published var discoveredIPs: [String] = []
    private let logger = Logger(subsystem: "com.example.ScanX", category: "LocalDeviceScanner")
    
    /// Scans the local subnet (assumed /24) by trying to open a TCP connection on the specified port.
    /// - Parameters:
    ///   - port: The port to probe (default is 80).
    ///   - timeout: How long (in seconds) to wait for each connection.
    func scanLocalSubnet(port: NWEndpoint.Port = 80, timeout: TimeInterval = 1.0) {
        guard let localPrefix = getLocalIPPrefix() else {
            logger.error("Failed to get local IP prefix.")
            return
        }
        // For a /24 subnet, iterate from .1 to .254.
        let group = DispatchGroup()
        var results = [String]()
        for i in 1...254 {
            let ipAddress = "\(localPrefix)\(i)"
            group.enter()
            let connection = NWConnection(host: NWEndpoint.Host(ipAddress), port: port, using: .tcp)
            
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    self.logger.debug("Connection ready to \(ipAddress)")
                    results.append(ipAddress)
                    connection.cancel()
                    group.leave()
                case .failed(_):
                    connection.cancel()
                    group.leave()
                case .waiting(_):
                    // Wait until timeout occurs.
                    break
                default:
                    break
                }
            }
            connection.start(queue: .global())
            // Cancel the connection if it doesn't succeed within the timeout.
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                connection.cancel()
            }
        }
        
        group.notify(queue: DispatchQueue.main) {
            self.discoveredIPs = results
            self.logger.info("Local subnet scan complete: \(results)")
        }
    }
}

// Helper function to extract the local IP prefix.
// (This assumes you already have getWiFiAddress() and getLocalIPPrefix(for:) defined.)
func getLocalIPPrefix() -> String? {
    guard let wifiAddress = getWiFiAddress() else { return nil }
    return getLocalIPPrefix(for: wifiAddress)
}
