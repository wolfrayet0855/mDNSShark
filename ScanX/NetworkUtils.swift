//
//  NetworkUtils.swift
//  ScanX
//
//  Created by user on 1/24/25.
//

import Foundation
import Darwin // Provides 'getifaddrs' and other C-level APIs

/**
 Returns the current Wi-Fi (IPv4) address, or `nil` if not found.
 Typically, the interface name on iOS for Wi-Fi is "en0".
 */
func getWiFiAddress() -> String? {
    var address: String?
    var ifaddr: UnsafeMutablePointer<ifaddrs>?

    // retrieve the current interfaces
    guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
        return nil
    }
    defer { freeifaddrs(ifaddr) }

    // iterate through the linked list of interfaces
    for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
        let interface = ptr.pointee
        let flags = Int32(interface.ifa_flags)

        // We're interested in IPv4 addresses, excluding loopback
        if (flags & (IFF_UP|IFF_RUNNING|IFF_LOOPBACK)) == (IFF_UP|IFF_RUNNING),
           interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
            let name = String(cString: interface.ifa_name)
            // Adjust if needed for your environment
            if name == "en0" {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let addr = interface.ifa_addr

                // Convert interface address to a human-readable string
                getnameinfo(
                    addr,
                    socklen_t(interface.ifa_addr.pointee.sa_len),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    socklen_t(0),
                    NI_NUMERICHOST
                )

                address = String(cString: hostname)
                break
            }
        }
    }

    return address
}

/**
 Attempts to extract the first three octets from the current Wi-Fi IP address
 and return them as a prefix (e.g. "192.168.1.").
 Returns `nil` if the Wi-Fi address cannot be determined or is malformed.
 */
func getLocalIPPrefix() -> String? {
    guard let wifiAddress = getWiFiAddress() else {
        return nil
    }
    // e.g., wifiAddress is "192.168.1.14"
    let parts = wifiAddress.split(separator: ".")
    guard parts.count == 4 else {
        return nil
    }
    // drop the last octet
    let prefixParts = parts.dropLast()
    // rejoin the first three octets, append a dot
    return prefixParts.joined(separator: ".") + "."
}
