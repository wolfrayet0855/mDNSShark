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
                Text(device.serviceType)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct DeviceDetailView: View {
    @ObservedObject var device: NetworkScanner.Device
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
        }
        .navigationTitle(device.identifier)
        .navigationBarTitleDisplayMode(.inline)
    }
}

