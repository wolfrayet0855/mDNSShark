import SwiftUI

// MARK: - DeviceDetailView
struct DeviceDetailView: View {
    @ObservedObject var device: NetworkScanner.Device
    
    /// Attempt to parse the portion before '@' as a MAC-like address.
    private var macLikeAddress: String? {
        let parts = device.serviceName.split(separator: "@", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return String(parts[0]) // (Optional) Could also add a regex or hex check here.
    }
    
    /// Attempt to parse the portion after '@' as a true IPv6 link-local address
    /// only if it starts with "fe80::" (case-insensitive).
    private var ipv6LinkLocal: String? {
        let parts = device.serviceName.split(separator: "@", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let remainder = parts[1]
        // Stricter check: ensure it starts with "fe80::"
        guard remainder.lowercased().hasPrefix("fe80::") else {
            return nil
        }
        return String(remainder)
    }

    var body: some View {
        Form {
            Section(header: Text("BASIC INFO")) {
                HStack {
                    Text("MAC-Like Address:")
                    Spacer()
                    Text(macLikeAddress ?? "Unavailable")
                }
                HStack {
                    Text("IPv6 Link-Local:")
                    Spacer()
                    Text(ipv6LinkLocal ?? "Unavailable")
                }
                HStack {
                    Text("Bonjour Service Name:")
                    Spacer()
                    Text(device.serviceName)
                }
                HStack {
                    Text("Domain:")
                    Spacer()
                    Text(device.serviceDomain)
                }
                HStack {
                    Text("Service Type:")
                    Spacer()
                    Text(device.serviceType)
                }
            }
        }
        .navigationTitle(device.serviceName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
