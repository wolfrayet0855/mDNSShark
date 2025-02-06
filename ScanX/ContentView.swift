import SwiftUI

// MARK: - ContentView
struct ContentView: View {
    @StateObject private var scanner = NetworkScanner()
    
    // A mapping from service types to their definitions (summaries) for display in the list view.
    private let serviceTypeSummaries: [String: String] = [
        "_http._tcp": "HTTP web service. Often used for websites and APIs.",
        "_ipp._tcp": "Internet Printing Protocol. Used by network printers.",
        "_raop._tcp": "AirPlay audio service (Remote Audio Output Protocol).",
        "_daap._tcp": "Digital Audio Access Protocol for sharing music libraries.",
        "_airdrop._tcp": "AirDrop file sharing service for Apple devices.",
        "_bluetoothd2._tcp": "Bluetooth-related service for device connectivity.",
        "_ftp._tcp": "File Transfer Protocol for transferring files.",
        "_services._dns-sd._udp": "DNS-SD meta-service. Enumerates other Bonjour services.",
        "_apple-mobdev2._tcp": "Used by Apple devices (e.g., iOS) for device discovery.",
        "_afpovertcp._tcp": "Apple Filing Protocol over TCP for file sharing.",
        "_ssh._tcp": "Secure Shell (SSH) service.",
        "_smb._tcp": "SMB file sharing service (Windows file sharing).",
        "_airplay._tcp": "AirPlay streaming service for audio or video.",
        "_device-info._tcp": "Provides basic device information.",
        "_printer._tcp": "Generic printer service.",
        "_https._tcp": "Secure HTTP web service (HTTPS).",
        "_rfb._tcp": "Remote Frame Buffer protocol (VNC screen sharing).",
        "_googlecast._tcp": "Google Cast/Chromecast service.",
        "_dacp._tcp": "Digital Audio Control Protocol.",
        "_workstation._tcp": "Indicates a SMB workstation or host service.",
        "_time-machine._tcp": "Apple Time Machine backup service.",
        "_adisk._tcp": "Apple AirDisk advertising for Time Capsule or disk sharing.",
        "_hap._tcp": "HomeKit Accessory Protocol.",
        "_presence._tcp": "Presence detection or status service.",
        "_btsync._tcp": "Resilio/Bittorrent Sync service.",
        "_mqtt._tcp": "MQTT message broker or client service.",
        "_coap._udp": "Constrained Application Protocol over UDP."
    ]
    
    var body: some View {
        NavigationView {
            VStack {
                Button(action: {
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
                    ProgressView()
                        .padding()
                }
                
                if scanner.devices.isEmpty && !scanner.isScanning {
                    Text("No devices found. Tap 'Scan Network' to start.")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    List(scanner.devices) { device in
                        // Display the device name, service type, and a one-line summary.
                        NavigationLink(destination: DeviceDetailView(device: device)) {
                            VStack(alignment: .leading) {
                                Text(device.identifier)
                                    .font(.headline)
                                Text(device.serviceType)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text(serviceTypeSummaries[device.serviceType] ?? "No summary available.")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
                Spacer()
            }
            .navigationTitle("Network Scanner")
        }
    }
}

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

