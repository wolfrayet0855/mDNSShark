import Foundation
import Network
import os

class LocalDeviceScanner: ObservableObject {
    @Published var discoveredIPs: [String] = []
    private let logger = Logger(subsystem: "com.example.mDNSShark", category: "LocalDeviceScanner")
    
    func scanLocalSubnet(port: NWEndpoint.Port = NWEndpoint.Port(integerLiteral: 80), timeout: TimeInterval = 1.0) {
        guard let localPrefix = getLocalIPPrefix() else {
            logger.error("Failed to get local IP prefix.")
            return
        }
        logger.info("Starting local subnet scan on prefix \(localPrefix)")
        
        let group = DispatchGroup()
        var results = [String]()
        let tcpParameters: NWParameters = .tcp
        
        for i in 1...254 {
            let ip = "\(localPrefix)\(i)"
            group.enter()
            scanSingleIP(ip: ip, port: port, parameters: tcpParameters, timeout: timeout) { success in
                if success {
                    results.append(ip)
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
    
    private func scanSingleIP(ip: String,
                              port: NWEndpoint.Port,
                              parameters: NWParameters,
                              timeout: TimeInterval,
                              completion: @escaping (Bool) -> Void) {
        let host = NWEndpoint.Host(ip)
        let connection = NWConnection(host: host, port: port, using: parameters)
        
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            self.logger.info("NWConnection for \(ip) state: \(String(describing: state))")
            switch state {
            case .ready:
                self.logger.debug("Connection ready to \(ip)")
                connection.cancel()
                completion(true)
            case .failed(let error):
                self.logger.debug("Connection failed to \(ip): \(error.localizedDescription)")
                connection.cancel()
                completion(false)
            default:
                break
            }
        }
        
        connection.start(queue: DispatchQueue.global())
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            connection.cancel()
            completion(false)
        }
    }
    
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
                    if name == "en0" {
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
    
    func getLocalIPPrefix() -> String? {
        if let wifiAddress = getWiFiAddress() {
            return getLocalIPPrefix(for: wifiAddress)
        }
        return nil
    }
    
    func getLocalIPPrefix(for ip: String) -> String? {
        let parts = ip.split(separator: ".")
        if parts.count == 4 {
            return "\(parts[0]).\(parts[1]).\(parts[2])."
        }
        return nil
    }
}

