/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Convenience extension for using SIMD types with SCNView.
*/

import SceneKit

extension SCNView {
    /**
     Type conversion wrapper for original `unprojectPoint(_:)` method.
     Used in contexts where sticking to SIMD float3 type is helpful.
     */
    func unprojectPoint(_ point: float3) -> float3 {
        return float3(unprojectPoint(SCNVector3(point)))
    }
}
