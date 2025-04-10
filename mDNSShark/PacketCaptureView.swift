//
//  PacketCaptureView.swift
//  mDNSShark
//
//  Created by user on 4/10/25.
//


//
//  PacketCaptureView.swift
//  mDNSShark
//
//  Created by user on 3/19/25.
//  Replicates a Wireshark-like columns UI with a detail view.
//

import SwiftUI

struct PacketCaptureView: View {
    // This manager simulates or fetches packets. See "PacketCaptureManager.swift".
    @StateObject private var manager = PacketCaptureManager()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                
                // -- Optional: A top bar with a "Capture" button, just to mimic "Start/Stop Capture"
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
                    .padding()
                    
                    Spacer()
                }
                .background(Color(UIColor.systemGray6))
                
                // -- Column headers (to replicate the look of Wireshark)
                HStack(spacing: 0) {
                    Text("No.")
                        .bold()
                        .frame(width: 50, alignment: .leading)
                        .padding(.leading, 4)
                    Divider()
                    Text("Time")
                        .bold()
                        .frame(width: 80, alignment: .leading)
                        .padding(.leading, 4)
                    Divider()
                    Text("Source")
                        .bold()
                        .frame(width: 120, alignment: .leading)
                        .padding(.leading, 4)
                    Divider()
                    Text("Destination")
                        .bold()
                        .frame(width: 120, alignment: .leading)
                        .padding(.leading, 4)
                    Divider()
                    Text("Proto")
                        .bold()
                        .frame(width: 60, alignment: .leading)
                        .padding(.leading, 4)
                    Divider()
                    Text("Length")
                        .bold()
                        .frame(width: 60, alignment: .leading)
                        .padding(.leading, 4)
                    Divider()
                    Text("Info")
                        .bold()
                        .frame(minWidth: 100, alignment: .leading)
                        .padding(.leading, 4)
                    Spacer()
                }
                .frame(height: 40)
                .background(Color(UIColor.systemGray5))
                
                // -- List of captured packets
                List(manager.packets) { packet in
                    NavigationLink(destination: PacketDetailView(packet: packet)) {
                        // Each row in the "table"
                        HStack(spacing: 0) {
                            Text("\(packet.frameNumber)")
                                .frame(width: 50, alignment: .leading)
                                .lineLimit(1)
                                .padding(.leading, 4)
                            Divider()
                            Text(packet.time)
                                .frame(width: 80, alignment: .leading)
                                .lineLimit(1)
                                .padding(.leading, 4)
                            Divider()
                            Text(packet.source)
                                .frame(width: 120, alignment: .leading)
                                .lineLimit(1)
                                .padding(.leading, 4)
                            Divider()
                            Text(packet.destination)
                                .frame(width: 120, alignment: .leading)
                                .lineLimit(1)
                                .padding(.leading, 4)
                            Divider()
                            Text(packet.protocolName)
                                .frame(width: 60, alignment: .leading)
                                .lineLimit(1)
                                .padding(.leading, 4)
                            Divider()
                            Text("\(packet.length)")
                                .frame(width: 60, alignment: .leading)
                                .lineLimit(1)
                                .padding(.leading, 4)
                            Divider()
                            Text(packet.info)
                                .frame(minWidth: 100, alignment: .leading)
                                .lineLimit(1)
                                .padding(.leading, 4)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Packet Capture")
        }
    }
}
