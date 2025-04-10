//
//  PacketDetailView.swift
//  mDNSShark
//

import SwiftUI

struct PacketDetailView: View {
    let packet: PacketModel
    
    var body: some View {
        Form {
            Section(header: Text("Packet Summary")) {
                HStack {
                    Text("Frame:")
                    Spacer()
                    Text("\(packet.frameNumber)")
                }
                HStack {
                    Text("Time:")
                    Spacer()
                    Text(packet.time)
                }
                HStack {
                    Text("Source:")
                    Spacer()
                    Text(packet.source)
                }
                HStack {
                    Text("Destination:")
                    Spacer()
                    Text(packet.destination)
                }
                HStack {
                    Text("Protocol:")
                    Spacer()
                    Text(packet.protocolName)
                }
                HStack {
                    Text("Length:")
                    Spacer()
                    Text("\(packet.length)")
                }
                HStack {
                    Text("Info:")
                    Spacer()
                    Text(packet.info)
                }
            }
            
            // A separate section for raw/hex dump
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
}
