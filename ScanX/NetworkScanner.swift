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

    // MARK: - Public API
    func scanNetwork() {
        // Clear old results
        devices.removeAll()

        // Mark scanning as in-progress
        isScanning = true
        print("🔵 [Scanner] Starting scan...")

        // Attempt to detect local IP prefix
        guard let prefix = getLocalIPPrefix() else {
            print("⚠️ [Scanner] Could not detect local IP prefix. Fallback to 192.168.1.")
            scanNetworkWithPrefix("192.168.1.")
            return
        }

        print("🌐 [Scanner] Detected local prefix: \(prefix) — now scanning .1 through .255")
        scanNetworkWithPrefix(prefix)
    }

    // MARK: - Private
    private func scanNetworkWithPrefix(_ prefix: String) {
        queue.async {
            // We'll do a total of 255 pings
            for i in 1...255 {
                let ipAddress = "\(prefix)\(i)"
                
                // (1) Attempt a TCP connection to reliably trigger local network permission
                self.tcpProbeIPAddress(ipAddress) { tcpSuccess in
                    // (2) Then do ICMP ping
                    self.pingIPAddressICMP(ipAddress) { icmpSuccess in
                        DispatchQueue.main.async {
                            // Combine results: if either TCP or ICMP says "true," we call it active
                            let isActive = (tcpSuccess || icmpSuccess)
                            print("   → [Scan] \(ipAddress): TCP=\(tcpSuccess), ICMP=\(icmpSuccess) → Active=\(isActive)")

                            // Append to the device list
                            self.devices.append(Device(ipAddress: ipAddress, isActive: isActive))

                            // When the loop hits the last IP, set isScanning=false
                            if i == 255 {
                                self.isScanning = false
                                print("✅ [Scanner] Finished scanning all 255 IPs.")
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - (A) TCP Probe
    /**
     Quick attempt to connect to ip:80.
     This usually triggers the local network permission prompt if none has appeared yet.
    */
    private func tcpProbeIPAddress(_ ipAddress: String, completion: @escaping (Bool) -> Void) {
        guard let port = NWEndpoint.Port(rawValue: 80) else {
            completion(false)
            return
        }
        let host = NWEndpoint.Host(ipAddress)
        let endpoint = NWEndpoint.hostPort(host: host, port: port)
        let params = NWParameters.tcp
        let connection = NWConnection(to: endpoint, using: params)

        connection.stateUpdateHandler = { newState in
            switch newState {
            case .ready:
                // We connected, so let's mark it "active"
                connection.cancel()
                completion(true)

            case .failed(let error):
                // Could not connect
                connection.cancel()
                // For logging:
                // print("❌ TCP connect to \(ipAddress):80 failed with \(error)")
                completion(false)

            case .cancelled:
                completion(false)
                
            default:
                break
            }
        }

        // Start connection on background queue
        connection.start(queue: self.queue)

        // Timeout after 1s if not connected
        self.queue.asyncAfter(deadline: .now() + 1.0) {
            if connection.state != .ready {
                connection.cancel()
                completion(false)
            }
        }
    }

    // MARK: - (B) ICMP Ping
    private func pingIPAddressICMP(_ ipAddress: String, completion: @escaping (Bool) -> Void) {
        let config = PingConfiguration(pInterval: 1.0,
                                       withTimeout: 2.0,
                                       withPayloadSize: 64)

        SwiftPing.pingOnce(host: ipAddress, configuration: config, queue: self.queue) { response in
            // If `response.error` is nil, that typically means we got an echo reply
            let success = (response.error == nil)
            completion(success)
        }
    }
}

