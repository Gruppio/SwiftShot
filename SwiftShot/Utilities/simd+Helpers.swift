/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Convenience extensions for SIMD vector and matrix types.
*/

import Foundation
import simd
import SceneKit

extension CATransform3D {
    init(_ m: float4x4) {
        self.init(
            m11: CGFloat(m.columns.0.x), m12: CGFloat(m.columns.1.x), m13: CGFloat(m.columns.2.x), m14: CGFloat(m.columns.3.x),
            m21: CGFloat(m.columns.0.y), m22: CGFloat(m.columns.1.y), m23: CGFloat(m.columns.2.y), m24: CGFloat(m.columns.3.y),
            m31: CGFloat(m.columns.0.x), m32: CGFloat(m.columns.1.z), m33: CGFloat(m.columns.2.z), m34: CGFloat(m.columns.3.z),
            m41: CGFloat(m.columns.0.w), m42: CGFloat(m.columns.1.w), m43: CGFloat(m.columns.2.w), m44: CGFloat(m.columns.3.w)
        )
    }
}

extension float4x4 {
    var translation: float3 {
        get {
            return columns.3.xyz
        }
        set(newValue) {
            columns.3 = float4(newValue, 1)
        }
    }
    
    var scale: float3 {
        return float3(length(columns.0), length(columns.1), length(columns.2))
    }

    init(translation vector: float3) {
        self.init(float4(1, 0, 0, 0),
                  float4(0, 1, 0, 0),
                  float4(0, 0, 1, 0),
                  float4(vector.x, vector.y, vector.z, 1))
    }
    
    init(scale factor: Float) {
        self.init(scale: float3(factor))
    }
    init(scale vector: float3) {
        self.init(float4(vector.x, 0, 0, 0),
                  float4(0, vector.y, 0, 0),
                  float4(0, 0, vector.z, 0),
                  float4(0, 0, 0, 1))
    }
    
    static let identity = matrix_identity_float4x4
}

func normalize(_ matrix: float4x4) -> float4x4 {
    var normalized = matrix
    normalized.columns.0 = simd.normalize(normalized.columns.0)
    normalized.columns.1 = simd.normalize(normalized.columns.1)
    normalized.columns.2 = simd.normalize(normalized.columns.2)
    return normalized
}

extension float4 {
    static let zero = float4(0.0)
    
    var xyz: float3 {
        get {
            return float3(x, y, z)
        }
        set {
            x = newValue.x
            y = newValue.y
            z = newValue.z
        }
    }
    
    init(_ xyz: float3, _ w: Float) {
        self.init(xyz.x, xyz.y, xyz.z, w)
    }
    
    var hasNaN: Bool {
        return x.isNaN || y.isNaN || z.isNaN || w.isNaN
    }
    
    func almostEqual(_ value: float4, within tolerance: Float) -> Bool {
        return length(self - value) <= tolerance
    }
}

extension float3 {
    var hasNaN: Bool {
        return x.isNaN || y.isNaN || z.isNaN
    }
    
    func almostEqual(_ value: float3, within tolerance: Float) -> Bool {
        return length(self - value) <= tolerance
    }
}

extension Float {
    func normalizedAngle(forMinimalRotationTo angle: Float, increment: Float) -> Float {
        var normalized = self
        while abs(normalized - angle) > increment / 2 {
            if self > angle {
                normalized -= increment
            } else {
                normalized += increment
            }
        }
        return normalized
    }
}
