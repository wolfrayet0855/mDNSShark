import SwiftUI

// MARK: - DeviceDetailView
struct DeviceDetailView: View {
    @ObservedObject var device: NetworkScanner.Device
    
    /// The Bonjour service name exactly as advertised.
    private var bonjourServiceName: String {
        device.serviceName
    }
    
    /// The domain name (usually "local.") advertised by Bonjour.
    private var domain: String {
        device.serviceDomain
    }
    
    /// The underlying service type (e.g. "_apple-mobdev2._tcp").
    private var serviceType: String {
        device.serviceType
    }
    
    /// Attempt to parse the portion before '@' as the MAC-like address.
    private var macLikeAddress: String? {
        let parts = bonjourServiceName.split(separator: "@", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return String(parts[0])
    }
    
    /// Extract the portion after '@' if present (to check for "fe80::").
    private var remainderAfterAt: Substring? {
        let segments = bonjourServiceName.split(separator: "@", maxSplits: 1)
        guard segments.count == 2 else { return nil }
        return segments[1]
    }
    
    /// If the remainder starts with "fe80::", return the link-local address.
    /// If there's a dash, parse that out as "Additional Info."
    private var ipv6LinkLocal: String? {
        guard let remainder = remainderAfterAt, remainder.lowercased().hasPrefix("fe80::") else {
            return nil
        }
        if let dashRange = remainder.range(of: "-") {
            return String(remainder[..<dashRange.lowerBound])
        } else {
            return String(remainder)
        }
    }
    
    private var additionalInfo: String? {
        guard let remainder = remainderAfterAt, remainder.lowercased().hasPrefix("fe80::") else {
            return nil
        }
        if let dashRange = remainder.range(of: "-") {
            let afterDash = remainder[dashRange.upperBound...]
            return String(afterDash)
        } else {
            return nil
        }
    }
    
    /**
     Parse the first three octets of the MAC-like address to look up the manufacturer
     in the dynamic OUIDatabase.
    */
    private var macOUI: String? {
        guard let mac = macLikeAddress else { return nil }
        let lowerMac = mac.lowercased()
        let components = lowerMac.split(separator: ":")
        guard components.count >= 3 else { return nil }
        
        // Join the first 3 components back with ":" to form the OUI key (e.g. "98:50:2e").
        let firstThree = components[0...2].joined(separator: ":")
        
        // Perform a lookup in our dynamic database.
        return OUIDatabase.shared.manufacturer(for: firstThree)
    }
    
    var body: some View {
        Form {
            Section(header: Text("BASIC INFO")) {
                
                // Bonjour Service Name
                HStack {
                    Text("Bonjour Service Name:")
                    Spacer()
                    Text(bonjourServiceName)
                }
                
                // Domain
                HStack {
                    Text("Domain:")
                    Spacer()
                    Text(domain)
                }
                
                // Service Type
                HStack {
                    Text("Service Type:")
                    Spacer()
                    Text(serviceType)
                }
                
                // MAC-like address
                HStack {
                    Text("MAC-Like Address:")
                    Spacer()
                    Text(macLikeAddress ?? "Unavailable")
                }
                
                // Manufacturer (OUI)
                HStack {
                    Text("Manufacturer (OUI):")
                    Spacer()
                    Text(macOUI ?? "N/A")
                }
                
                // IPv6 link-local
                HStack {
                    Text("IPv6 Link-Local:")
                    Spacer()
                    Text(ipv6LinkLocal ?? "Unavailable")
                }
                
                // Additional info
                HStack {
                    Text("Additional Info:")
                    Spacer()
                    Text(additionalInfo ?? "N/A")
                }
            }
        }
        .navigationTitle(bonjourServiceName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

