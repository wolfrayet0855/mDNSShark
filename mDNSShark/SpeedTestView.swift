
//
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

    // Updated URL for download, upload, and latency tests.
    private let testFileURL = URL(string: "https://proof.ovh.net/files/10Mb.dat")!
    
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

        // 1) Download Test
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

        // 2) Upload Test
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

        // 3) Latency Test (HEAD Request)
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

        // When all tests finish, mark testing as done.
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
        let task = URLSession.shared.dataTask(with: testFileURL) { data, response, error in
            let endTime = CFAbsoluteTimeGetCurrent()
            if let error = error {
                completion(nil, error.localizedDescription)
                return
            }
            guard let data = data, !data.isEmpty else {
                completion(nil, "No data received from test file.")
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
        // Prepare a 2MB data payload.
        let dataSize = 2 * 1024 * 1024
        let uploadData = Data(count: dataSize)
        var request = URLRequest(url: testFileURL)
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

    // MARK: Latency Test using HEAD Request
    private func performLatencyTest(completion: @escaping (Double?, String?) -> Void) {
        var request = URLRequest(url: testFileURL)
        request.httpMethod = "HEAD"
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let task = URLSession.shared.dataTask(with: request) { _, _, error in
            let endTime = CFAbsoluteTimeGetCurrent()
            let measuredLatency = (endTime - startTime) * 1000.0  // Convert seconds to milliseconds
            
            DispatchQueue.main.async {
                if let error = error {
                    completion(nil, error.localizedDescription)
                } else {
                    completion(measuredLatency, nil)
                }
            }
        }
        
        task.resume()
    }
}

// MARK: - Data Model for Chart
struct SpeedChartData: Identifiable {
    let id = UUID()
    let label: String  // e.g. "Download", "Upload"
    let value: Double  // Numeric value in Mbps
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
                    Text("Using OVH test file for download/upload tests. Latency measured via HEAD request.")
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
                
                // Horizontal Bar Chart showing Download and Upload speeds.
                if let dataPoints = buildDataPoints() {
                    Section(header: Text("Bar Chart (Final)")) {
                        Chart(dataPoints) {
                            BarMark(
                                x: .value("Value", $0.value),
                                y: .value("Test", $0.label)
                            )
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
}

// MARK: - Preview
struct SpeedTestView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SpeedTestView()
        }
    }
}
