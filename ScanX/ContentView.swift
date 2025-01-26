import SwiftUI

struct ContentView: View {
    @StateObject private var scanner = NetworkScanner()

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Scan Button
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

                // Device List
                if scanner.devices.isEmpty {
                    Text("No devices found. Tap 'Scan Network' to start.")
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    List(scanner.devices) { device in
                        HStack {
                            Text(device.ipAddress)
                            Spacer()
                            Text(device.isActive ? "Active" : "Inactive")
                                .foregroundColor(device.isActive ? .green : .red)
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .padding()
            .navigationTitle("Network Scanner")
        }
    }
}

