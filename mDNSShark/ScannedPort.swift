//
//  PortScannerView.swift
//  mDNSShark
//
//  Created by user on 4/5/25.
//  Updated for configurable timeout and banner retrieval per port.
//  Feature: TCP Port Scanner for Penetration Testing
//

import SwiftUI
import Network

// Represents an open port and, if available, its banner.
struct ScannedPort: Identifiable {
    var id: Int { port }
    let port: Int
    let banner: String?
}

// A simple port scanner that uses NWConnection to check TCP ports and grab banner info.
class PortScanner: ObservableObject {
    @Published var openPorts: [ScannedPort] = []
    @Published var isScanning: Bool = false
    
    // A helper class to ensure a single completion for each connection.
    class Flag {
        private var completed = false
        private let queue = DispatchQueue(label: "FlagQueue")
        
        // Returns true only the first time it's called.
        func setCompleted() -> Bool {
            return queue.sync {
                if !completed {
                    completed = true
                    return true
                }
                return false
            }
        }
    }
    
    /// Scans the given IP address from startPort to endPort, applying a per-port timeout.
    func scan(ip: String, startPort: Int, endPort: Int, timeout: TimeInterval) {
        guard startPort > 0, endPort > 0, startPort <= endPort else { return }
        DispatchQueue.main.async {
            self.openPorts = []
            self.isScanning = true
        }
        
        let queue = DispatchQueue.global(qos: .userInitiated)
        let group = DispatchGroup()
        
        for port in startPort...endPort {
            group.enter()
            let nwPort = NWEndpoint.Port(integerLiteral: NWEndpoint.Port.IntegerLiteralType(port))
            let connection = NWConnection(host: NWEndpoint.Host(ip), port: nwPort, using: .tcp)
            
            let flag = Flag()
            
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if flag.setCompleted() {
                        // Attempt to grab banner info from the open connection.
                        connection.receive(minimumIncompleteLength: 1, maximumLength: 256) { data, _, _, _ in
                            var banner: String? = nil
                            if let data = data, !data.isEmpty {
                                banner = String(data: data, encoding: .utf8)
                            }
                            DispatchQueue.main.async {
                                self.openPorts.append(ScannedPort(port: port, banner: banner))
                            }
                            connection.cancel()
                            group.leave()
                        }
                    }
                case .failed(_):
                    if flag.setCompleted() {
                        connection.cancel()
                        group.leave()
                    }
                default:
                    break
                }
            }
            
            connection.start(queue: queue)
            
            // Enforce per-port timeout
            queue.asyncAfter(deadline: .now() + timeout) {
                if flag.setCompleted() {
                    connection.cancel()
                    group.leave()
                }
            }
        }
        
        group.notify(queue: DispatchQueue.main) {
            self.isScanning = false
        }
    }
}

struct PortScannerView: View {
    @StateObject private var scanner = PortScanner()
    @State private var ipAddress: String = ""
    @State private var startPort: String = "20"
    @State private var endPort: String = "1024"
    @State private var timeout: String = "3" // Timeout in seconds per port scan
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Target IP Address")) {
                    TextField("IP Address", text: $ipAddress)
                        .keyboardType(.decimalPad)
                }
                
                Section(header: Text("Port Range")) {
                    HStack {
                        TextField("Start Port", text: $startPort)
                            .keyboardType(.numberPad)
                        Text("to")
                        TextField("End Port", text: $endPort)
                            .keyboardType(.numberPad)
                    }
                }
                
                Section(header: Text("Scan Timeout (seconds)")) {
                    TextField("Timeout", text: $timeout)
                        .keyboardType(.decimalPad)
                }
                
                Section {
                    Button(action: {
                        guard let start = Int(startPort),
                              let end = Int(endPort),
                              let timeoutVal = Double(timeout),
                              !ipAddress.isEmpty else { return }
                        scanner.scan(ip: ipAddress, startPort: start, endPort: end, timeout: timeoutVal)
                    }) {
                        HStack {
                            if scanner.isScanning {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            }
                            Text(scanner.isScanning ? "Scanning..." : "Start Port Scan")
                        }
                    }
                    .disabled(scanner.isScanning || ipAddress.isEmpty)
                }
                
                if !scanner.openPorts.isEmpty {
                    Section(header: Text("Open Ports")) {
                        List(scanner.openPorts.sorted(by: { $0.port < $1.port })) { scannedPort in
                            VStack(alignment: .leading) {
                                Text("Port \(scannedPort.port) is open")
                                    .font(.headline)
                                if let banner = scannedPort.banner, !banner.isEmpty {
                                    Text("Banner: \(banner)")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                } else {
                                    Text("No banner retrieved")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("TCP Port Scanner")
        }
    }
}

struct PortScannerView_Previews: PreviewProvider {
    static var previews: some View {
        PortScannerView()
    }
}
