import Foundation
import Network
import SwiftPing
import Combine

class NetworkScanner: ObservableObject {
    @Published var devices: [Device] = []
    @Published var isScanning: Bool = false
    @Published var progress: Double = 0.0
    @Published var localIPAddress: String? = nil

    private let queue = DispatchQueue.global(qos: .background)
    
    // Total IPs to scan and counter for scanned IPs.
    private var totalIPs: Int = 0
    private var scannedIPs: Int = 0
    
    // NWBrowser for Bonjour-based scanning
    private var bonjourBrowser: NWBrowser? = nil

    struct Device: Identifiable {
        let id = UUID()
        let ipAddress: String
        let openPort: UInt16?
        let icmpResponded: Bool

        /// Heuristically determine the device type icon.
        /// - Parameter localIP: The IP address of the scanning device.
        /// - Returns: An SF Symbol name.
        func deviceTypeIcon(localIP: String?) -> String {
            if let local = localIP, self.ipAddress == local {
                return "iphone"
            } else if let port = openPort, [22, 80, 443, 8080].contains(port) {
                return "desktopcomputer"
            } else {
                return "questionmark.circle"
            }
        }
    }

    // List of common ports to check. Adjust as needed.
    private var commonPorts: [UInt16] { [22, 80, 443, 8080] }

    // MARK: - Public Start
    func scanNetwork() {
        // Clear any previous results.
        devices.removeAll()
        isScanning = true
        progress = 0.0
        scannedIPs = 0

        // Get and store the local device’s IP address.
        localIPAddress = getWiFiAddress()
        guard let localIP = localIPAddress,
              let prefix = getLocalIPPrefix(for: localIP)
        else {
            print("⚠️ [Scanner] Could not detect local IP prefix. Aborting scan.")
            isScanning = false
            return
        }
        
        print("🌐 [Scanner] Local IP: \(localIP)")
        print("🌐 [Scanner] Detected prefix: \(prefix) => scanning .1 through .255 (common ports + optional ICMP)")

        let allIPs = (1...255).map { "\(prefix)\($0)" }
        totalIPs = allIPs.count

        // Process addresses in chunks of 10 to avoid extreme concurrency.
        scanNextBatch(allIPs, batchSize: 10, startIndex: 0)
    }

    // MARK: - Batch Scanning
    private func scanNextBatch(_ ipList: [String], batchSize: Int, startIndex: Int) {
        // If no more IPs to process, we’re done.
        guard startIndex < ipList.count else {
            finishScanning()
            return
        }

        // Create the next sub‐array.
        let endIndex = min(startIndex + batchSize, ipList.count)
        let batch = ipList[startIndex..<endIndex]

        // A dispatch group for this batch.
        let batchGroup = DispatchGroup()

        // For each IP in this batch:
        for ip in batch {
            batchGroup.enter()
            scanOneHost(ip) {
                batchGroup.leave()
            }
        }

        // Once the entire batch is done, move on to the next batch.
        batchGroup.notify(queue: queue) {
            self.scanNextBatch(ipList, batchSize: batchSize, startIndex: endIndex)
        }
    }

    private func finishScanning() {
        DispatchQueue.main.async {
            self.isScanning = false
            print("✅ [Scanner] Finished scanning all IPs.")
            // If no devices were found using TCP/ICMP, try the alternative Bonjour scan.
            if self.devices.isEmpty {
                print("🔎 [Scanner] No devices found via TCP/ICMP; starting Bonjour scan as alternative...")
                self.scanNetworkAlternative()
                // Stop the Bonjour browser after 5 seconds (for testing purposes).
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    self.bonjourBrowser?.cancel()
                    self.bonjourBrowser = nil
                    print("🔎 [Scanner] Bonjour scan ended.")
                }
            }
        }
    }

    // MARK: - Single Host Scan
    /**
     For one IP address, we:
     - Check several TCP ports.
     - Run an ICMP ping.
     - Then, if either check indicates an active device, we add it to the devices list.
     */
    private func scanOneHost(_ ip: String, completion: @escaping () -> Void) {
        var foundOpenPort: UInt16? = nil
        let portGroup = DispatchGroup()

        // Check each port.
        for port in commonPorts {
            portGroup.enter()
            tcpProbeIPAddress(ip, port: port) { didConnect in
                if didConnect, foundOpenPort == nil {
                    foundOpenPort = port
                }
                portGroup.leave()
            }
        }

        // Once all port checks complete, perform the ICMP ping.
        portGroup.notify(queue: queue) {
            self.pingIPAddressICMP(ip) { didPing in
                DispatchQueue.main.async {
                    // If either check succeeds, add the device.
                    if foundOpenPort != nil || didPing {
                        let dev = Device(ipAddress: ip,
                                         openPort: foundOpenPort,
                                         icmpResponded: didPing)
                        self.devices.append(dev)
                        print("   → [Scan] \(ip): port=\(String(describing: foundOpenPort)), ping=\(didPing) => Active!")
                    } else {
                        print("   → [Scan] \(ip): no ports open, no ping => Inactive (not added)")
                    }
                    
                    // Update progress.
                    self.scannedIPs += 1
                    self.progress = Double(self.scannedIPs) / Double(self.totalIPs)
                    completion()
                }
            }
        }
    }

    // MARK: - TCP Probe
    private func tcpProbeIPAddress(_ ip: String, port: UInt16, completion: @escaping (Bool) -> Void) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            completion(false)
            return
        }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(ip), port: nwPort)
        let conn = NWConnection(to: endpoint, using: .tcp)

        // Ensure the completion handler is only called once.
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

    // MARK: - ICMP Ping
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
    
    // MARK: - Alternative Method: Bonjour Scan
    /**
     If no devices respond to TCP or ICMP, we can try to discover Bonjour-advertised services.
     In this example, we use a specific Bonjour service type.
     Adjust the service type (e.g. "_http._tcp") as needed if you expect specific services.
     */
    private func scanNetworkAlternative() {
        // Use a specific Bonjour service type.
        let bonjourDescriptor = NWBrowser.Descriptor.bonjour(type: "_http._tcp", domain: nil)
        // Use TCP parameters for browsing.
        let parameters = NWParameters.tcp
        bonjourBrowser = NWBrowser(for: bonjourDescriptor, using: parameters)
        
        bonjourBrowser?.stateUpdateHandler = { state in
            print("🔎 [Bonjour] Browser state: \(state)")
        }
        
        bonjourBrowser?.browseResultsChangedHandler = { results, changes in
            for result in results {
                switch result.endpoint {
                case .service(let name, let domain, let type, _):
                    DispatchQueue.main.async {
                        // Use the service name as a unique identifier.
                        if !self.devices.contains(where: { $0.ipAddress == name }) {
                            let dev = Device(ipAddress: name, openPort: nil, icmpResponded: false)
                            self.devices.append(dev)
                            print("🔎 [Bonjour] Discovered service: \(name) in domain: \(domain) of type: \(type)")
                        }
                    }
                default:
                    break
                }
            }
        }
        
        bonjourBrowser?.start(queue: queue)
    }
}

