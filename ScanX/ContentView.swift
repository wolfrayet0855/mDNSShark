import SwiftUI

struct ContentView: View {
    @StateObject private var scanner = NetworkScanner()

    var body: some View {
        NavigationView {
            VStack {
                Button(action: {
                    print("🔵 [UI] 'Scan Network' button tapped")
                    scanner.scanNetwork()
                }) {
                    Text(scanner.isScanning ? "Scanning..." : "Scan Network")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(scanner.isScanning ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding()

                if scanner.isScanning {
                    ProgressView().padding()
                }
                
                if scanner.devices.isEmpty && !scanner.isScanning {
                    Text("No devices found. Tap 'Scan Network' to start.")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    List(scanner.devices) { device in
                        NavigationLink(destination: DeviceDetailView(device: device)) {
                            DeviceRow(device: device)
                        }
                    }
                }
                Spacer()
            }
            .navigationTitle("Network Scanner")
        }
    }
}

struct DeviceRow: View {
    @ObservedObject var device: NetworkScanner.Device
    var body: some View {
        HStack {
            Image(systemName: device.deviceTypeIcon())
                .foregroundColor(.accentColor)
                .imageScale(.large)
            VStack(alignment: .leading) {
                Text(device.identifier)
                    .font(.headline)
                HStack(spacing: 4) {
                    Text(device.serviceType)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    if let ip = device.resolvedIPAddress {
                        Text("· \(ip)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    if let port = device.port {
                        Text(":\(port)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct DeviceDetailView: View {
    @ObservedObject var device: NetworkScanner.Device

    // A mapping from service types to their definitions.
    private let serviceTypeDefinitions: [String: String] = [
        "_http._tcp": "HTTP web service. Often used for websites and APIs.",
        "_ipp._tcp": "Internet Printing Protocol. Used by network printers.",
        "_raop._tcp": "AirPlay audio service (Remote Audio Output Protocol) for streaming audio.",
        "_daap._tcp": "Digital Audio Access Protocol for sharing music libraries.",
        "_airdrop._tcp": "AirDrop file sharing service for Apple devices.",
        "_bluetoothd2._tcp": "Bluetooth related service for device connectivity."
    ]
    
    var body: some View {
        Form {
            Section(header: Text("Basic Info")) {
                HStack {
                    Text("Name:")
                    Spacer()
                    Text(device.identifier)
                }
                HStack {
                    Text("Service Type:")
                    Spacer()
                    Text(device.serviceType)
                    // Info icon with a context menu for service definition.
                    Image(systemName: "questionmark.circle")
                        .foregroundColor(.blue)
                        .contextMenu {
                            Text(serviceTypeDefinitions[device.serviceType] ?? "No definition available.")
                        }
                }
                HStack {
                    Text("Domain:")
                    Spacer()
                    Text(device.serviceDomain)
                }
            }
            Section(header: Text("Resolved Info")) {
                HStack {
                    Text("IP Address:")
                    Spacer()
                    Text(device.resolvedIPAddress ?? "Not available")
                }
                HStack {
                    Text("Port:")
                    Spacer()
                    Text(device.port != nil ? "\(device.port!)" : "Not available")
                }
                HStack {
                    Text("Friendly Name:")
                    Spacer()
                    Text(device.friendlyName ?? "Not available")
                }
                HStack {
                    Text("Model:")
                    Spacer()
                    Text(device.model ?? "Not available")
                }
            }
            if let txtRecords = device.txtRecords, !txtRecords.isEmpty {
                Section(header: Text("TXT Records")) {
                    ForEach(txtRecords.keys.sorted(), id: \.self) { key in
                        HStack {
                            Text("\(key):")
                            Spacer()
                            Text(txtRecords[key] ?? "")
                        }
                    }
                }
            }
        }
        .navigationTitle(device.identifier)
        .navigationBarTitleDisplayMode(.inline)
    }
}

