import Foundation
import Network
import os
import Darwin

class LocalDeviceScanner: ObservableObject {
    @Published var discoveredIPs: [String] = []
    private let logger = Logger(subsystem: "com.example.mDNSShark", category: "LocalDeviceScanner")
    
    /// Heuristically determines the default gateway.
    /// Assumes the router is at x.x.x.1, where x.x.x. is the device's Wi‑Fi prefix.
    private func getDefaultGateway() -> String? {
        if let wifiAddress = getWiFiAddress(), let prefix = getLocalIPPrefix(for: wifiAddress) {
            return "\(prefix)1"
        }
        return nil
    }
    
    /// Scans the local /24 subnet by iterating over each IP and invoking a dedicated scan for each.
    func scanLocalSubnet(port: NWEndpoint.Port = NWEndpoint.Port(integerLiteral: 80), timeout: TimeInterval = 1.0) {
        guard let localPrefix = getLocalIPPrefix() else {
            logger.error("Failed to get local IP prefix.")
            return
        }
        // Use the heuristic to determine the default gateway.
        let defaultGatewayIP = getDefaultGateway()
        logger.info("Default gateway (heuristic) detected: \(defaultGatewayIP ?? "unknown")")
        logger.info("Starting local subnet scan on prefix \(localPrefix)")
        
        let group = DispatchGroup()
        var results = [String]()
        let tcpParameters: NWParameters = .tcp
        
        for i in 1...254 {
            let ip = "\(localPrefix)\(i)"
            // Skip the default gateway so it doesn't show as a discovered device.
            if let defaultGatewayIP = defaultGatewayIP, ip == defaultGatewayIP {
                logger.debug("Skipping default gateway IP: \(ip)")
                continue
            }
            
            group.enter()
            scanSingleIP(ip: ip, port: port, parameters: tcpParameters, timeout: timeout) { success in
                if success, !results.contains(ip) {
                    results.append(ip)
                    self.logger.info("Local scan discovered device at IP: \(ip)")
                }
                group.leave()
            }
        }
        
        group.notify(queue: DispatchQueue.main) { [weak self] in
            guard let self = self else { return }
            self.discoveredIPs = results
            self.logger.info("Local subnet scan complete. Discovered IPs: \(results)")
        }
    }
    
    /// Helper method that attempts a TCP connection to the given IP address.
    private func scanSingleIP(ip: String,
                              port: NWEndpoint.Port,
                              parameters: NWParameters,
                              timeout: TimeInterval,
                              completion: @escaping (Bool) -> Void) {
        let host = NWEndpoint.Host(ip)
        let connection = NWConnection(host: host, port: port, using: parameters)
        
        // Ensure the completion closure is only called once.
        let lock = NSLock()
        var didComplete = false
        func safeComplete(_ success: Bool) {
            lock.lock()
            defer { lock.unlock() }
            if !didComplete {
                didComplete = true
                completion(success)
            }
        }
        
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            self.logger.info("NWConnection for \(ip) state: \(String(describing: state))")
            switch state {
            case .ready:
                self.logger.debug("Connection ready to \(ip)")
                connection.cancel()
                safeComplete(true)
            case .failed(let error):
                self.logger.debug("Connection failed to \(ip): \(error.localizedDescription)")
                connection.cancel()
                safeComplete(false)
            default:
                break
            }
        }
        
        connection.start(queue: DispatchQueue.global())
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            connection.cancel()
            safeComplete(false)
        }
    }
    
    // MARK: - Helper Functions for IP Address Retrieval
    
    /// Retrieves the device's Wi‑Fi IP address.
    func getWiFiAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr {
            defer { freeifaddrs(ifaddr) }
            var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
            while let currentPtr = ptr {
                let interface = currentPtr.pointee
                let flags = Int32(interface.ifa_flags)
                if (flags & (IFF_UP | IFF_RUNNING | IFF_LOOPBACK)) == (IFF_UP | IFF_RUNNING),
                   interface.ifa_addr?.pointee.sa_family == UInt8(AF_INET) {
                    let name = String(cString: interface.ifa_name)
                    if name == "en0" { // Typical Wi‑Fi interface
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        if let addr = interface.ifa_addr {
                            getnameinfo(addr,
                                        socklen_t(addr.pointee.sa_len),
                                        &hostname,
                                        socklen_t(hostname.count),
                                        nil,
                                        0,
                                        NI_NUMERICHOST)
                            address = String(cString: hostname)
                            break
                        }
                    }
                }
                ptr = interface.ifa_next
            }
        }
        return address
    }
    
    /// Returns the local IP prefix (first three octets followed by a dot) based on the Wi‑Fi address.
    func getLocalIPPrefix() -> String? {
        if let wifiAddress = getWiFiAddress() {
            return getLocalIPPrefix(for: wifiAddress)
        }
        return nil
    }
    
    /// Given an IPv4 address string, returns the /24 prefix (e.g. "192.168.1.").
    func getLocalIPPrefix(for ip: String) -> String? {
        let parts = ip.split(separator: ".")
        if parts.count == 4 {
            return "\(parts[0]).\(parts[1]).\(parts[2])."
        }
        return nil
    }
}

