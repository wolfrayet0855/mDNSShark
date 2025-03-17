
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

    // Using 1.1.1.1 for demonstration. (Minimal responses, not suitable for big file tests)
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

        // 3) Latency (remains available in the textual results)
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
    let label: String  // e.g. "Download", "Upload"
    let value: Double  // numeric value in Mbps
}

// MARK: - SpeedTestView
struct SpeedTestView: View {
    @StateObject private var manager = SpeedTestManager()
    @State private var showCloudflareTip: Bool = true  // Controls showing/hiding the info banner

    var body: some View {
        VStack {
            // Info Banner
            if showCloudflareTip {
                HStack {
                    Image(systemName: "info.circle")
                    Text("Using Cloudflare's DNS server (1.1.1.1). Not suitable for large file downloads.")
                        .font(.subheadline)
                    Spacer()
                    Button(action: {
                        showCloudflareTip = false
                    }) {
                        Image(systemName: "xmark.circle")
                    }
                }
                .padding()
                .background(Color.yellow.opacity(0.2))
                .cornerRadius(8)
                .padding([.leading, .trailing])
            }

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

                // Horizontal Bar Chart showing Download and Upload speeds with colored bars.
                if let dataPoints = buildDataPoints() {
                    Section(header: Text("Bar Chart (Final)")) {
                        Chart(dataPoints) {
                            BarMark(
                                x: .value("Value", $0.value),
                                y: .value("Test", $0.label)
                            )
                            .foregroundStyle(colorForSpeed($0.value))
                        }
                        .frame(height: 200)
                        .padding(.vertical)
                        .chartXAxis {
                            AxisMarks(position: .bottom) { value in
                                if let doubleValue = value.as(Double.self) {
                                    AxisValueLabel("\(doubleValue, specifier: "%.0f") Mbps")
                                }
                                AxisTick()
                                AxisGridLine()
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading)
                        }
                    }
                }
            }
        }
        .navigationTitle("Speed Test")
    }

    /// Build data points for the bar chart using only download and upload speeds.
    private func buildDataPoints() -> [SpeedChartData]? {
        if manager.downloadSpeedMbps == nil && manager.uploadSpeedMbps == nil {
            return nil
        }
        var points = [SpeedChartData]()
        if let dl = manager.downloadSpeedMbps {
            points.append(SpeedChartData(label: "Download", value: dl))
        }
        if let ul = manager.uploadSpeedMbps {
            points.append(SpeedChartData(label: "Upload", value: ul))
        }
        return points
    }
    
    /// Determines the bar color based on speed: red for <10 Mbps, yellow for <50 Mbps, and green otherwise.
    private func colorForSpeed(_ speed: Double) -> Color {
        if speed < 10 {
            return .red
        } else if speed < 50 {
            return .yellow
        } else {
            return .green
        }
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
