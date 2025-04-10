//
//  PacketDetailView.swift
//  mDNSShark
//

import SwiftUI

struct PacketDetailView: View {
    let packet: PacketModel
    
    var body: some View {
        Form {
            // Show all details (including Time, Length, Info)
            Section(header: Text("Packet Summary")) {
                keyValueRow("No.", "\(packet.frameNumber)")
                keyValueRow("Time", packet.time)
                keyValueRow("Source", packet.source)
                keyValueRow("Destination", packet.destination)
                keyValueRow("Protocol", packet.protocolName)
                keyValueRow("Length", "\(packet.length)")
                keyValueRow("Info", packet.info)
            }
            
            Section(header: Text("Hex Dump")) {
                ScrollView {
                    Text(packet.hexDump)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                }
                .frame(minHeight: 250)
            }
        }
        .navigationTitle("Frame \(packet.frameNumber)")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // Helper for consistent layout
    @ViewBuilder
    private func keyValueRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .multilineTextAlignment(.trailing)
        }
    }
}

