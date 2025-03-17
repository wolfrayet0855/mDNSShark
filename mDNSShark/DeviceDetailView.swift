//  DeviceDetailView.swift

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
     Takes a raw MAC string like "A4CF99725E8A" or "A4:CF:99:72:5E:8A" and returns
     just the **first three octets** (e.g. "a4:cf:99") in lowercase for OUI lookup.
     */
    private func ouiPrefix(from rawMac: String) -> String? {
        // Remove any non-hex or non-colon characters
        let cleaned = rawMac
            .replacingOccurrences(of: "[^A-Fa-f0-9:]", with: "", options: .regularExpression)
            .lowercased()
        
        // If it's already colon-separated, we might just split:
        let hexCharsOnly = cleaned.replacingOccurrences(of: ":", with: "")
        guard hexCharsOnly.count == 12 else {
            // Not exactly 6 bytes worth of hex => can't parse
            return nil
        }
        
        // Insert colons every 2 hex digits => "a4:cf:99:72:5e:8a"
        var pairs: [String] = []
        for i in stride(from: 0, to: 12, by: 2) {
            let start = hexCharsOnly.index(hexCharsOnly.startIndex, offsetBy: i)
            let end   = hexCharsOnly.index(start, offsetBy: 2)
            pairs.append(String(hexCharsOnly[start..<end]))
        }
        // We only care about the first three octets => "a4:cf:99"
        return pairs.prefix(3).joined(separator: ":")
    }

    
    /**
     Final computed property that looks up the manufacturer
     in the OUIDatabase if the `macLikeAddress` is parseable.
    */
    private var macOUI: String? {
        guard let mac = macLikeAddress else { return nil }
        guard let prefix = ouiPrefix(from: mac) else { return nil }
        return OUIDatabase.shared.manufacturer(for: prefix)
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

