//
//  PacketCaptureManager.swift
//  mDNSShark
//
//  Created by user on 4/10/25.
//


//
//  PacketCaptureManager.swift
//  mDNSShark
//
//  Created by user on 3/19/25.
//

import Foundation
import Combine

class PacketCaptureManager: ObservableObject {
    @Published var packets: [PacketModel] = []
    @Published var isCapturing: Bool = false
    
    private var timer: Timer?
    private var frameCounter = 1
    
    // Start simulating incoming packets
    func startCaptureSimulation() {
        isCapturing = true
        frameCounter = 1
        packets = []
        
        // For demonstration, generate a new packet every ~1 second
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.generateRandomPacket()
        }
    }
    
    // Stop capturing
    func stopCapture() {
        isCapturing = false
        timer?.invalidate()
        timer = nil
    }
    
    private func generateRandomPacket() {
        let sampleProtocols = ["TCP", "UDP", "MDNS", "HTTP", "DNS", "TLSv1.2"]
        let sampleInfos = [
            "Standard query response 0x1234 PTR _http._tcp.local",
            "ACK, seq 42, win 1024",
            "Client Hello",
            "GET /index.html HTTP/1.1",
            "AAAA record query",
            "Encrypted Application Data"
        ]
        
        let newPacket = PacketModel(
            frameNumber: frameCounter,
            time: String(format: "%.6f", CFAbsoluteTimeGetCurrent().truncatingRemainder(dividingBy: 100000)),
            source: randomIP(),
            destination: randomIP(),
            protocolName: sampleProtocols.randomElement() ?? "TCP",
            length: Int.random(in: 60...1024),
            info: sampleInfos.randomElement() ?? "No info",
            hexDump: makeSampleHexDump()
        )
        
        frameCounter += 1
        
        DispatchQueue.main.async {
            self.packets.append(newPacket)
        }
    }
    
    private func randomIP() -> String {
        return "\(Int.random(in: 10...240)).\(Int.random(in: 0...255)).\(Int.random(in: 0...255)).\(Int.random(in: 0...255))"
    }
    
    private func makeSampleHexDump() -> String {
        // Just a placeholder for the “Hex dump” portion
        // Real code might parse raw bytes from a pcap or a capture library
        return """
        0000  45 00 00 54 a6 f2 40 00 40 01 2c 35 c0 a8 00 65
        0010  08 08 08 08 00 00 5a 67 00 01 00 01 61 62 63 64
        0020  65 66 67 68 69 6a 6b 6c 6d 6e 6f 70 71 72 73 74
        0030  75 76 77 78 79 7a 31 32 33 34 35 36 37 38 39 30
        """
    }
}
