
//
//  SpeedTestView.swift
//  mDNSShark
////
//  SpeedTestView.swift
//  mDNSShark
//
import SwiftUI
import Network
import Charts

// MARK: - SpeedTestManager
class SpeedTestManager: ObservableObject {
    @Published var isTesting: Bool = false
    @Published var downloadSpeedMbps: Double?
    @Published var uploadSpeedMbps: Double?
    @Published var latencyMs: Double?
    @Published var errorMessage: String?

    // Using 1.1.1.1 for demonstration.
    // In reality, 1.1.1.1 is a DNS server that won't return large files.
    private let downloadTestURL = URL(string: "https://1.1.1.1")!
    private let uploadTestURL   = URL(string: "https://1.1.1.1")!
    private let pingHost        = NWEndpoint.Host("1.1.1.1")
    private let pingPort        = NWEndpoint.Port(rawValue: 53)!

    /// Start all tests in parallel using a DispatchGroup.
    func startSpeedTest() {
        DispatchQueue.main.async {
            self.isTesting = true
            self.errorMessage = nil
            self.downloadSpeedMbps = nil
            self.uploadSpeedMbps = nil
            self.latencyMs = nil
        }

        let group = DispatchGroup()

        // 1) Download
        group.enter()
        performDownloadTest { [weak self] speed, err in
            DispatchQueue.main.async {
                if let err = err {
                    self?.errorMessage = "Download error: \(err)"
                } else {
                    self?.downloadSpeedMbps = speed
                }
            }
            group.leave()
        }

        // 2) Upload
        group.enter()
        performUploadTest { [weak self] speed, err in
            DispatchQueue.main.async {
                if let err = err {
                    self?.errorMessage = "Upload error: \(err)"
                } else {
                    self?.uploadSpeedMbps = speed
                }
            }
            group.leave()
        }

        // 3) Latency
        group.enter()
        performLatencyTest { [weak self] latency, err in
            DispatchQueue.main.async {
                if let err = err {
                    self?.errorMessage = "Latency error: \(err)"
                } else {
                    self?.latencyMs = latency
                }
            }
            group.leave()
        }

        // When all finish
        group.notify(queue: .main) { [weak self] in
            self?.isTesting = false
        }
    }
}

// MARK: - Internal test methods
extension SpeedTestManager {

    // MARK: Download Test
    private func performDownloadTest(completion: @escaping (Double?, String?) -> Void) {
        let startTime = CFAbsoluteTimeGetCurrent()
        let task = URLSession.shared.dataTask(with: downloadTestURL) { data, response, error in
            let endTime = CFAbsoluteTimeGetCurrent()

            if let error = error {
                completion(nil, error.localizedDescription)
                return
            }
            guard let data = data, !data.isEmpty else {
                completion(nil, "No data received from 1.1.1.1.")
                return
            }

            // Calculate approximate speed
            let elapsed = endTime - startTime
            let bytes = Double(data.count)
            let bits = bytes * 8.0
            let bps = bits / elapsed
            let mbps = bps / 1_000_000.0
            completion(mbps, nil)
        }
        task.resume()
    }

    // MARK: Upload Test
    private func performUploadTest(completion: @escaping (Double?, String?) -> Void) {
        // Attempting to POST ~2 MB of data to 1.1.1.1
        // In reality, 1.1.1.1 may not handle large POST data.
        let dataSize = 2 * 1024 * 1024
        let uploadData = Data(count: dataSize)

        var request = URLRequest(url: uploadTestURL)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let startTime = CFAbsoluteTimeGetCurrent()
        let task = URLSession.shared.uploadTask(with: request, from: uploadData) { _, _, error in
            let endTime = CFAbsoluteTimeGetCurrent()

            if let error = error {
                completion(nil, error.localizedDescription)
                return
            }

            let elapsed = endTime - startTime
            let bytes = Double(dataSize)
            let bits = bytes * 8.0
            let bps = bits / elapsed
            let mbps = bps / 1_000_000.0
            completion(mbps, nil)
        }
        task.resume()
    }

    // MARK: Latency (Ping)
    private func performLatencyTest(completion: @escaping (Double?, String?) -> Void) {
        let connection = NWConnection(host: pingHost, port: pingPort, using: .udp)
        let startTime = CFAbsoluteTimeGetCurrent()
        connection.stateUpdateHandler = { newState in
            switch newState {
            case .ready:
                let endTime = CFAbsoluteTimeGetCurrent()
                let elapsedMs = (endTime - startTime) * 1000.0
                connection.cancel()
                completion(elapsedMs, nil)
            case .failed(let error):
                connection.cancel()
                completion(nil, error.localizedDescription)
            default:
                break
            }
        }
        connection.start(queue: .global())
    }
}

// MARK: - Data Model for Chart
struct SpeedChartData: Identifiable {
    let id = UUID()
    let label: String  // e.g. "Download", "Upload", "Latency"
    let value: Double  // numeric value (Mbps or ms)
}

// MARK: - SpeedTestView (Bar Chart)
struct SpeedTestView: View {
    @StateObject private var manager = SpeedTestManager()

    var body: some View {
        VStack {
            if manager.isTesting {
                ProgressView("Testing…")
                    .padding()
            }

            Button("Start Speed Test") {
                manager.startSpeedTest()
            }
            .font(.headline)
            .padding()
            .disabled(manager.isTesting)

            if let error = manager.errorMessage {
                Text("Error: \(error)")
                    .foregroundColor(.red)
                    .padding()
            }

            List {
                Section(header: Text("Results")) {
                    HStack {
                        Text("Download Speed")
                        Spacer()
                        Text(manager.downloadSpeedMbps != nil
                             ? String(format: "%.2f Mbps", manager.downloadSpeedMbps!)
                             : "N/A")
                    }
                    HStack {
                        Text("Upload Speed")
                        Spacer()
                        Text(manager.uploadSpeedMbps != nil
                             ? String(format: "%.2f Mbps", manager.uploadSpeedMbps!)
                             : "N/A")
                    }
                    HStack {
                        Text("Latency")
                        Spacer()
                        Text(manager.latencyMs != nil
                             ? String(format: "%.0f ms", manager.latencyMs!)
                             : "N/A")
                    }
                }

                if let dataPoints = buildDataPoints() {
                    Section(header: Text("Bar Chart (Final)")) {
                        Chart(dataPoints) {
                            BarMark(
                                x: .value("Test", $0.label),
                                y: .value("Value", $0.value)
                            )
                        }
                        .frame(height: 200)
                        .padding(.vertical)
                        .chartYAxis {
                            AxisMarks(position: .leading)
                        }
                        .chartXAxis {
                            AxisMarks(position: .bottom)
                        }

                        // NOTE: Download/Upload are in Mbps, Latency is in ms.
                        // They share the same axis here, which can be misleading.
                    }
                }
            }
        }
        .navigationTitle("Speed Test")
    }

    /// Build data points for the bar chart.
    private func buildDataPoints() -> [SpeedChartData]? {
        if manager.downloadSpeedMbps == nil &&
           manager.uploadSpeedMbps == nil &&
           manager.latencyMs == nil {
            return nil
        }

        var points = [SpeedChartData]()
        if let dl = manager.downloadSpeedMbps {
            points.append(SpeedChartData(label: "Download", value: dl))
        }
        if let ul = manager.uploadSpeedMbps {
            points.append(SpeedChartData(label: "Upload", value: ul))
        }
        if let lat = manager.latencyMs {
            points.append(SpeedChartData(label: "Latency (ms)", value: lat))
        }
        return points
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

