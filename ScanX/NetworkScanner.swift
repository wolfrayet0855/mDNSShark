import SwiftUI
import Network
import Combine
import CoreFoundation
import os

class NetworkScanner: NSObject, ObservableObject, NetServiceDelegate {
    @Published var devices: [Device] = []
    @Published var isScanning: Bool = false
    
    private let serviceTypes: [String] = [
        "_http._tcp",
        "_ipp._tcp",
        "_raop._tcp",
        "_daap._tcp",
        "_airdrop._tcp",
        "_bluetoothd2._tcp"
    ]
    
    private var bonjourBrowsers: [NWBrowser] = []
    private var serviceToDeviceId: [ObjectIdentifier: UUID] = [:]
    
    // Configurable scan duration in seconds.
    private let scanDuration: TimeInterval = 15.0
    
    private let logger = Logger(subsystem: "com.example.ScanX", category: "NetworkScanner")
    
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
        
        var identifier: String { friendlyName ?? serviceName }
        
        init(serviceName: String, serviceDomain: String, serviceType: String) {
            self.serviceName = serviceName
            self.serviceDomain = serviceDomain
            self.serviceType = serviceType
        }
        
        func deviceTypeIcon() -> String {
            let lower = identifier.lowercased()
            if lower.contains("epson") || lower.contains("printer") { return "printer.fill" }
            else if lower.contains("rsled") || lower.contains("rsato") { return "lightbulb.fill" }
            else if lower.contains("mac") || lower.contains("dell") ||
                        lower.contains("pc") || lower.contains("computer") { return "desktopcomputer" }
            else { return "questionmark.circle" }
        }
    }
    
    func scanNetwork() {
        guard !isScanning else {
            logger.debug("Scan already in progress. Ignoring new scan request.")
            return
        }
        for browser in bonjourBrowsers { browser.cancel() }
        bonjourBrowsers.removeAll()
        devices.removeAll()
        isScanning = true
        serviceToDeviceId.removeAll()
        
        logger.info("Starting network scan for service types: \(self.serviceTypes.description, privacy: .public)")
        for type in self.serviceTypes { createAndStartBrowser(for: type) }
        
        // End the scan after a configurable duration.
        DispatchQueue.main.asyncAfter(deadline: .now() + scanDuration) { [weak self] in
            guard let self = self else { return }
            for browser in self.bonjourBrowsers { browser.cancel() }
            self.bonjourBrowsers.removeAll()
            self.isScanning = false
            self.logger.info("🔎 [Bonjour] Scan ended after \(self.scanDuration) seconds.")
        }
    }
    private func createAndStartBrowser(for serviceType: String) {
        let descriptor = NWBrowser.Descriptor.bonjour(type: serviceType, domain: nil)
        let parameters = NWParameters.tcp
        let browser = NWBrowser(for: descriptor, using: parameters)
        
        // Create an explicitly typed closure variable.
        let stateHandler: (NWBrowser.State) -> Void = { [weak self] state in
            guard let self = self else { return }
            // Convert the values explicitly to String to avoid ambiguity.
            self.logger.debug("🔎 [Bonjour] Browser state for \(String(describing: serviceType)): \(String(describing: state))")
            if case .failed(let error) = state {
                self.logger.error("🔎 [Bonjour] Browser for \(String(describing: serviceType)) failed with error: \(error.localizedDescription)")
                DispatchQueue.main.async { self.isScanning = false }
            }
        }
        browser.stateUpdateHandler = stateHandler
        
        // The browseResultsChangedHandler remains unchanged.
        browser.browseResultsChangedHandler = { [weak self] (results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) in
            guard let self = self else { return }
            for result in results {
                switch result.endpoint {
                case .service(let name, let type, let domain, _):
                    DispatchQueue.main.async {
                        if !self.devices.contains(where: { $0.serviceName == name &&
                            $0.serviceDomain == domain && $0.serviceType == type }) {
                            let device = Device(serviceName: name, serviceDomain: domain, serviceType: type)
                            self.devices.append(device)
                            self.logger.info("🔎 [Bonjour] Discovered service: \(name) in domain: \(domain) of type: \(type)")
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
    
    private func resolveService(name: String, type: String, domain: String) {
        let netService = NetService(domain: domain, type: type, name: name)
        netService.delegate = self
        netService.schedule(in: RunLoop.main, forMode: .common)
        if let device = self.devices.first(where: { $0.serviceName == name &&
                                                     $0.serviceDomain == domain &&
                                                     $0.serviceType == type }) {
            serviceToDeviceId[ObjectIdentifier(netService)] = device.id
        }
        logger.info("🔎 [Bonjour] Resolving service: \(name, privacy: .public) \(type, privacy: .public) \(domain, privacy: .public)")
        netService.resolve(withTimeout: 10.0)
    }
    
    // MARK: - NetServiceDelegate Methods
    
    func netServiceDidResolveAddress(_ sender: NetService) {
        let key = ObjectIdentifier(sender)
        guard let deviceID = serviceToDeviceId[key],
              let device = devices.first(where: { $0.id == deviceID })
        else {
            logger.error("🔎 [Bonjour] No device mapping for resolved service \(sender.name, privacy: .public)")
            return
        }
        
        var foundIP: String? = nil
        if let addresses = sender.addresses, !addresses.isEmpty {
            logger.debug("🔎 [Bonjour] \(sender.name, privacy: .public) has \(addresses.count, privacy: .public) addresses")
            for addressData in addresses {
                if let ip = ipAddressFromData(addressData) {
                    foundIP = ip
                    logger.info("🔎 [Bonjour] Found IP \(ip, privacy: .public) for service \(sender.name, privacy: .public)")
                    break
                }
            }
            if foundIP == nil {
                logger.warning("🔎 [Bonjour] No valid IP parsed from addresses for \(sender.name, privacy: .public)")
            }
        } else {
            logger.warning("🔎 [Bonjour] No addresses available for \(sender.name, privacy: .public)")
        }
        
        if foundIP == nil {
            logger.info("🔎 [Bonjour] Attempting fallback resolution using DNSServiceResolver for \(sender.name, privacy: .public)")
            DNSServiceResolver.resolve(name: sender.name, type: sender.type, domain: sender.domain) { host, port in
                if let host = host, let port = port {
                    DispatchQueue.main.async {
                        device.resolvedIPAddress = host
                        device.port = Int(port)
                        self.logger.info("🔎 [DNSService] Resolved \(sender.name, privacy: .public) to IP: \(host, privacy: .public) on port: \(port, privacy: .public)")
                    }
                } else {
                    self.logger.error("🔎 [DNSService] Failed to resolve \(sender.name, privacy: .public) using DNSServiceResolver")
                }
            }
            return
        }
        
        DispatchQueue.main.async {
            device.resolvedIPAddress = foundIP
            device.port = sender.port
            self.logger.info("🔎 [Bonjour] Service \(sender.name, privacy: .public) resolved to IP: \(foundIP!, privacy: .public) on port: \(sender.port, privacy: .public)")
        }
        
        // Process TXT records.
        if let txtData = sender.txtRecordData() {
            let txtDict = NetService.dictionary(fromTXTRecord: txtData)
            if txtDict.isEmpty {
                logger.debug("🔎 [Bonjour] TXT record data empty for \(sender.name, privacy: .public)")
            } else {
                var allTXTRecords: [String: String] = [:]
                for (key, value) in txtDict {
                    if let stringValue = String(data: value, encoding: .utf8) {
                        allTXTRecords[key] = stringValue
                    }
                }
                DispatchQueue.main.async {
                    device.txtRecords = allTXTRecords
                    self.logger.info("🔎 [Bonjour] TXT records for \(sender.name, privacy: .public): \(allTXTRecords.description, privacy: .public)")
                }
                if let friendlyData = txtDict["fn"] ?? txtDict["n"],
                   let friendly = String(data: friendlyData, encoding: .utf8),
                   !friendly.isEmpty {
                    DispatchQueue.main.async {
                        device.friendlyName = friendly
                        self.logger.info("🔎 [Bonjour] Resolved friendly name for \(sender.name, privacy: .public): \(friendly, privacy: .public)")
                    }
                } else {
                    logger.debug("🔎 [Bonjour] No friendly name found in TXT records for \(sender.name, privacy: .public)")
                }
                if let modelData = txtDict["md"],
                   let model = String(data: modelData, encoding: .utf8),
                   !model.isEmpty {
                    DispatchQueue.main.async {
                        device.model = model
                        self.logger.info("🔎 [Bonjour] Resolved model for \(sender.name, privacy: .public): \(model, privacy: .public)")
                    }
                } else {
                    logger.debug("🔎 [Bonjour] No model info found in TXT records for \(sender.name, privacy: .public)")
                }
            }
        } else {
            logger.debug("🔎 [Bonjour] No TXT record data available for \(sender.name, privacy: .public)")
        }
    }
    
    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        logger.error("🔎 [Bonjour] Failed to resolve \(sender.name, privacy: .public) with error: \(errorDict.description, privacy: .public)")
    }
    
    // MARK: - Helper Function
    
    private func ipAddressFromData(_ data: Data) -> String? {
        var storage = sockaddr_storage()
        (data as NSData).getBytes(&storage, length: MemoryLayout<sockaddr_storage>.size)
        if Int32(storage.ss_family) == AF_INET {
            let addr = withUnsafePointer(to: &storage) {
                $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            }
            if let ipCStr = inet_ntoa(addr) { return String(cString: ipCStr) }
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
}

