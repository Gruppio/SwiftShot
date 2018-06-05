/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Convenience extension for setting shader modifier parameters on SCNMaterial or SCNGeometry.
*/

import Foundation
import SceneKit

private let log = Log()

extension SCNShadable where Self: NSObject {
    // https://developer.apple.com/documentation/scenekit/scnshadable#1654834
    // Some of these can be animated inside of an SCNTransaction.
    // Sets shader modifier data onto a material or all materials in a geometry.
    func setTexture(_ uniform: String, _ texture: SCNMaterialProperty) {
        // this must be the texture name, and not the sampler name
        setValue(texture, forKey: uniform)
    }
    
    // these repeat the type name, so if types change user can validate all type breaks
    func setFloat4x4(_ uniform: String, _ value: float4x4) {
        setValue(CATransform3D(value), forKey: uniform)
    }
    func setFloat4(_ uniform: String, _ value: float4) {
        setValue(SCNVector4(value.x, value.y, value.z, value.w), forKey: uniform)
    }
    func setFloat3(_ uniform: String, _ value: float3) {
        setValue(SCNVector3(value.x, value.y, value.z), forKey: uniform)
    }
    func setFloat2(_ uniform: String, _ value: float2) {
        setValue(CGPoint(x: CGFloat(value.x), y: CGFloat(value.y)), forKey: uniform)
    }
    func setFloat(_ uniform: String, _ value: Float) {
        setValue(CGFloat(value), forKey: uniform)
    }
    func setFloat(_ uniform: String, _ value: Double) {
        setValue(CGFloat(value), forKey: uniform)
    }
    func setInt(_ uniform: String, _ value: Int) {
        setValue(NSInteger(value), forKey: uniform)
    }
    func setColor(_ uniform: String, _ value: UIColor) {
        setValue(value, forKey: uniform)
    }
    
    // getters
    func hasUniform(_ uniform: String) -> Bool {
        return value(forKey: uniform) != nil
    }
}
