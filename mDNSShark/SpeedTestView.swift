import SwiftUI
import Network

struct SpeedTestView: View {
    @State private var downloadSpeed: Double?
    @State private var uploadSpeed: Double?
    @State private var latency: Double?
    @State private var isTesting: Bool = false
    @State private var errorMessage: String?

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
    
    private func performDownloadTest(completion: @escaping (Double?) -> Void) {
        guard let url = URL(string: "https://speed.hetzner.de/10MB.bin") else {
            completion(nil)
            return
        }
        let startTime = CFAbsoluteTimeGetCurrent()
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            let endTime = CFAbsoluteTimeGetCurrent()
            if let error = error {
                print("Download test error: \(error.localizedDescription)")
                completion(nil)
                return
            }
            guard let data = data else {
                completion(nil)
                return
            }
            let elapsed = endTime - startTime
            let bytes = Double(data.count)
            let bits = bytes * 8.0
            let speedBps = bits / elapsed
            let speedMbps = speedBps / 1_000_000
            completion(speedMbps)
        }
        task.resume()
    }
    
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
    
    private func performLatencyTest(completion: @escaping (Double?) -> Void) {
        let host = NWEndpoint.Host("apple.com")
        guard let port = NWEndpoint.Port(integerLiteral: 80) else {
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
                connection.cancel()
                completion(nil)
            default:
                break
            }
        }
        
        connection.start(queue: DispatchQueue.global())
    }
}

struct SpeedTestView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SpeedTestView()
        }
    }
}
