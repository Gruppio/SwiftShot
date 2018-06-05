/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Convenience extension for using SIMD types with SCNPhysicsBody.
*/

import Foundation
import SceneKit

extension SCNPhysicsBody {
    var simdVelocity: float3 {
        get { return float3(velocity) }
        set { velocity = SCNVector3(newValue) }
    }
    
    var simdAngularVelocity: float4 {
        get { return float4(angularVelocity) }
        set { angularVelocity = SCNVector4(newValue) }
    }
    
    var simdVelocityFactor: float3 {
        get { return float3(velocityFactor) }
        set { velocityFactor = SCNVector3(newValue) }
    }
    
    var simdAngularVelocityFactor: float3 {
        get { return float3(angularVelocityFactor) }
        set { angularVelocityFactor = SCNVector3(newValue) }
    }
    
    func applyForce(_ force: float3, asImpulse impulse: Bool) {
        applyForce(SCNVector3(force), asImpulse: impulse)
    }
    
    func applyTorque(_ torque: float4, asImpulse impulse: Bool) {
        applyTorque(SCNVector4(torque), asImpulse: impulse)
    }
}
