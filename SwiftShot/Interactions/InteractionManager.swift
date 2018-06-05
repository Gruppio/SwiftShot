/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Manages user interactions.
*/

import Foundation
import SceneKit
import ARKit

class InteractionManager {
    private var interactions = [Int: Interaction]()
    
    func addInteraction(_ interaction: Interaction) {
        let classIdentifier = ObjectIdentifier(type(of: interaction)).hashValue
        interactions[classIdentifier] = interaction
    }
    
    func interaction(of type: AnyClass) -> Interaction? {
        let classIdentifier = ObjectIdentifier(type).hashValue
        return interactions[classIdentifier]
    }
    
    func removeAllInteractions() {
        interactions.removeAll()
    }
    
    func updateAll(cameraInfo: CameraInfo) {
        for interaction in interactions.values {
            interaction.update(cameraInfo: cameraInfo)
        }
    }

    func handleGameCommandAll(_ gameManager: GameManager, gameCommand: GameCommand) {
        for interaction in interactions.values {
            if case .gameAction(let gameAction) = gameCommand.action, let player = gameCommand.player {
                interaction.handle(gameAction: gameAction, player: player)
            }
        }
    }
    
    // MARK: - Touch Event Routing
    func handleTouch(type: TouchType, hit: GameRayCastHitInfo) {
        for interaction in interactions.values {
            interaction.handleTouch(type: type, hitInfo: hit)
        }
    }
    
    func didCollision(nodeA: SCNNode, nodeB: SCNNode, pos: float3, impulse: CGFloat) {
        for interaction in interactions.values {
            // nodeA and nodeB take turn to be the main node
            interaction.didCollision(node: nodeA, otherNode: nodeB, pos: pos, impulse: impulse)
            interaction.didCollision(node: nodeB, otherNode: nodeA, pos: pos, impulse: impulse)
        }
    }
    
}
