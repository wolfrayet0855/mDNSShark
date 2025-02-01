import Foundation
import Network
import Combine

class NetworkScanner: NSObject, ObservableObject, NetServiceDelegate {
    @Published var devices: [Device] = []
    @Published var isScanning: Bool = false

    // Array of Bonjour service types to scan for.
    private let serviceTypes: [String] = ["_http._tcp", "_ipp._tcp", "_raop._tcp"]
    
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
                    break
                }
            }
        }
        if let txtData = sender.txtRecordData() {
            let txtDict = NetService.dictionary(fromTXTRecord: txtData)
            if let friendlyData = txtDict["fn"], let friendly = String(data: friendlyData, encoding: .utf8) {
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

