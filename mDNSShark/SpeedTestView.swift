//
//  SpeedTestView.swift
//  mDNSShark
//
//  Created by user on 3/15/25.
//

import SwiftUI
import Network

struct SpeedTestView: View {
    @State private var downloadSpeed: Double?
    @State private var uploadSpeed: Double?
    @State private var latency: Double?
    @State private var isTesting: Bool = false
    @State private var errorMessage: String?

    // Multiple Apple speed test domains
    private let appleSpeedTestHosts = [
        "speedtest-sjc1.apple.com",
        "speedtest-lax.apple.com",
        "speedtest-lhr.apple.com",
        "speedtest-syd.apple.com"
    ]
    
    // Fallback CDN
    private let fallbackTestURL = "https://ipv4.ikoula.testdebit.info/10M.iso"
    
    // Final IP-based test (plain HTTP).
    // If this also fails, your network likely blocks all traffic or has no route.
    private let ipTestURL = "http://1.1.1.1/"
    
    var body: some View {
        Form {
            Section(header: Text("Speed Test Results")) {
                HStack {
                    Text("Download Speed:")
                    Spacer()
                    if let speed = downloadSpeed {
                        Text(String(format: "%.2f Mbps", speed))
                    } else {
                        Text("N/A")
                    }
                }
                HStack {
                    Text("Upload Speed:")
                    Spacer()
                    if let speed = uploadSpeed {
                        Text(String(format: "%.2f Mbps", speed))
                    } else {
                        Text("N/A")
                    }
                }
                HStack {
                    Text("Latency:")
                    Spacer()
                    if let latency = latency {
                        Text(String(format: "%.0f ms", latency))
                    } else {
                        Text("N/A")
                    }
                }
            }
            
            if let errorMessage = errorMessage {
                Section {
                    Text("Error: \(errorMessage)")
                        .foregroundColor(.red)
                }
            }
            
            Section {
                if isTesting {
                    HStack {
                        Spacer()
                        ProgressView("Testing...")
                        Spacer()
                    }
                }
                Button(action: {
                    startSpeedTest()
                }) {
                    Text("Start Speed Test")
                        .frame(maxWidth: .infinity)
                }
                .disabled(isTesting)
            }
        }
        .navigationTitle("Speed Test")
    }
    
    private func startSpeedTest() {
        isTesting = true
        errorMessage = nil
        downloadSpeed = nil
        uploadSpeed = nil
        latency = nil
        
        let group = DispatchGroup()
        
        group.enter()
        performDownloadTest { speed in
            DispatchQueue.main.async {
                self.downloadSpeed = speed
            }
            group.leave()
        }
        
        group.enter()
        performUploadTest { speed in
            DispatchQueue.main.async {
                self.uploadSpeed = speed
            }
            group.leave()
        }
        
        group.enter()
        performLatencyTest { latencyValue in
            DispatchQueue.main.async {
                self.latency = latencyValue
            }
            group.leave()
        }
        
        group.notify(queue: .main) {
            self.isTesting = false
        }
    }
    
    // MARK: - Multi-Domain Download Test with IP fallback
    private func performDownloadTest(completion: @escaping (Double?) -> Void) {
        tryDownload(
            hosts: appleSpeedTestHosts,
            fallbackURL: fallbackTestURL,
            ipFallbackURL: ipTestURL
        ) { speed, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = error
                }
                completion(nil)
            } else {
                completion(speed)
            }
        }
    }
    
    private func tryDownload(
        hosts: [String],
        fallbackURL: String,
        ipFallbackURL: String,
        completion: @escaping (Double?, String?) -> Void
    ) {
        // If no more Apple hosts left, try fallback domain
        guard !hosts.isEmpty else {
            // Try the fallback domain
            guard let fallback = URL(string: fallbackURL) else {
                completion(nil, "Could not form fallback URL.")
                return
            }
            downloadFrom(url: fallback) { speed, error in
                if let error = error {
                    print("Failed fallback domain with error: \(error). Trying IP next...")
                    // Next, try IP-based request (requires ATS exception)
                    guard let ipURL = URL(string: ipFallbackURL) else {
                        completion(nil, "Could not form IP fallback URL.")
                        return
                    }
                    downloadFrom(url: ipURL) { ipSpeed, ipError in
                        if let ipError = ipError {
                            // Everything failed
                            completion(nil, ipError)
                        } else {
                            completion(ipSpeed, nil)
                        }
                    }
                } else {
                    // Fallback domain succeeded
                    completion(speed, nil)
                }
            }
            return
        }
        
        // Otherwise, try the next Apple domain
        let currentHost = hosts[0]
        let remainingHosts = Array(hosts.dropFirst())
        
        guard let url = URL(string: "https://\(currentHost)/speedtest") else {
            // If URL can't form, skip to next
            tryDownload(
                hosts: remainingHosts,
                fallbackURL: fallbackURL,
                ipFallbackURL: ipFallbackURL,
                completion: completion
            )
            return
        }
        
        downloadFrom(url: url) { speed, error in
            if let error = error {
                print("Failed \(currentHost) with error: \(error). Trying next host...")
                tryDownload(
                    hosts: remainingHosts,
                    fallbackURL: fallbackURL,
                    ipFallbackURL: ipFallbackURL,
                    completion: completion
                )
            } else {
                // Success
                completion(speed, nil)
            }
        }
    }
    
    private func downloadFrom(url: URL, completion: @escaping (Double?, String?) -> Void) {
        let startTime = CFAbsoluteTimeGetCurrent()
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            let endTime = CFAbsoluteTimeGetCurrent()
            if let error = error {
                let errorMsg = "Download from \(url.host ?? url.absoluteString) failed: \(error.localizedDescription)"
                completion(nil, errorMsg)
                return
            }
            guard let data = data else {
                let errorMsg = "No data from \(url.host ?? url.absoluteString)"
                completion(nil, errorMsg)
                return
            }
            let elapsed = endTime - startTime
            let bytes = Double(data.count)
            let bits = bytes * 8.0
            let speedBps = bits / elapsed
            let speedMbps = speedBps / 1_000_000
            completion(speedMbps, nil)
        }
        task.resume()
    }
    
    // MARK: - Upload Test
    private func performUploadTest(completion: @escaping (Double?) -> Void) {
        guard let url = URL(string: "https://httpbin.org/post") else {
            completion(nil)
            return
        }
        let dataSize = 5 * 1024 * 1024 // 5 MB
        let uploadData = Data(count: dataSize)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        
        let startTime = CFAbsoluteTimeGetCurrent()
        let task = URLSession.shared.uploadTask(with: request, from: uploadData) { data, response, error in
            let endTime = CFAbsoluteTimeGetCurrent()
            if let error = error {
                print("Upload test error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                }
                completion(nil)
                return
            }
            let elapsed = endTime - startTime
            let bytes = Double(dataSize)
            let bits = bytes * 8.0
            let speedBps = bits / elapsed
            let speedMbps = speedBps / 1_000_000
            completion(speedMbps)
        }
        task.resume()
    }
    
    // MARK: - Latency Test
    private func performLatencyTest(completion: @escaping (Double?) -> Void) {
        let host = NWEndpoint.Host("apple.com")
        guard let port = NWEndpoint.Port(rawValue: 80) else {
            completion(nil)
            return
        }
        let parameters = NWParameters.tcp
        let connection = NWConnection(host: host, port: port, using: parameters)
        
        let startTime = CFAbsoluteTimeGetCurrent()
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                let endTime = CFAbsoluteTimeGetCurrent()
                let latencySeconds = endTime - startTime
                let latencyMs = latencySeconds * 1000.0
                connection.cancel()
                completion(latencyMs)
            case .failed(let error):
                print("Latency test failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                }
                connection.cancel()
                completion(nil)
            default:
                break
            }
        }
        
        connection.start(queue: DispatchQueue.global())
    }
}
