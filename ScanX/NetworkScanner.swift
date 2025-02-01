import Foundation
import Network
import Combine

class NetworkScanner: ObservableObject {
    @Published var devices: [Device] = []
    @Published var isScanning: Bool = false
    
    // NWBrowser for Bonjour-based scanning
    private var bonjourBrowser: NWBrowser? = nil

    struct Device: Identifiable {
        let id = UUID()
        let identifier: String  // Holds the Bonjour service name
        
        /// Determines the appropriate SF Symbol based on keywords in the identifier.
        func deviceTypeIcon() -> String {
            let lowerIdentifier = identifier.lowercased()
            // Check for printer-related keywords.
            if lowerIdentifier.contains("epson") || lowerIdentifier.contains("printer") {
                return "printer.fill"
            }
            // Check for LED device keywords.
            else if lowerIdentifier.contains("rsled") || lowerIdentifier.contains("rsato") {
                return "lightbulb.fill"
            }
            // Check for computer-related keywords.
            else if lowerIdentifier.contains("mac") || lowerIdentifier.contains("dell") || lowerIdentifier.contains("pc") || lowerIdentifier.contains("computer") {
                return "desktopcomputer"
            }
            // Fallback if no known keyword is found.
            else {
                return "questionmark.circle"
            }
        }
    }
    
    /// Starts a Bonjour-based scan.
    func scanNetwork() {
        // Clear any previous results.
        devices.removeAll()
        isScanning = true
        startBonjourScan()
    }
    
    /// Uses NWBrowser to scan for Bonjour-advertised services.
    private func startBonjourScan() {
        // Use a specific Bonjour service type.
        let bonjourDescriptor = NWBrowser.Descriptor.bonjour(type: "_http._tcp", domain: nil)
        let parameters = NWParameters.tcp
        bonjourBrowser = NWBrowser(for: bonjourDescriptor, using: parameters)
        
        bonjourBrowser?.stateUpdateHandler = { state in
            print("🔎 [Bonjour] Browser state: \(state)")
            if case .failed(let error) = state {
                print("🔎 [Bonjour] Browser failed with error: \(error)")
                DispatchQueue.main.async {
                    self.isScanning = false
                }
            }
        }
        
        bonjourBrowser?.browseResultsChangedHandler = { results, changes in
            for result in results {
                switch result.endpoint {
                case .service(let name, let domain, let type, _):
                    DispatchQueue.main.async {
                        // Avoid duplicate entries.
                        if !self.devices.contains(where: { $0.identifier == name }) {
                            let dev = Device(identifier: name)
                            self.devices.append(dev)
                            print("🔎 [Bonjour] Discovered service: \(name) in domain: \(domain) of type: \(type)")
                        }
                    }
                default:
                    break
                }
            }
        }
        
        // Start browsing on a background queue.
        bonjourBrowser?.start(queue: DispatchQueue.global(qos: .background))
        
        // Stop scanning after a set interval (e.g., 5 seconds for testing).
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            self.bonjourBrowser?.cancel()
            self.bonjourBrowser = nil
            self.isScanning = false
            print("🔎 [Bonjour] Scan ended.")
        }
    }
}

