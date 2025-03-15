import SwiftUI

struct ContentView: View {
    @StateObject private var scanner = NetworkScanner()
    @State private var scanDuration: Double = 25.0
    @State private var showRouterTip: Bool = true
    
    private let serviceTypeSummaries: [String: String] = [
        // Common / Web
        "_http._tcp": "HTTP web service, often used for websites/APIs.",
        "_https._tcp": "Secure HTTP (HTTPS) service.",
        "_ftp._tcp": "File Transfer Protocol for transferring files.",
        "_webdav._tcp": "WebDAV protocol for remote file management.",
        
        // Apple / AirPlay / Airdrop
        "_airplay._tcp": "AirPlay streaming for audio/video.",
        "_airdrop._tcp": "AirDrop file sharing for Apple devices.",
        "_apple-mobdev2._tcp": "Used by Apple devices for wireless discovery and sync.",
        "_afpovertcp._tcp": "Apple Filing Protocol over TCP for file sharing.",
        "_adisk._tcp": "Advertises an Apple AirDisk (e.g. Time Capsule).",
        "_time-machine._tcp": "Apple Time Machine backup service.",
        "_airport._tcp": "AirPort (Apple Wi-Fi base station) service.",
        "_daap._tcp": "iTunes DAAP service for music library sharing.",
        "_dacp._tcp": "Apple remote control protocol (iTunes/Apple TV).",
        "_raop._tcp": "AirPlay audio (Remote Audio Output Protocol).",
        "_device-info._tcp": "Basic Apple device info (model/version).",
        
        // Printing / Scanning
        "_ipp._tcp": "Internet Printing Protocol for printers.",
        "_ipps._tcp": "Secure IPP (Internet Printing Protocol).",
        "_printer._tcp": "Generic printer service.",
        "_pdl-datastream._tcp": "HP Printer PDL data stream.",
        "_scanner._tcp": "Network scanner service.",
        
        // Remote Access / OS
        "_ssh._tcp": "SSH remote shell access.",
        "_telnet._tcp": "Telnet (insecure) remote shell service.",
        "_rfb._tcp": "VNC (Remote Frame Buffer) screen sharing.",
        "_remotemanagement._tcp": "Apple Remote Desktop management service.",
        
        // SMB / Windows / NFS
        "_smb._tcp": "Windows SMB file sharing service.",
        "_workstation._tcp": "SMB workstation or host service.",
        "_nfs._tcp": "Network File System (NFS) sharing.",
        
        // Sync & Tools
        "_btsync._tcp": "Resilio/Bittorrent Sync service.",
        "_distcc._tcp": "Distributed C/C++ compilation service.",
        "_acp-sync._tcp": "Example Apple sync or Config Protocol.",
        
        // DNS & Time
        "_services._dns-sd._udp": "DNS-SD meta-service enumerates other Bonjour services.",
        "_time._udp": "Network time service.",
        "_timedate._udp": "Date/time sync service.",
        
        // Streaming & IoT
        "_googlecast._tcp": "Google Cast/Chromecast streaming device.",
        "_spotify-connect._tcp": "Spotify Connect streaming or device control.",
        "_bluetoothd2._tcp": "Bluetooth-related service for device connectivity.",
        "_hap._tcp": "HomeKit Accessory Protocol (IoT/home automation).",
        "_presence._tcp": "Presence detection or status service.",
        "_mqtt._tcp": "MQTT message broker or client service.",
        "_coap._udp": "Constrained Application Protocol over UDP.",
        
        // Catch-all
        "_tcpchat._tcp": "Example custom TCP chat or messaging service.",
        
        // Newly Added Services
        "_touch-able._tcp": "Interactive touch-based service for smart devices. (Newly added)",
        "_airpod._tcp": "Service related to AirPods connectivity and discovery. (Newly added)",
        "_teamviewer._tcp": "TeamViewer remote access service for remote support. (Newly added)",
        "_vnc._tcp": "VNC remote desktop service (alternative to _rfb._tcp). (Newly added)",
        "_sftp-ssh._tcp": "Secure File Transfer Protocol over SSH. (Newly added)",
        "_octoprint._tcp": "Service for 3D printer management (OctoPrint). (Newly added)",
        "_xbmc-jsonrpc._tcp": "JSON-RPC API for XBMC/Kodi media centers. (Newly added)",
        "_plexmediasvr._tcp": "Plex Media Server for streaming multimedia content. (Newly added)"
    ]
    
    var body: some View {
        NavigationView {
            VStack {
                if showRouterTip {
                    HStack {
                        Image(systemName: "info.circle")
                        Text("Tip: On your local network, you can detect devices by logging into your router.")
                            .font(.subheadline)
                        Spacer()
                        Button(action: {
                            showRouterTip = false
                        }) {
                            Image(systemName: "xmark.circle")
                        }
                    }
                    .padding()
                    .background(Color.yellow.opacity(0.2))
                    .cornerRadius(8)
                    .padding([.leading, .trailing])
                }
                
                VStack {
                    Text("Scan Duration: \(Int(scanDuration)) seconds")
                    Slider(value: $scanDuration, in: 5...60, step: 1)
                        .padding([.leading, .trailing])
                }
                
                Button(action: {
                    scanner.scanNetwork(duration: scanDuration)
                }) {
                    Text(scanner.isScanning ? "Scan in Progress" : "Scan Network")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(scanner.isScanning ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .disabled(scanner.isScanning)
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
            .navigationTitle("mDNSShark")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SpeedTestView()) {
                        Image(systemName: "speedometer")
                    }
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

