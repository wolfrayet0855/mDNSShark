
//
//  SpeedTestView.swift
//  mDNSShark
//
//  Created by user on 3/15/25.
//
//
//  SpeedTestView.swift
//  mDNSShark
//
//  Created by user on 3/15/25.
//

import SwiftUI
import Network

// MARK: - SpeedTestManager
/// An ObservableObject that manages network speed tests for download, upload, and latency.
class SpeedTestManager: ObservableObject {
    @Published var downloadSpeed: Double?
    @Published var uploadSpeed: Double?
    @Published var latency: Double?
    @Published var isTesting: Bool = false
    @Published var errorMessage: String?
    
    // MARK: - Test Endpoints
    /// List of Apple speed test hosts.
    private let appleSpeedTestHosts = [
        "speedtest-sjc1.apple.com",
        "speedtest-lax.apple.com",
        "speedtest-lhr.apple.com",
        "speedtest-syd.apple.com"
    ]
    
    /// Fallback CDN URL.
    private let fallbackTestURL = "https://ipv4.ikoula.testdebit.info/10M.iso"
    
    /// Final IP-based test (plain HTTP).
    /// Note: This endpoint requires an ATS exception in your Info.plist.
    private let ipTestURL = "http://1.1.1.1/"
    
    // MARK: - Public API
    /// Starts the concurrent speed tests.
    func startSpeedTest() {
        // Reset test results
        DispatchQueue.main.async {
            self.isTesting = true
            self.errorMessage = nil
            self.downloadSpeed = nil
            self.uploadSpeed = nil
            self.latency = nil
        }
        
        let group = DispatchGroup()
        
        // Download Test
        group.enter()
        performDownloadTest { [weak self] speed in
            DispatchQueue.main.async {
                self?.downloadSpeed = speed
            }
            group.leave()
        }
        
        // Upload Test
        group.enter()
        performUploadTest { [weak self] speed in
            DispatchQueue.main.async {
                self?.uploadSpeed = speed
            }
            group.leave()
        }
        
        // Latency Test
        group.enter()
        performLatencyTest { [weak self] latencyValue in
            DispatchQueue.main.async {
                self?.latency = latencyValue
            }
            group.leave()
        }
        
        group.notify(queue: .main) { [weak self] in
            self?.isTesting = false
        }
    }
    
    // MARK: - Download Test
    /// Performs a download test using multiple endpoints with fallback.
    private func performDownloadTest(completion: @escaping (Double?) -> Void) {
        tryDownload(
            hosts: appleSpeedTestHosts,
            fallbackURL: fallbackTestURL,
            ipFallbackURL: ipTestURL
        ) { [weak self] speed, error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.errorMessage = error
                }
                completion(nil)
            } else {
                completion(speed)
            }
        }
    }
    
    /// Recursively attempts to download from a list of hosts; if all fail, it uses fallback URLs.
    private func tryDownload(
        hosts: [String],
        fallbackURL: String,
        ipFallbackURL: String,
        completion: @escaping (Double?, String?) -> Void
    ) {
        // If no more Apple hosts left, try the fallback URL.
        guard !hosts.isEmpty else {
            guard let fallback = URL(string: fallbackURL) else {
                completion(nil, "Could not form fallback URL.")
                return
            }
            downloadFrom(url: fallback) { [weak self] speed, error in
                if let error = error {
                    print("Failed fallback domain with error: \(error). Trying IP-based test next...")
                    guard let ipURL = URL(string: ipFallbackURL) else {
                        completion(nil, "Could not form IP fallback URL.")
                        return
                    }
                    self?.downloadFrom(url: ipURL) { ipSpeed, ipError in
                        if let ipError = ipError {
                            completion(nil, ipError)
                        } else {
                            completion(ipSpeed, nil)
                        }
                    }
                } else {
                    completion(speed, nil)
                }
            }
            return
        }
        
        // Try the next Apple host.
        let currentHost = hosts[0]
        let remainingHosts = Array(hosts.dropFirst())
        
        guard let url = URL(string: "https://\(currentHost)/speedtest") else {
            // If URL formation fails, try the next host.
            tryDownload(hosts: remainingHosts,
                        fallbackURL: fallbackURL,
                        ipFallbackURL: ipFallbackURL,
                        completion: completion)
            return
        }
        
        downloadFrom(url: url) { [weak self] speed, error in
            if let error = error {
                print("Failed \(currentHost) with error: \(error). Trying next host...")
                self?.tryDownload(hosts: remainingHosts,
                                  fallbackURL: fallbackURL,
                                  ipFallbackURL: ipFallbackURL,
                                  completion: completion)
            } else {
                completion(speed, nil)
            }
        }
    }
    
    /// Downloads data from the specified URL and calculates download speed in Mbps.
    private func downloadFrom(url: URL, completion: @escaping (Double?, String?) -> Void) {
        let startTime = CFAbsoluteTimeGetCurrent()
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            let endTime = CFAbsoluteTimeGetCurrent()
            if let error = error {
                let errorMsg = "Download from \(url.host ?? url.absoluteString) failed: \(error.localizedDescription)"
                completion(nil, errorMsg)
                return
            }
            guard let data = data, !data.isEmpty else {
                let errorMsg = "No data received from \(url.host ?? url.absoluteString)"
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
    /// Performs an upload test by sending data to a testing endpoint.
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
    /// Measures latency by establishing a TCP connection to apple.com.
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

// MARK: - SpeedTestView
/// A SwiftUI view that displays speed test results and a control to start testing.
struct SpeedTestView: View {
    @StateObject private var manager = SpeedTestManager()
    
    var body: some View {
        Form {
            Section(header: Text("Speed Test Results")) {
                HStack {
                    Text("Download Speed:")
                    Spacer()
                    if let speed = manager.downloadSpeed {
                        Text(String(format: "%.2f Mbps", speed))
                    } else {
                        Text("N/A")
                    }
                }
                HStack {
                    Text("Upload Speed:")
                    Spacer()
                    if let speed = manager.uploadSpeed {
                        Text(String(format: "%.2f Mbps", speed))
                    } else {
                        Text("N/A")
                    }
                }
                HStack {
                    Text("Latency:")
                    Spacer()
                    if let latency = manager.latency {
                        Text(String(format: "%.0f ms", latency))
                    } else {
                        Text("N/A")
                    }
                }
            }
            
            if let errorMessage = manager.errorMessage {
                Section {
                    Text("Error: \(errorMessage)")
                        .foregroundColor(.red)
                }
            }
            
            Section {
                if manager.isTesting {
                    HStack {
                        Spacer()
                        ProgressView("Testing...")
                        Spacer()
                    }
                }
                Button(action: {
                    manager.startSpeedTest()
                }) {
                    Text("Start Speed Test")
                        .frame(maxWidth: .infinity)
                }
                .disabled(manager.isTesting)
            }
        }
        .navigationTitle("Speed Test")
    }
}

// MARK: - Preview
struct SpeedTestView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SpeedTestView()
        }
    }
}
