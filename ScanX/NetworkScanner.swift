import Foundation
import Network
import Combine
import CoreFoundation

class NetworkScanner: NSObject, ObservableObject, NetServiceDelegate {
    @Published var devices: [Device] = []
    @Published var isScanning: Bool = false

    // Updated list: Added _daap._tcp for music sharing, _airdrop._tcp for Airdrop, and _bluetoothd2._tcp for Bluetooth-related services.
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
    
    // Device is now a class (ObservableObject) so that changes update the UI.
    class Device: ObservableObject, Identifiable {
        let id = UUID()
        let serviceName: String
        let serviceDomain: String
        let serviceType: String
        
        @Published var resolvedIPAddress: String? = nil
        @Published var friendlyName: String? = nil
        @Published var model: String? = nil
        
        // Use friendlyName if available, otherwise show the serviceName.
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
            } else if lowerIdentifier.contains("mac") || lowerIdentifier.contains("dell") || lowerIdentifier.contains("pc") || lowerIdentifier.contains("computer") {
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
        
        // Stop scanning after a fixed interval (e.g., 5 seconds for testing).
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
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
        
        browser.browseResultsChangedHandler = { results, changes in
            for result in results {
                switch result.endpoint {
                case .service(let name, let type, let domain, _):
                    DispatchQueue.main.async {
                        // Avoid adding duplicate devices.
                        if !self.devices.contains(where: { $0.serviceName == name && $0.serviceDomain == domain && $0.serviceType == type }) {
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
    
    /// Resolves a service using NetService to obtain its IP address and TXT record information.
    private func resolveService(name: String, type: String, domain: String) {
        let netService = NetService(domain: domain, type: type, name: name)
        netService.delegate = self
        if let device = self.devices.first(where: { $0.serviceName == name && $0.serviceDomain == domain && $0.serviceType == type }) {
            serviceToDeviceId[ObjectIdentifier(netService)] = device.id
        }
        netService.resolve(withTimeout: 5.0)
    }
    
    // MARK: - NetServiceDelegate Methods
    
    func netServiceDidResolveAddress(_ sender: NetService) {
        let key = ObjectIdentifier(sender)
        guard let deviceID = serviceToDeviceId[key] else {
            print("🔎 [Bonjour] No device mapping for resolved service \(sender)")
            return
        }
        if let addresses = sender.addresses {
            for addressData in addresses {
                if let ip = ipAddressFromData(addressData) {
                    DispatchQueue.main.async {
                        if let device = self.devices.first(where: { $0.id == deviceID }) {
                            device.resolvedIPAddress = ip
                            print("🔎 [Bonjour] Resolved \(sender.name) to IP: \(ip)")
                        }
                    }
                    // Perform reverse DNS lookup if TXT record did not yield a friendly name.
                    self.performReverseDNSLookup(for: ip) { reverseName in
                        if let reverseName = reverseName, !reverseName.isEmpty {
                            DispatchQueue.main.async {
                                if let device = self.devices.first(where: { $0.id == deviceID }) {
                                    if device.friendlyName == nil || device.friendlyName?.isEmpty == true {
                                        device.friendlyName = reverseName
                                        print("🔎 [Bonjour] Reverse DNS lookup resolved \(sender.name) to hostname: \(reverseName)")
                                    }
                                }
                            }
                        }
                    }
                    break
                }
            }
        }
        if let txtData = sender.txtRecordData() {
            let txtDict = NetService.dictionary(fromTXTRecord: txtData)
            // Try the "fn" key; if unavailable, fall back to "n"
            if let friendlyData = txtDict["fn"] ?? txtDict["n"],
               let friendly = String(data: friendlyData, encoding: .utf8),
               !friendly.isEmpty {
                DispatchQueue.main.async {
                    if let device = self.devices.first(where: { $0.id == deviceID }) {
                        device.friendlyName = friendly
                        print("🔎 [Bonjour] Resolved friendly name for \(sender.name): \(friendly)")
                    }
                }
            }
            if let modelData = txtDict["md"], let model = String(data: modelData, encoding: .utf8) {
                DispatchQueue.main.async {
                    if let device = self.devices.first(where: { $0.id == deviceID }) {
                        device.model = model
                        print("🔎 [Bonjour] Resolved model for \(sender.name): \(model)")
                    }
                }
            }
        }
    }
    
    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        print("🔎 [Bonjour] Failed to resolve \(sender.name) with error: \(errorDict)")
    }
    
    // MARK: - Reverse DNS Lookup
    
    /// Performs a reverse DNS lookup using CFHost on the given IP address.
    private func performReverseDNSLookup(for ip: String, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .background).async {
            // Prepare a sockaddr_in structure for the IPv4 address.
            var sin = sockaddr_in()
            sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            sin.sin_family = sa_family_t(AF_INET)
            let result = ip.withCString { cstring in
                inet_pton(AF_INET, cstring, &sin.sin_addr)
            }
            guard result == 1 else {
                completion(nil)
                return
            }
            
            // Create CFData from the sockaddr_in structure.
            let data = Data(bytes: &sin, count: Int(sin.sin_len))
            // CFHostCreateWithAddress returns a non-optional Unmanaged<CFHost>
            let unmanagedHost = CFHostCreateWithAddress(nil, data as CFData)
            let hostRef = unmanagedHost.takeRetainedValue()
            
            var resolved: DarwinBoolean = false
            if CFHostStartInfoResolution(hostRef, .names, nil) {
                if let namesUnmanaged = CFHostGetNames(hostRef, &resolved) {
                    let names = namesUnmanaged.takeUnretainedValue() as NSArray as? [String]
                    if let names = names, !names.isEmpty {
                        completion(names.first)
                        return
                    }
                }
            }
            completion(nil)
        }
    }
    
    // MARK: - Helper Function
    
    /// Converts a sockaddr Data object to an IP address string.
    private func ipAddressFromData(_ data: Data) -> String? {
        var storage = sockaddr_storage()
        (data as NSData).getBytes(&storage, length: MemoryLayout<sockaddr_storage>.size)
        
        if Int32(storage.ss_family) == AF_INET {
            let addr = withUnsafePointer(to: &storage) {
                $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                    $0.pointee.sin_addr
                }
            }
            if let ipCStr = inet_ntoa(addr) {
                return String(cString: ipCStr)
            }
        } else if Int32(storage.ss_family) == AF_INET6 {
            let addr = withUnsafePointer(to: &storage) {
                $0.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                    $0.pointee.sin6_addr
                }
            }
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            let ipString = withUnsafePointer(to: addr) { ptr in
                inet_ntop(AF_INET6, ptr, &buffer, socklen_t(INET6_ADDRSTRLEN))
            }
            if let ipString = ipString {
                return String(cString: ipString)
            }
        }
        return nil
    }
}

