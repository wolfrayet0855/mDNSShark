//
//  PacketCaptureView.swift
//  mDNSShark
//
//  Created by user on 4/10/25.
//


import SwiftUI

struct PacketCaptureView: View {
    @StateObject private var manager = PacketCaptureManager()
    
    // Define grid layout columns for Frame, Source, Destination, and Protocol
    private let columns = [
        GridItem(.fixed(55), alignment: .leading),    // Frame (Frame Number)
        GridItem(.fixed(120), alignment: .leading),   // Source
        GridItem(.fixed(120), alignment: .leading),   // Destination
        GridItem(.fixed(80), alignment: .leading)     // Protocol
    ]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                
                // -- Top bar with a "Capture" button for starting/stopping capture
                HStack {
                    Button(action: {
                        manager.isCapturing.toggle()
                        if manager.isCapturing {
                            manager.startCaptureSimulation()
                        } else {
                            manager.stopCapture()
                        }
                    }) {
                        Text(manager.isCapturing ? "Stop Capture" : "Start Capture")
                            .font(.headline)
                            .padding(8)
                            .background(manager.isCapturing ? Color.red : Color.blue)
                            .cornerRadius(6)
                            .foregroundColor(.white)
                    }
                    .padding(.leading)
                    
                    Spacer()
                }
                .padding(.vertical, 4)
                .background(Color(UIColor.systemGray6))
                
                // -- Table header with selected columns
                LazyVGrid(columns: columns, spacing: 10) {
                    Text("Frame").bold()
                    Text("Source").bold()
                    Text("Destination").bold()
                    Text("Protocol").bold()
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
                .background(Color(UIColor.systemGray5))
                
                // -- Table content inside a scrollable view
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(manager.packets) { packet in
                            NavigationLink(destination: PacketDetailView(packet: packet)) {
                                LazyVGrid(columns: columns, spacing: 10) {
                                    Text("\(packet.frameNumber)")
                                    Text(packet.source)
                                    Text(packet.destination)
                                    Text(packet.protocolName)
                                }
                                .padding(8)
                                .background(Color.white)
                                .overlay(
                                    Rectangle()
                                        .stroke(Color(UIColor.systemGray4), lineWidth: 0.5)
                                )
                            }
                        }
                    }
                }
            }
            .navigationTitle("Packet Capture")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
