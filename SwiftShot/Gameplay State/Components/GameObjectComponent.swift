/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Protocols for GKComponents that require or provide certain behaviors.
*/

import Foundation
import GameplayKit

// Components that require an update call every frame
protocol UpdatableComponent {
    func update(deltaTime seconds: TimeInterval, isServer: Bool)
}

// Components that imply the object can be touched
protocol TouchableComponent {}

// Components that indicate the object should exhibit highlight behavior based on camera distance + orientation
protocol HighlightableComponent {
    var isHighlighted: Bool { get }
    func shouldHighlight(camera: Ray) -> Bool
    func doHighlight(show: Bool, sfxCoordinator: SFXCoordinator?)
}

// Components that allow require special handling during collisions
protocol CollisionHandlerComponent {
    // node is the node associated with this CollisionHandlerComponent.
    func didCollision(manager: GameManager, node: SCNNode, otherNode: SCNNode, pos: float3, impulse: CGFloat)
}

// Components that require setup for scenekit's SCNPhysicsBehavior to work
protocol PhysicsBehaviorComponent {
    var behaviors: [SCNPhysicsBehavior] { get }
    func initBehavior(levelRoot: SCNNode, world: SCNPhysicsWorld)
}
