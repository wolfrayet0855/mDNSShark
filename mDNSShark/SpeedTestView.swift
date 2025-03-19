
//  SpeedTestView.swift
//  mDNSShark
//
import SwiftUI
import Network
import Charts

// MARK: - An actor for accumulating byte counts in a concurrency-safe way
actor ByteAccumulator {
    private(set) var total: Int = 0
    
    func add(_ bytes: Int) {
        total += bytes
    }
}

// MARK: - SpeedTestManager using async/await for Timed Concurrency
class SpeedTestManager: ObservableObject {
    @Published var isTesting: Bool = false
    @Published var downloadSpeedMbps: Double?
    @Published var uploadSpeedMbps: Double?
    @Published var latencyMs: Double?
    @Published var errorMessage: String?

    // Test file endpoint on a robust provider.
    private let testFileURL = URL(string: "https://proof.ovh.net/files/10Mb.dat")!
    
    // Configuration
    private let downloadConcurrency = 8
    private let uploadConcurrency = 8
    private let latencyIterations = 5
    
    // Timed test duration (seconds). Adjust for more accuracy.
    private let testDuration: TimeInterval = 10

    func startSpeedTest() {
        Task {
            do {
                await MainActor.run {
                    self.isTesting = true
                    self.errorMessage = nil
                    self.downloadSpeedMbps = nil
                    self.uploadSpeedMbps = nil
                    self.latencyMs = nil
                }
                
                // 1) Measure idle latency FIRST (no load)
                let latencyResult = try await performMultipleLatencyTests()
                
                // 2) Then do the big timed download
                let downloadResult = try await performTimedConcurrentDownload()
                
                // 3) Then do the big timed upload
                let uploadResult = try await performTimedConcurrentUpload()
                
                // Update UI
                await MainActor.run {
                    self.latencyMs = latencyResult
                    self.downloadSpeedMbps = downloadResult
                    self.uploadSpeedMbps = uploadResult
                    self.isTesting = false
                }
                
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isTesting = false
                }
            }
        }
    }
}

// MARK: - Timed Download / Upload / Latency Methods
extension SpeedTestManager {
    
    // MARK: Timed Download Test
    private func performTimedConcurrentDownload() async throws -> Double {
        let startTime = CFAbsoluteTimeGetCurrent()
        let endTime = startTime + testDuration
        
        // Use an actor to safely accumulate byte counts from multiple tasks.
        let accumulator = ByteAccumulator()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<downloadConcurrency {
                group.addTask {
                    while CFAbsoluteTimeGetCurrent() < endTime {
                        do {
                            let (data, _) = try await URLSession.shared.data(from: self.testFileURL)
                            await accumulator.add(data.count)
                        } catch {
                            // In a production app, you might retry or handle errors here
                            break
                        }
                    }
                }
            }
            try await group.waitForAll()
        }
        
        let actualEndTime = CFAbsoluteTimeGetCurrent()
        let elapsed = actualEndTime - startTime
        
        // Safely read total bytes from the actor
        let totalBytesTransferred = await accumulator.total
        let bits = Double(totalBytesTransferred) * 8.0
        let mbps = bits / elapsed / 1_000_000.0
        return mbps
    }
    
    // MARK: Timed Upload Test
    private func performTimedConcurrentUpload() async throws -> Double {
        let startTime = CFAbsoluteTimeGetCurrent()
        let endTime = startTime + testDuration
        
        let accumulator = ByteAccumulator()

        // Prepare 2 MB payload for each POST
        let dataSize = 2 * 1024 * 1024
        let uploadData = Data(count: dataSize)
        var request = URLRequest(url: testFileURL)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<uploadConcurrency {
                group.addTask {
                    while CFAbsoluteTimeGetCurrent() < endTime {
                        do {
                            _ = try await URLSession.shared.upload(for: request, from: uploadData)
                            await accumulator.add(dataSize)
                        } catch {
                            break
                        }
                    }
                }
            }
            try await group.waitForAll()
        }
        
        let actualEndTime = CFAbsoluteTimeGetCurrent()
        let elapsed = actualEndTime - startTime
        
        let totalBytesTransferred = await accumulator.total
        let bits = Double(totalBytesTransferred) * 8.0
        let mbps = bits / elapsed / 1_000_000.0
        return mbps
    }
    
    // MARK: Latency Test (Median of Several HEAD requests)
    private func performMultipleLatencyTests() async throws -> Double {
        let latencies = try await withThrowingTaskGroup(of: Double.self) { group -> [Double] in
            for _ in 0..<latencyIterations {
                group.addTask {
                    var request = URLRequest(url: self.testFileURL)
                    request.httpMethod = "HEAD"
                    let start = CFAbsoluteTimeGetCurrent()
                    _ = try await URLSession.shared.data(for: request)
                    let end = CFAbsoluteTimeGetCurrent()
                    return (end - start) * 1000.0 // Convert to ms
                }
            }
            var results = [Double]()
            for try await latency in group {
                results.append(latency)
            }
            return results
        }
        
        // Use median to reduce outlier impact
        let sorted = latencies.sorted()
        let median = sorted[latencies.count / 2]
        return median
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
    @State private var showInfoBanner: Bool = true

    var body: some View {
        VStack {
            // Info Banner
            if showInfoBanner {
                HStack {
                    Image(systemName: "info.circle")
                    Text("Latency is measured first (idle), then timed concurrency for throughput. This prevents HEAD from competing with big transfers.")
                        .font(.subheadline)
                    Spacer()
                    Button {
                        showInfoBanner = false
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                }
                .padding()
                .background(Color.yellow.opacity(0.2))
                .cornerRadius(8)
                .padding(.horizontal)
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
                        Text("HTTP Round-Trip Latency (HEAD)")
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
    
    private func buildDataPoints() -> [SpeedChartData]? {
        var points = [SpeedChartData]()
        if let dl = manager.downloadSpeedMbps {
            points.append(SpeedChartData(label: "Download", value: dl))
        }
        if let ul = manager.uploadSpeedMbps {
            points.append(SpeedChartData(label: "Upload", value: ul))
        }
        return points.isEmpty ? nil : points
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
