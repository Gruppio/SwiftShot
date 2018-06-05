/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Convenience extension for loading from docs directory with FileManager.
*/

import Foundation

extension FileManager {
    func urlInDocumentsDirectory(with fileName: String) -> URL {
        guard let documentPathUrl = urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Failed to retrieve path to user documents directory")
        }
        return documentPathUrl.appendingPathComponent(fileName)
    }
}
