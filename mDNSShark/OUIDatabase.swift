import Foundation
import os

class OUIDatabase {
    static let shared = OUIDatabase()
    
    private let logger = Logger(subsystem: "com.example.mDNSShark", category: "OUIDatabase")
    
    private let ouiDictionary: [String: String] = [
        "a4:cf:99": "Apple, Inc.",
        "98:50:2e": "Apple, Inc.",
        "9c:8c:6e": "Apple, Inc.",
        "00:26:b0": "Apple, Inc.",
        "e0:cb:4e": "Apple, Inc.",
        "ec:35:86": "Apple, Inc.",
        "f0:99:bf": "Apple, Inc.",
        "dc:2b:2a": "Apple, Inc.",
        "1c:36:bb": "Apple, Inc.",
        "58:b0:35": "Apple, Inc.",
        "e6:dd:fb": "Apple, Inc.",
        "f4:5c:89": "Apple, Inc.",
        "bc:92:6b": "Apple, Inc.",
        "a8:66:7f": "Apple, Inc.",
        "b0:34:95": "Apple, Inc.",
        "d4:61:9d": "Apple, Inc.",
        "84:38:35": "Apple, Inc.",
        "2c:1f:23": "Apple, Inc.",
        "84:4b:f5": "Apple, Inc.",
        "44:d9:e7": "Apple, Inc.",
        "48:60:bc": "Apple, Inc.",
        "ac:87:a3": "Apple, Inc.",
        "cc:20:e8": "Apple, Inc.",
        "08:66:98": "Apple, Inc.",
        "68:9c:70": "Apple, Inc.",
        "d8:9e:3f": "Apple, Inc.",
        "cc:78:5f": "Apple, Inc.",
        "ac:1f:74": "Apple, Inc.",
        "88:c6:63": "Apple, Inc.",
        "4c:8d:79": "Apple, Inc.",
        "a4:5e:60": "Apple, Inc.",
        "78:64:c0": "Apple, Inc",
        "00:1f:5b": "Cisco Systems, Inc.",
        "00:16:6f": "Cisco Systems, Inc.",
        "00:05:9a": "Cisco Systems, Inc.",
        "68:bc:0c": "Cisco Systems, Inc.",
        "00:24:97": "Cisco Systems, Inc.",
        "00:1b:d4": "Cisco Systems, Inc.",
        "00:1d:70": "Cisco Systems, Inc.",
        "00:22:90": "Cisco Systems, Inc.",
        "2c:54:2d": "Cisco Systems, Inc.",
        "ac:bc:32": "Cisco Systems, Inc.",
        "00:1a:2b": "Dell Inc.",
        "34:02:86": "Dell Inc.",
        "f4:8e:92": "Dell Inc.",
        "bc:30:5b": "Dell Inc.",
        "f0:92:1c": "Dell Inc.",
        "00:13:72": "Dell Inc.",
        "14:18:77": "Dell Inc.",
        "2c:59:e5": "Dell Inc.",
        "40:9c:28": "Dell Inc.",
        "70:85:c2": "Dell Inc.",
        "00:14:22": "Intel Corporate",
        "68:05:ca": "Intel Corporate",
        "00:1c:c0": "Intel Corporate",
        "3c:d9:2b": "Intel Corporate",
        "00:22:fb": "Intel Corporate",
        "30:07:4d": "Hewlett Packard",
        "00:1a:4b": "Hewlett Packard",
        "b4:b5:2f": "Hewlett Packard",
        "c4:34:6b": "Hewlett Packard",
        "14:02:ec": "Hewlett Packard",
        "b8:27:eb": "Raspberry Pi Foundation",
        "e4:5f:01": "Raspberry Pi Foundation",
        "dc:a6:32": "Raspberry Pi Foundation",
        "dc:44:6d": "Raspberry Pi Foundation",
        "dc:08:ff": "Raspberry Pi Foundation",
        "d0:3d:29": "Amazon Technologies Inc.",
        "7c:ed:8d": "Amazon Technologies Inc.",
        "78:2b:46": "Amazon Technologies Inc.",
        "00:50:f2": "Microsoft Corporation",
        "38:e0:4d": "Microsoft Corporation"
    ]
    
    private init() {
        self.logger.info("OUIDatabase: Using static dictionary with \(self.ouiDictionary.count) entries.")
    }
    
    func manufacturer(for oui: String) -> String? {
        let lowerOUI = oui.lowercased()
        return self.ouiDictionary[lowerOUI]
    }
}

