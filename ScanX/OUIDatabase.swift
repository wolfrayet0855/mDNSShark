import Foundation
import os

/// A singleton for loading & querying OUI data from a local JSON file in the app bundle.
class OUIDatabase {
    static let shared = OUIDatabase()
    private var ouiDictionary: [String: String] = [:]
    private let logger = Logger(subsystem: "com.example.ScanX", category: "OUIDatabase")

    private init() {
        loadOUIDatabase()
    }
    
    /// Loads the `oui.json` resource from the app bundle into memory.
    private func loadOUIDatabase() {
        guard let url = Bundle.main.url(forResource: "oui", withExtension: "json") else {
            logger.error("Could not find oui.json in bundle.")
            return
        }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([String: String].self, from: data)
            ouiDictionary = decoded
            logger.info("Loaded OUI database with \(ouiDictionary.count) entries.")
        } catch {
            logger.error("Failed to load or parse oui.json: \(error.localizedDescription)")
        }
    }
    
    /// Lookup the manufacturer for a given OUI (e.g. "98:50:2e").
    /// Returns nil if not found in the dictionary.
    func manufacturer(for oui: String) -> String? {
        return ouiDictionary[oui.lowercased()]
    }
}
