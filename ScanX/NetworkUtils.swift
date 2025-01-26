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
            // Typically on iOS, Wi-Fi is "en0".
            if name == "en0" {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let addr = interface.ifa_addr

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

func getLocalIPPrefix() -> String? {
    guard let wifiAddress = getWiFiAddress() else {
        return nil
    }
    let parts = wifiAddress.split(separator: ".")
    guard parts.count == 4 else {
        return nil
    }
    let prefixParts = parts.dropLast()
    return prefixParts.joined(separator: ".") + "."
}
