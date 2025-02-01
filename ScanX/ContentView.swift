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

                if scanner.isScanning {
                    ProgressView()
                        .progressViewStyle(LinearProgressViewStyle())
                        .padding(.horizontal)
                }

                if scanner.devices.isEmpty && !scanner.isScanning {
                    Text("No active devices found. Tap 'Scan Network' to start.")
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding()
                } else if !scanner.devices.isEmpty {
                    List(scanner.devices) { device in
                        HStack(spacing: 12) {
                            Image(systemName: device.deviceTypeIcon())
                                .foregroundColor(.accentColor)
                                .imageScale(.large)
                            Text(device.identifier)
                                .font(.headline)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Network Scanner")
        }
    }
}

