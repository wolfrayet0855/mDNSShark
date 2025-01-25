//
//  NetworkScanner.swift
//  ScanX
//
//  Created by user on 1/24/25.
//

import Foundation
import Network

/// A basic ObservableObject that scans the local network and keeps track of found devices.
class NetworkScanner: ObservableObject {
    @Published var devices: [Device] = []

    private let queue = DispatchQueue.global(qos: .background)

    struct Device: Identifiable {
        let id = UUID()
        let ipAddress: String
        let isActive: Bool
    }

    /// Initiates a network scan, automatically detecting the local IP prefix.
    func scanNetwork() {
        devices.removeAll()

        // Attempt to detect prefix from the current Wi-Fi IP
        guard let prefix = getLocalIPPrefix() else {
            // If detection fails, fallback or handle accordingly
            print("Could not detect local IP prefix. Using a default or skipping scan.")
            // fallback example:
            scanNetworkWithPrefix("192.168.1.")
            return
        }

        // If successful, scan using the detected prefix
        scanNetworkWithPrefix(prefix)
    }

    /// Scans IP range x.x.x.1 to x.x.x.255 using the given prefix.
    private func scanNetworkWithPrefix(_ prefix: String) {
        for i in 1...255 {
            let ipAddress = "\(prefix)\(i)"

            // --- CHOOSE YOUR METHOD BELOW ---

            // 1) TCP PROBE approach (quick connect on port 80)
            tcpProbeIPAddress(ipAddress) { isActive in
                DispatchQueue.main.async {
                    self.devices.append(Device(ipAddress: ipAddress, isActive: isActive))
                }
            }

            // 2) ICMP Ping approach
            /*
            pingIPAddressICMP(ipAddress) { isActive in
                DispatchQueue.main.async {
                    self.devices.append(Device(ipAddress: ipAddress, isActive: isActive))
                }
            }
            */
        }
    }
}


// MARK: - 1) TCP Probe with NWConnection
extension NetworkScanner {
    /**
     A quick TCP connection attempt to ip:80.
     If the connection is `.ready` within ~1 second, we call that “active.”
     */
    func tcpProbeIPAddress(_ ipAddress: String, completion: @escaping (Bool) -> Void) {
        guard let port = NWEndpoint.Port(rawValue: 80) else {
            completion(false)
            return
        }
        let host = NWEndpoint.Host(ipAddress)
        let endpoint = NWEndpoint.hostPort(host: host, port: port)
        let params = NWParameters.tcp
        let connection = NWConnection(to: endpoint, using: params)

        connection.stateUpdateHandler = { newState in
            switch newState {
            case .ready:
                // We connected, so the host should be "active"
                connection.cancel()
                completion(true)

            case .failed(_), .cancelled:
                // Could not connect
                connection.cancel()
                completion(false)

            default:
                break
            }
        }

        // Start connection on background queue
        connection.start(queue: queue)

        // Timeout after 1s if not connected
        queue.asyncAfter(deadline: .now() + 1.0) {
            if connection.state != .ready {
                connection.cancel()
                completion(false)
            }
        }
    }
}

// MARK: - Minimal C-level ICMP utilities
// ICMPv4 types
private let ICMP_ECHO_REQUEST: UInt8 = 8
private let ICMP_ECHO_REPLY: UInt8 = 0

// Struct matching icmp header for an echo request
private struct icmp_echo {
    var icmp_type: UInt8
    var icmp_code: UInt8
    var icmp_cksum: UInt16
    var icmp_id: UInt16
    var icmp_seq: UInt16
}

// in_cksum function to compute Internet Checksum for the data.
private func in_cksum(_ buffer: UnsafeMutableRawPointer!, _ length: Int) -> UInt16 {
    var sum: UInt32 = 0
    var ptr = buffer.bindMemory(to: UInt16.self, capacity: length/2)
    var count = length

    while count > 1 {
        sum &+= UInt32(ptr.pointee)
        ptr = ptr.advanced(by: 1)
        count -= 2
    }

    if count > 0 {
        sum &+= UInt32(UnsafeMutablePointer<UInt8>(OpaquePointer(ptr)).pointee) << 8
    }

    while (sum >> 16) != 0 {
        sum = (sum & 0xffff) &+ (sum >> 16)
    }
    return ~UInt16(sum & 0xffff)
}

