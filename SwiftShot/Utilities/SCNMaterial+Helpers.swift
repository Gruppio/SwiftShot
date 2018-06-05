/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Convenience extension for setting SCNMaterial visual properties.
*/

import Foundation
import SceneKit

extension SCNMaterial {
    convenience init(diffuse: Any?) {
        self.init()
        self.diffuse.contents = diffuse
        isDoubleSided = true
        lightingModel = .physicallyBased
    }
}
