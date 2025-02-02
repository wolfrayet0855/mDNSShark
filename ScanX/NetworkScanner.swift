import Foundation
import Network
import Combine
import CoreFoundation

class NetworkScanner: NSObject, ObservableObject, NetServiceDelegate {
    @Published var devices: [Device] = []
    @Published var isScanning: Bool = false

    // Updated list of service types.
    private let serviceTypes: [String] = [
        "_http._tcp",
        "_ipp._tcp",
        "_raop._tcp",
        "_daap._tcp",
        "_airdrop._tcp",
        "_bluetoothd2._tcp"
    ]
    
    // Array to hold NWBrowser instances for each service type.
    private var bonjourBrowsers: [NWBrowser] = []
    
    // Mapping from each NetService (using ObjectIdentifier) to the corresponding Device id.
    private var serviceToDeviceId: [ObjectIdentifier: UUID] = [:]
    
    // Device is an ObservableObject so that changes update the UI.
    class Device: ObservableObject, Identifiable {
        let id = UUID()
        let serviceName: String
        let serviceDomain: String
        let serviceType: String
        
        @Published var resolvedIPAddress: String? = nil
        @Published var friendlyName: String? = nil
        @Published var model: String? = nil
        @Published var port: Int? = nil
        @Published var txtRecords: [String: String]? = nil
        
        // Use friendlyName if available; otherwise show the serviceName.
        var identifier: String {
            return friendlyName ?? serviceName
        }
        
        init(serviceName: String, serviceDomain: String, serviceType: String) {
            self.serviceName = serviceName
            self.serviceDomain = serviceDomain
            self.serviceType = serviceType
        }
        
        func deviceTypeIcon() -> String {
            let lowerIdentifier = identifier.lowercased()
            if lowerIdentifier.contains("epson") || lowerIdentifier.contains("printer") {
                return "printer.fill"
            } else if lowerIdentifier.contains("rsled") || lowerIdentifier.contains("rsato") {
                return "lightbulb.fill"
            } else if lowerIdentifier.contains("mac") || lowerIdentifier.contains("dell") ||
                        lowerIdentifier.contains("pc") || lowerIdentifier.contains("computer") {
                return "desktopcomputer"
            } else {
                return "questionmark.circle"
            }
        }
    }
    
    /// Starts scanning by clearing previous results and launching a browser for each service type.
    func scanNetwork() {
        // Cancel any active browsers.
        for browser in bonjourBrowsers {
            browser.cancel()
        }
        bonjourBrowsers.removeAll()
        devices.removeAll()
        isScanning = true
        serviceToDeviceId.removeAll()
        
        // Start an NWBrowser for each service type.
        for type in serviceTypes {
            createAndStartBrowser(for: type)
        }
        
        // Allow more time for resolution (15 seconds for testing).
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            for browser in self.bonjourBrowsers {
                browser.cancel()
            }
            self.bonjourBrowsers.removeAll()
            self.isScanning = false
            print("🔎 [Bonjour] Scan ended.")
        }
    }
    
    /// Creates and starts an NWBrowser for a given service type.
    private func createAndStartBrowser(for serviceType: String) {
        let descriptor = NWBrowser.Descriptor.bonjour(type: serviceType, domain: nil)
        let parameters = NWParameters.tcp
        let browser = NWBrowser(for: descriptor, using: parameters)
        
        browser.stateUpdateHandler = { state in
            print("🔎 [Bonjour] Browser state for \(serviceType): \(state)")
            if case .failed(let error) = state {
                print("🔎 [Bonjour] Browser for \(serviceType) failed with error: \(error)")
                DispatchQueue.main.async {
                    self.isScanning = false
                }
            }
        }
        
        browser.browseResultsChangedHandler = { results, _ in
            for result in results {
                switch result.endpoint {
                case .service(let name, let type, let domain, _):
                    DispatchQueue.main.async {
                        // Avoid duplicates.
                        if !self.devices.contains(where: { $0.serviceName == name &&
                            $0.serviceDomain == domain && $0.serviceType == type }) {
                            let device = Device(serviceName: name, serviceDomain: domain, serviceType: type)
                            self.devices.append(device)
                            print("🔎 [Bonjour] Discovered service: \(name) in domain: \(domain) of type: \(type)")
                            self.resolveService(name: name, type: type, domain: domain)
                        }
                    }
                default:
                    break
                }
            }
        }
        
        browser.start(queue: DispatchQueue.global(qos: .background))
        bonjourBrowsers.append(browser)
    }
    
    /// Resolves a service using NetService to obtain its IP address, port, and TXT record info.
    private func resolveService(name: String, type: String, domain: String) {
        let netService = NetService(domain: domain, type: type, name: name)
        netService.delegate = self
        // Schedule on the main run loop so that delegate callbacks occur.
        netService.schedule(in: RunLoop.main, forMode: .common)
        if let device = self.devices.first(where: { $0.serviceName == name &&
                                                     $0.serviceDomain == domain &&
                                                     $0.serviceType == type }) {
            serviceToDeviceId[ObjectIdentifier(netService)] = device.id
        }
        print("🔎 [Bonjour] Resolving service: \(name) \(type) \(domain)")
        // Increase timeout to 10 seconds.
        netService.resolve(withTimeout: 10.0)
    }
    
    // MARK: - NetServiceDelegate Methods
    
    func netServiceDidResolveAddress(_ sender: NetService) {
        let key = ObjectIdentifier(sender)
        guard let deviceID = serviceToDeviceId[key] else {
            print("🔎 [Bonjour] No device mapping for resolved service \(sender)")
            return
        }
        guard let device = self.devices.first(where: { $0.id == deviceID }) else { return }
        
        var foundIP: String? = nil
        if let addresses = sender.addresses, !addresses.isEmpty {
            print("🔎 [Bonjour] \(sender.name) has \(addresses.count) address(es)")
            for addressData in addresses {
                if let ip = ipAddressFromData(addressData) {
                    foundIP = ip
                    print("🔎 [Bonjour] Found IP \(ip) for service \(sender.name)")
                    break
                }
            }
            if foundIP == nil {
                print("🔎 [Bonjour] No valid IP could be parsed from addresses for \(sender.name)")
            }
        } else {
            print("🔎 [Bonjour] No addresses available for \(sender.name)")
        }
        // Fallback: if no IP was found, try hostname resolution.
        if foundIP == nil {
            let hostname = "\(sender.name).\(sender.domain)"
            print("🔎 [Bonjour] Attempting fallback resolution using hostname: \(hostname)")
            foundIP = resolveHostname(hostname)
            if let ip = foundIP {
                print("🔎 [Bonjour] Fallback resolved \(hostname) to IP: \(ip)")
            } else {
                print("🔎 [Bonjour] Fallback resolution failed for hostname: \(hostname)")
            }
        }
        if let ip = foundIP {
            DispatchQueue.main.async {
                device.resolvedIPAddress = ip
                device.port = sender.port
                print("🔎 [Bonjour] Service \(sender.name) resolved to IP: \(ip) on port: \(sender.port)")
            }
            // For HTTP services, try to fetch additional info.
            if device.serviceType == "_http._tcp" {
                attemptFetchDeviceInfo(for: device)
            }
        } else {
            print("🔎 [Bonjour] Could not determine IP for service \(sender.name)")
        }
        
        if let txtData = sender.txtRecordData() {
            let txtDict = NetService.dictionary(fromTXTRecord: txtData)
            if txtDict.isEmpty {
                print("🔎 [Bonjour] TXT record data empty for \(sender.name)")
            } else {
                var allTXTRecords: [String: String] = [:]
                for (key, value) in txtDict {
                    if let stringValue = String(data: value, encoding: .utf8) {
                        allTXTRecords[key] = stringValue
                    }
                }
                DispatchQueue.main.async {
                    device.txtRecords = allTXTRecords
                    print("🔎 [Bonjour] TXT records for \(sender.name): \(allTXTRecords)")
                }
                // Set friendly name and model if available.
                if let friendlyData = txtDict["fn"] ?? txtDict["n"],
                   let friendly = String(data: friendlyData, encoding: .utf8),
                   !friendly.isEmpty {
                    DispatchQueue.main.async {
                        device.friendlyName = friendly
                        print("🔎 [Bonjour] Resolved friendly name for \(sender.name): \(friendly)")
                    }
                } else {
                    print("🔎 [Bonjour] No friendly name found in TXT records for \(sender.name)")
                }
                if let modelData = txtDict["md"],
                   let model = String(data: modelData, encoding: .utf8),
                   !model.isEmpty {
                    DispatchQueue.main.async {
                        device.model = model
                        print("🔎 [Bonjour] Resolved model for \(sender.name): \(model)")
                    }
                } else {
                    print("🔎 [Bonjour] No model info found in TXT records for \(sender.name)")
                }
            }
        } else {
            print("🔎 [Bonjour] No TXT record data available for \(sender.name)")
        }
    }
    
    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        print("🔎 [Bonjour] Failed to resolve \(sender.name) with error: \(errorDict)")
    }
    
    // MARK: - Additional Info Fetching for HTTP Services
    
    /// Attempts to fetch additional device info via an HTTP GET.
    private func attemptFetchDeviceInfo(for device: Device) {
        guard let ip = device.resolvedIPAddress, let port = device.port else {
            print("🔎 [HTTP] Missing IP or port for \(device.serviceName). Skipping HTTP fetch.")
            return
        }
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            print("🔎 [HTTP] Invalid port value \(port) for \(device.serviceName)")
            return
        }
        
        let connection = NWConnection(host: NWEndpoint.Host(ip), port: nwPort, using: .tcp)
        connection.stateUpdateHandler = { state in
            print("🔎 [HTTP] Connection state for \(device.serviceName): \(state)")
            if case .ready = state {
                if device.serviceType == "_http._tcp" {
                    let request = "GET / HTTP/1.1\r\nHost: \(ip)\r\nConnection: close\r\n\r\n"
                    connection.send(content: request.data(using: .utf8), completion: .contentProcessed({ error in
                        if let error = error {
                            print("🔎 [HTTP] Error sending request for \(device.serviceName): \(error)")
                            connection.cancel()
                        } else {
                            self.receiveData(from: connection, for: device)
                        }
                    }))
                } else {
                    connection.cancel()
                }
            }
        }
        connection.start(queue: DispatchQueue.global())
    }
    
    private func receiveData(from connection: NWConnection, for device: Device) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, error in
            if let error = error {
                print("🔎 [HTTP] Error receiving data for \(device.serviceName): \(error)")
            } else if let data = data, let response = String(data: data, encoding: .utf8) {
                print("🔎 [HTTP] Received data for \(device.serviceName)")
                if let titleStart = response.range(of: "<title>") {
                    let titleSub = response[titleStart.upperBound...]
                    if let titleEnd = titleSub.range(of: "</title>") {
                        let title = String(titleSub[..<titleEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                        DispatchQueue.main.async {
                            if device.friendlyName == nil || device.friendlyName?.isEmpty == true {
                                device.friendlyName = title
                                print("🔎 [HTTP] Fetched friendly name from title for \(device.serviceName): \(title)")
                            }
                        }
                    } else {
                        print("🔎 [HTTP] Title end tag not found for \(device.serviceName)")
                    }
                } else {
                    print("🔎 [HTTP] <title> tag not found in response for \(device.serviceName)")
                }
            } else {
                print("🔎 [HTTP] No data received for \(device.serviceName)")
            }
            connection.cancel()
        }
    }
    
    // MARK: - Helper Functions
    
    /// Converts a sockaddr Data object to an IP address string.
    private func ipAddressFromData(_ data: Data) -> String? {
        var storage = sockaddr_storage()
        (data as NSData).getBytes(&storage, length: MemoryLayout<sockaddr_storage>.size)
        
        if Int32(storage.ss_family) == AF_INET {
            let addr = withUnsafePointer(to: &storage) {
                $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            }
            if let ipCStr = inet_ntoa(addr) {
                return String(cString: ipCStr)
            }
        } else if Int32(storage.ss_family) == AF_INET6 {
            let addr = withUnsafePointer(to: &storage) {
                $0.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr }
            }
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            var addr6 = addr // mutable copy for inet_ntop
            inet_ntop(AF_INET6, &addr6, &buffer, socklen_t(INET6_ADDRSTRLEN))
            return String(cString: buffer)
        }
        return nil
    }
    
    /// Resolves a hostname to an IP address using getaddrinfo.
    private func resolveHostname(_ hostname: String) -> String? {
        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil)
        var infoPtr: UnsafeMutablePointer<addrinfo>?
        if getaddrinfo(hostname, nil, &hints, &infoPtr) != 0 {
            print("🔎 [Hostname] getaddrinfo failed for hostname: \(hostname)")
            return nil
        }
        guard let info = infoPtr else {
            print("🔎 [Hostname] getaddrinfo returned nil info for hostname: \(hostname)")
            return nil
        }
        var ip: String?
        if info.pointee.ai_family == AF_INET {
            let addr = info.pointee.ai_addr!.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            if let ipCStr = inet_ntoa(addr.sin_addr) {
                ip = String(cString: ipCStr)
            }
        } else if info.pointee.ai_family == AF_INET6 {
            let addr = info.pointee.ai_addr!.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            var addr6 = addr.sin6_addr
            inet_ntop(AF_INET6, &addr6, &buffer, socklen_t(INET6_ADDRSTRLEN))
            ip = String(cString: buffer)
        }
        freeaddrinfo(info)
        if ip == nil {
            print("🔎 [Hostname] Unable to resolve hostname \(hostname) to an IP")
        }
        return ip
    }
}

