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
        let openPort: UInt16?
        let icmpResponded: Bool

        var isActive: Bool {
            (openPort != nil || icmpResponded)
        }
    }

    // List of common ports to check. Adjust as needed:
    private let commonPorts: [UInt16] = [22, 80, 443, 8080]

    // MARK: - Public Start
    func scanNetwork() {
        devices.removeAll()
        isScanning = true
        print("🔵 [Scanner] Starting multi-port scan...")

        guard let prefix = getLocalIPPrefix() else {
            print("⚠️ [Scanner] Could not detect local IP prefix. Aborting scan.")
            isScanning = false
            return
        }

        print("🌐 [Scanner] Detected prefix: \(prefix) => scanning .1 through .255 (common ports + optional ICMP)")

        let allIPs = (1...255).map { "\(prefix)\($0)" }

        // Process addresses in chunks of 10 to avoid extreme concurrency.
        scanNextBatch(allIPs, batchSize: 10, startIndex: 0)
    }

    // MARK: - Batch Scanning
    private func scanNextBatch(_ ipList: [String], batchSize: Int, startIndex: Int) {
        // If no more IPs to process, we’re done
        guard startIndex < ipList.count else {
            finishScanning()
            return
        }

        // Create the next sub‐array
        let endIndex = min(startIndex + batchSize, ipList.count)
        let batch = ipList[startIndex..<endIndex]

        // A dispatch group for this batch
        let batchGroup = DispatchGroup()

        // For each IP in this batch:
        for ip in batch {
            // 1) Enter the batch group once
            batchGroup.enter()

            // 2) Scan the IP on the background queue
            scanOneHost(ip) {
                // 3) On completion, leave the batch group
                batchGroup.leave()
            }
        }

        // Once the entire batch is done, move on to the next batch
        batchGroup.notify(queue: queue) {
            self.scanNextBatch(ipList, batchSize: batchSize, startIndex: endIndex)
        }
    }

    private func finishScanning() {
        DispatchQueue.main.async {
            self.isScanning = false
            print("✅ [Scanner] Finished scanning all IPs.")
        }
    }

    // MARK: - Single Host
    /**
     For one IP, we:
     - open a small `portGroup` for the ports
     - do `tcpProbe` for each port, collecting the first open port if any
     - once ports are done, do an ICMP ping
     - then call the final completion
    */
    private func scanOneHost(_ ip: String, completion: @escaping () -> Void) {
        // Record the first open port found
        var foundOpenPort: UInt16? = nil

        // A group for the ports
        let portGroup = DispatchGroup()

        // Start port checks
        for port in commonPorts {
            portGroup.enter()
            tcpProbeIPAddress(ip, port: port) { didConnect in
                if didConnect, foundOpenPort == nil {
                    foundOpenPort = port
                }
                portGroup.leave()
            }
        }

        // Once all ports are tested, do an ICMP ping
        portGroup.notify(queue: queue) {
            self.pingIPAddressICMP(ip) { didPing in
                DispatchQueue.main.async {
                    // If either a port was open or ICMP replied, we add it to devices
                    if foundOpenPort != nil || didPing {
                        let dev = Device(ipAddress: ip,
                                         openPort: foundOpenPort,
                                         icmpResponded: didPing)
                        self.devices.append(dev)
                        print("   → [Scan] \(ip): port=\(String(describing: foundOpenPort)), ping=\(didPing) => Active!")
                    } else {
                        print("   → [Scan] \(ip): no ports open, no ping => Inactive (not added)")
                    }
                    // Signal back that we’re done scanning this IP
                    completion()
                }
            }
        }
    }

    // MARK: - TCP
    private func tcpProbeIPAddress(_ ip: String, port: UInt16, completion: @escaping (Bool) -> Void) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            completion(false)
            return
        }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(ip), port: nwPort)
        let conn = NWConnection(to: endpoint, using: .tcp)

        // Ensure completion is only called once.
        var didComplete = false
        let completeOnce: (Bool) -> Void = { success in
            if !didComplete {
                didComplete = true
                completion(success)
            }
        }

        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                conn.cancel()
                completeOnce(true)
            case .failed(_), .cancelled:
                conn.cancel()
                completeOnce(false)
            default:
                break
            }
        }

        conn.start(queue: queue)

        // Timeout after 1 second if not ready.
        queue.asyncAfter(deadline: .now() + 1.0) {
            if conn.state != .ready {
                conn.cancel()
                completeOnce(false)
            }
        }
    }

    // MARK: - ICMP
    private func pingIPAddressICMP(_ ip: String, completion: @escaping (Bool) -> Void) {
        let config = PingConfiguration(
            pInterval: 1.0,
            withTimeout: 2.0,
            withPayloadSize: 64
        )
        SwiftPing.pingOnce(host: ip, configuration: config, queue: queue) { response in
            let success = (response.error == nil)
            completion(success)
        }
    }
}

