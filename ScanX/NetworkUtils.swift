import Foundation
import Darwin

func getWiFiAddress() -> String? {
    var address: String?
    var ifaddr: UnsafeMutablePointer<ifaddrs>?

    guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
        return nil
    }
    defer { freeifaddrs(ifaddr) }

    for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
        let interface = ptr.pointee
        let flags = Int32(interface.ifa_flags)

        if (flags & (IFF_UP|IFF_RUNNING|IFF_LOOPBACK)) == (IFF_UP|IFF_RUNNING),
           interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
            let name = String(cString: interface.ifa_name)
            // On iOS, Wi-Fi is typically "en0"
            if name == "en0" {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let addr = interface.ifa_addr

                getnameinfo(addr,
                            socklen_t(interface.ifa_addr.pointee.sa_len),
                            &hostname,
                            socklen_t(hostname.count),
                            nil,
                            socklen_t(0),
                            NI_NUMERICHOST)

                address = String(cString: hostname)
                break
            }
        }
    }
    return address
}

/**
 Extracts prefix for 10.x.x.x, 192.168.x.x, or 172.16-31.x.x
 Returns something like "10.0.1." or "192.168.0." etc.
 If the IP is not in these private ranges, returns nil.
 */
func getLocalIPPrefix() -> String? {
    guard let wifiAddress = getWiFiAddress() else { return nil }

    let parts = wifiAddress.split(separator: ".").map { String($0) }
    guard parts.count == 4 else { return nil }

    // Check if it’s 10.x.x.x
    if parts[0] == "10" {
        // prefix is e.g. "10.0.1."
        return "\(parts[0]).\(parts[1]).\(parts[2])."
    }

    // Check if it’s 192.168.x.x
    if parts[0] == "192" && parts[1] == "168" {
        return "192.168.\(parts[2])."
    }

    // Check if it’s 172.(16-31).x.x
    if parts[0] == "172",
       let secondOctet = Int(parts[1]),
       (16...31).contains(secondOctet)
    {
        return "172.\(secondOctet).\(parts[2])."
    }

    // If we get here, it’s some other IP range, e.g. public IP.
    // Decide if you want to handle that differently or just return nil.
    return nil
}

