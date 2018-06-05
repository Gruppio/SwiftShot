/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Synchronization for pooled physics data (projectiles).
*/

import Foundation
import SceneKit

/// - Tag: PhysicsPoolNodeData
struct PhysicsPoolNodeData {
    var isAlive: Bool
    var team: TeamID
    var nodeData: PhysicsNodeData
    
    var description: String {
        return "isAlive:\(isAlive), \(nodeData.description)"
    }
}

extension PhysicsPoolNodeData {
    init(projectile: Projectile) {
        guard let physicsNode = projectile.physicsNode else { fatalError("No physicsNode on Projectile \(projectile.index)") }
        isAlive = projectile.isAlive
        team = projectile.team
        nodeData = PhysicsNodeData(node: physicsNode)
    }
}

extension PhysicsPoolNodeData: BitStreamCodable {
    func encode(to bitStream: inout WritableBitStream) {
        bitStream.appendBool(isAlive)
        team.encode(to: &bitStream)
        nodeData.encode(to: &bitStream)
    }

    init(from bitStream: inout ReadableBitStream) throws {
        isAlive = try bitStream.readBool()
        team = try TeamID(from: &bitStream)
        nodeData = try PhysicsNodeData(from: &bitStream)
    }
}
