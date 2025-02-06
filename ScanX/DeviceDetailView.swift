import SwiftUI

// MARK: - DeviceDetailView
struct DeviceDetailView: View {
    @ObservedObject var device: NetworkScanner.Device
    
    /// Extract the part before '@' in `device.serviceName` if present.
    private var macLikeAddress: String? {
        let parts = device.serviceName.split(separator: "@", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return String(parts[0])
    }
    
    /// Extract the IPv6 link-local portion (between '@' and first '-') if present.
    private var ipv6LinkLocal: String? {
        let parts = device.serviceName.split(separator: "@", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let afterAt = parts[1]
        // If there is a dash, everything before that is the link-local address.
        if let dashRange = afterAt.range(of: "-") {
            return String(afterAt[..<dashRange.lowerBound])
        } else {
            // Otherwise, return the entire substring after '@'
            return String(afterAt)
        }
    }

    var body: some View {
        Form {
            Section(header: Text("Basic Info")) {
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
