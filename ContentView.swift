//
//  ContentView.swift
//  ScanX
//
//  Created by user on 1/24/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var scanner = NetworkScanner()

    var body: some View {
        NavigationView {
            VStack {
                Button(action: {
                    scanner.scanNetwork()
                }) {
                    Text("Scan Network")
                        .font(.headline)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }

                List(scanner.devices) { device in
                    HStack {
                        Text(device.ipAddress)
                        Spacer()
                        if device.isActive {
                            Text("Active")
                                .foregroundColor(.green)
                        } else {
                            Text("Inactive")
                                .foregroundColor(.red)
                        }
                    }
                }
                .listStyle(PlainListStyle())
            }
            .navigationTitle("Network Scanner")
        }
    }
}
