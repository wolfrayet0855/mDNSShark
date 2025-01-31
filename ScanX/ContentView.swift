import SwiftUI

struct ContentView: View {
    @StateObject private var scanner = NetworkScanner()

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Button(action: {
                    print("🔵 [UI] 'Scan Network' button tapped")
                    scanner.scanNetwork()
                }) {
                    if scanner.isScanning {
                        Text("Scanning...")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    } else {
                        Text("Scan Network")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
                .disabled(scanner.isScanning)

                if scanner.devices.isEmpty {
                    Text("No active devices found. Tap 'Scan Network' to start.")
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    List(scanner.devices) { device in
                        HStack {
                            Text(device.ipAddress)
                            Spacer()
                            if let port = device.openPort {
                                Text("Port \(port) open")
                                    .foregroundColor(.green)
                            } else if device.icmpResponded {
                                Text("ICMP ping")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
            .padding()
            .navigationTitle("Network Scanner")
        }
    }
}
