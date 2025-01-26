import Foundation
import Network
import SwiftPing
import Combine

class NetworkScanner: ObservableObject {
    @Published var devices: [Device] = []
    @Published var isScanning: Bool = false

    private let queue = DispatchQueue.global(qos: .background)

    struct Device: Identifiable {
        let id = UUID()
        let ipAddress: String
        let isActive: Bool
    }

    func scanNetwork() {
        // Clear any old results
        devices.removeAll()
        
        // Mark scanning as in-progress
        isScanning = true

        // Try to detect the local IP prefix
        guard let prefix = getLocalIPPrefix() else {
            print("❗️ Could not detect local IP prefix. Defaulting to 192.168.1.")
            scanNetworkWithPrefix("192.168.1.")
            return
        }

        print("🌐 Detected local prefix: \(prefix)")
        scanNetworkWithPrefix(prefix)
    }

    private func scanNetworkWithPrefix(_ prefix: String) {
        // Because we’re scanning 255 addresses, do it asynchronously:
        queue.async {
            // Loop from x.x.x.1 to x.x.x.255
            for i in 1...255 {
                let ipAddress = "\(prefix)\(i)"

                // SwiftPing approach (ICMP):
                self.pingIPAddressICMP(ipAddress) { isActive in
                    DispatchQueue.main.async {
                        // For debugging:
                        print("   → \(ipAddress) isActive = \(isActive)")

                        self.devices.append(Device(ipAddress: ipAddress, isActive: isActive))

                        // If we’ve reached the last address, toggle isScanning off.
                        // Alternatively, you could keep track of completion with a counter.
                        if i == 255 {
                            self.isScanning = false
                        }
                    }
                }
            }
        }
    }

    // MARK: - SwiftPing-based ICMP method
    private func pingIPAddressICMP(_ ipAddress: String, completion: @escaping (Bool) -> Void) {
        let config = PingConfiguration(
            pInterval: 1.0,
            withTimeout: 2.0,
            withPayloadSize: 64
        )

        // For debugging, show which IP is about to be pinged
        // (You will see this in the Xcode console.)
        // print("Pinging \(ipAddress)...")

        SwiftPing.pingOnce(host: ipAddress, configuration: config, queue: queue) { response in
            // If ‘response.error’ is nil, that typically means we got an echo reply.
            let isActive = (response.error == nil)
            completion(isActive)
        }
    }
}
