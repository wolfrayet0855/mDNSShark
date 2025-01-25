import SwiftUI

struct ContentView: View {
    @StateObject private var scanner = NetworkScanner()

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Scan Button
                Button(action: {
                    scanner.scanNetwork()
                }) {
                    Text("Scan Network")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.horizontal)

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

