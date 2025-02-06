import SwiftUI
import Network
import Combine
import CoreFoundation
import os
import Darwin

// MARK: - NetworkScanner
class NetworkScanner: NSObject, ObservableObject, NetServiceDelegate {
    @Published var devices: [Device] = []
    @Published var isScanning: Bool = false

    // Updated service types list: removed duplicates and fixed typos.
    // Updated service types list: includes both your existing services and additional service types.
    private let serviceTypes: [String] = [
        // Common services
        "_http._tcp",
        "_https._tcp",
        "_ftp._tcp",
        "_ssh._tcp",
        "_telnet._tcp",
        "_smb._tcp",
        "_afpovertcp._tcp",
        "_nfs._tcp",
        "_workstation._tcp",

        // Apple / macOS / iOS services
        "_airdrop._tcp",
        "_airplay._tcp",
        "_apple-mobdev2._tcp",
        "_adisk._tcp",
        "_time-machine._tcp",
        "_airport._tcp",       // AirPort base station
        "_afpovertcp._tcp",    // Apple Filing Protocol
        "_device-info._tcp",
        "_services._dns-sd._udp", // DNS-SD meta-service

        // Printing & Scanning
        "_ipp._tcp",           // Internet Printing Protocol
        "_ipps._tcp",          // Secure IPP
        "_printer._tcp",
        "_pdl-datastream._tcp",// HP Printer PDL
        "_scanner._tcp",

        // Media & Streaming
        "_raop._tcp",          // AirPlay audio streaming
        "_daap._tcp",          // iTunes DAAP
        "_dacp._tcp",          // iTunes/Apple TV remote control
        "_spotify-connect._tcp",
        "_googlecast._tcp",

        // File sharing & sync
        "_bluetoothd2._tcp",
        "_btsync._tcp",        // Resilio/BitTorrent Sync
        "_workstation._tcp",   // SMB workstation
        "_distcc._tcp",        // Distributed C/C++ compiler
        "_webdav._tcp",

        // Remote screen / management
        "_rfb._tcp",           // VNC Remote Frame Buffer
        "_remotemanagement._tcp",

        // IoT / HomeKit / Presence
        "_hap._tcp",           // HomeKit Accessory Protocol
        "_presence._tcp",
        "_mqtt._tcp",          // MQTT broker/client
        "_coap._udp",          // Constrained Application Protocol
        "_peertalk._tcp",

        // Security & Other
        "_services._dns-sd._udp",
        "_time._udp",
        "_timedate._udp",
        "_ssh._tcp",           // (Listed again if you want to group separately)
        "_tcpchat._tcp",       // Example custom chat
        "_raop._tcp",          // (Duplicate if you prefer grouping)
        "_acp-sync._tcp"       // Example for Apple Config / sync
    ]


    
    // Dedicated queue for Bonjour browser tasks.
    private let bonjourQueue = DispatchQueue(label: "com.example.ScanX.bonjourQueue")
    
    private var bonjourBrowsers: [NWBrowser] = []
    private var serviceToDeviceId: [ObjectIdentifier: UUID] = [:]
    
    // Scan duration in seconds.
    private let scanDuration: TimeInterval = 25.0
    private let logger = Logger(subsystem: "com.example.ScanX", category: "NetworkScanner")
    
    // Instance of the local subnet scanner.
    private let localScanner = LocalDeviceScanner()
    private var cancellables = Set<AnyCancellable>()
    
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
    }
    
    // MARK: - Public Scanning Method
    func scanNetwork() {
        guard !isScanning else {
            logger.debug("Scan already in progress.")
            return
        }
        // Cancel any existing browsers and clear previous results.
        for browser in bonjourBrowsers { browser.cancel() }
        bonjourBrowsers.removeAll()
        devices.removeAll()
        isScanning = true
        serviceToDeviceId.removeAll()
        logger.info("Starting network scan for service types: \(self.serviceTypes)")
        
        // Start Bonjour scanning.
        for type in self.serviceTypes {
            createAndStartBrowser(for: type)
        }
        
        // Start SSDP scanning.
        scanSSDP()
        
        // Start local TCP subnet scanning.
        localScanner.scanLocalSubnet(port: NWEndpoint.Port(rawValue: 80)!)
        localScanner.$discoveredIPs
            .sink { [weak self] ips in
                guard let self = self else { return }
                for ip in ips {
                    if !self.devices.contains(where: { $0.resolvedIPAddress == ip }) {
                        let device = Device(serviceName: ip, serviceDomain: "local", serviceType: "tcp")
                        device.resolvedIPAddress = ip
                        self.devices.append(device)
                        self.logger.info("Local scan discovered device at IP: \(ip)")
                    }
                }
            }
            .store(in: &cancellables)
        
        // End the scan after the configured duration.
        DispatchQueue.main.asyncAfter(deadline: .now() + scanDuration) { [weak self] in
            guard let self = self else { return }
            for browser in self.bonjourBrowsers { browser.cancel() }
            self.bonjourBrowsers.removeAll()
            self.isScanning = false
            self.logger.info("Scan ended after \(self.scanDuration) seconds.")
        }
    }
    
    // MARK: - Bonjour Scanning
    private func createAndStartBrowser(for serviceType: String) {
        let descriptor = NWBrowser.Descriptor.bonjour(type: serviceType, domain: nil)
        // Choose network parameters based on service type:
        // If the service type indicates UDP, use UDP parameters; otherwise, use TCP.
        let parameters: NWParameters = serviceType.contains("_udp") ? .udp : .tcp
        let browser = NWBrowser(for: descriptor, using: parameters)
        let capturedServiceType: String = serviceType  // capture explicitly
        
        browser.stateUpdateHandler = { [weak self] (state: NWBrowser.State) -> Void in
            guard let self = self else { return }
            self.logger.info("Bonjour browser for \(capturedServiceType) state: \(String(describing: state))")
            if case .failed(let error) = state {
                self.logger.error("Bonjour browser for \(capturedServiceType) failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isScanning = false
                }
            }
        }
        
        browser.browseResultsChangedHandler = { [weak self] (results: Set<NWBrowser.Result>, changes: Set<NWBrowser.Result.Change>) -> Void in
            guard let self = self else { return }
            self.processBrowseResults(results)
        }
        
        // Start the browser on the dedicated queue.
        browser.start(queue: bonjourQueue)
        bonjourBrowsers.append(browser)
    }
    
    /// Processes the results returned by an NWBrowser.
    private func processBrowseResults(_ results: Set<NWBrowser.Result>) {
        for result in results {
            switch result.endpoint {
            case .service(let name, let type, let domain, _):
                DispatchQueue.main.async {
                    if !self.devices.contains(where: { $0.serviceName == name &&
                        $0.serviceDomain == domain &&
                        $0.serviceType == type }) {
                        let device = Device(serviceName: name, serviceDomain: domain, serviceType: type)
                        self.devices.append(device)
                        self.logger.info("Bonjour discovered: \(name) in domain: \(domain) of type: \(type)")
                        self.resolveService(name: name, type: type, domain: domain)
                    }
                }
            default:
                break
            }
        }
    }
    
    /// Attempts to resolve a discovered NetService.
    private func resolveService(name: String, type: String, domain: String) {
        let netService = NetService(domain: domain, type: type, name: name)
        netService.delegate = self
        netService.schedule(in: RunLoop.main, forMode: .common)
        if let device = self.devices.first(where: { $0.serviceName == name &&
                                                     $0.serviceDomain == domain &&
                                                     $0.serviceType == type }) {
            serviceToDeviceId[ObjectIdentifier(netService)] = device.id
        }
        logger.info("Resolving service: \(name) \(type) \(domain)")
        netService.resolve(withTimeout: 10.0)
    }
    
    // MARK: - SSDP/UPnP Scanning via UDP
    private func scanSSDP() {
        let ssdpAddress = "239.255.255.250"
        let ssdpPort: UInt16 = 1900
        let ssdpMessage = """
        M-SEARCH * HTTP/1.1\r
        HOST: 239.255.255.250:1900\r
        MAN: "ssdp:discover"\r
        MX: 3\r
        ST: ssdp:all\r
        \r\n
        """
        
        let sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        if sock < 0 {
            logger.error("SSDP socket creation failed")
            return
        }
        
        var ttl: Int32 = 2
        setsockopt(sock, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<Int32>.size))
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = ssdpPort.bigEndian
        inet_pton(AF_INET, ssdpAddress, &addr.sin_addr)
        
        let sendResult = ssdpMessage.withCString { ptr -> ssize_t in
            return withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    sendto(sock, ptr, strlen(ptr), 0, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        
        if sendResult < 0 {
            logger.error("SSDP sendto failed")
            close(sock)
            return
        }
        logger.info("SSDP M-SEARCH message sent.")
        
        let source = DispatchSource.makeReadSource(fileDescriptor: sock, queue: DispatchQueue.global())
        source.setEventHandler { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 1024)
            let count = recv(sock, &buffer, buffer.count, 0)
            if count > 0 {
                let data = Data(buffer[0..<count])
                if let response = String(data: data, encoding: .utf8) {
                    self?.logger.info("Received SSDP response: \(response)")
                    self?.parseSSDPResponse(response)
                } else {
                    self?.logger.debug("Received non-string SSDP data")
                }
            }
        }
        source.setCancelHandler {
            close(sock)
        }
        source.resume()
        
        DispatchQueue.global().asyncAfter(deadline: .now() + scanDuration) {
            source.cancel()
        }
    }
    
    private func parseSSDPResponse(_ response: String) {
        let lines = response.components(separatedBy: "\r\n")
        var headers: [String: String] = [:]
        for line in lines {
            if let separatorRange = line.range(of: ":") {
                let key = line[..<separatorRange.lowerBound].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[separatorRange.upperBound...].trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }
        guard let location = headers["location"] else {
            logger.debug("SSDP response missing LOCATION header: \(response)")
            return
        }
        let usn = headers["usn"] ?? location
        let server = headers["server"] ?? "SSDP Device"
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if !self.devices.contains(where: { $0.serviceName == usn && $0.serviceDomain == "ssdp" }) {
                let device = Device(serviceName: usn, serviceDomain: "ssdp", serviceType: "ssdp")
                device.friendlyName = server
                if let url = URL(string: location), let host = url.host {
                    device.resolvedIPAddress = host
                    device.port = url.port ?? 80
                }
                self.devices.append(device)
                self.logger.info("SSDP discovered device: \(usn) at \(location)")
            }
        }
    }
    
    // MARK: - NetServiceDelegate Methods
    func netServiceDidResolveAddress(_ sender: NetService) {
        let key = ObjectIdentifier(sender)
        guard let deviceID = serviceToDeviceId[key],
              let device = devices.first(where: { $0.id == deviceID }) else {
            logger.error("No device mapping for resolved service \(sender.name)")
            return
        }
        
        var foundIP: String? = nil
        if let addresses = sender.addresses, !addresses.isEmpty {
            logger.info("\(sender.name) has \(addresses.count) addresses")
            for addressData in addresses {
                if let ip = ipAddressFromData(addressData) {
                    foundIP = ip
                    logger.info("Found IP \(ip) for \(sender.name)")
                    break
                }
            }
            if foundIP == nil {
                logger.warning("No valid IP parsed for \(sender.name)")
            }
        } else {
            logger.warning("No addresses available for \(sender.name)")
        }
        
        if foundIP == nil {
            logger.info("Attempting fallback resolution for \(sender.name)")
            DNSServiceResolver.resolve(name: sender.name, type: sender.type, domain: sender.domain) { host, port in
                if let host = host, let port = port {
                    DispatchQueue.main.async {
                        device.resolvedIPAddress = host
                        device.port = Int(port)
                        self.logger.info("Fallback resolved \(sender.name) to IP: \(host) on port: \(port)")
                    }
                } else {
                    self.logger.error("Fallback resolution failed for \(sender.name)")
                }
            }
            return
        }
        
        DispatchQueue.main.async {
            device.resolvedIPAddress = foundIP
            device.port = sender.port
            self.logger.info("Resolved \(sender.name) to IP: \(foundIP!) on port: \(sender.port)")
        }
        
        if let txtData = sender.txtRecordData() {
            let txtDict = NetService.dictionary(fromTXTRecord: txtData)
            if txtDict.isEmpty {
                logger.debug("TXT record data empty for \(sender.name)")
            } else {
                var allTXTRecords = [String: String]()
                for (key, value) in txtDict {
                    if let stringValue = String(data: value, encoding: .utf8) {
                        allTXTRecords[key] = stringValue
                    }
                }
                DispatchQueue.main.async {
                    device.txtRecords = allTXTRecords
                    self.logger.info("TXT records for \(sender.name): \(allTXTRecords)")
                }
                if let friendlyData = txtDict["fn"] ?? txtDict["n"],
                   let friendly = String(data: friendlyData, encoding: .utf8),
                   !friendly.isEmpty {
                    DispatchQueue.main.async {
                        device.friendlyName = friendly
                        self.logger.info("Resolved friendly name for \(sender.name): \(friendly)")
                    }
                } else {
                    logger.debug("No friendly name found for \(sender.name)")
                }
                if let modelData = txtDict["md"],
                   let model = String(data: modelData, encoding: .utf8),
                   !model.isEmpty {
                    DispatchQueue.main.async {
                        device.model = model
                        self.logger.info("Resolved model for \(sender.name): \(model)")
                    }
                } else {
                    logger.debug("No model info found for \(sender.name)")
                }
            }
        } else {
            logger.debug("No TXT record data available for \(sender.name)")
        }
    }
    
    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        logger.error("Failed to resolve \(sender.name) with error: \(errorDict)")
    }
    
    /// Helper to extract an IP address from Data.
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
            var addr6 = addr
            inet_ntop(AF_INET6, &addr6, &buffer, socklen_t(INET6_ADDRSTRLEN))
            return String(cString: buffer)
        }
        return nil
    }
}

