/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Manages toggling physics behavior and user interaction for the slingshot.
*/

import Foundation
import GameplayKit

class SlingshotComponent: GKComponent, UpdatableComponent {
    var restPos: float3
    var currentPos: float3
    var vel: float3
    var physicsMode: Bool
    let catapult: SCNNode
    
    init(catapult: SCNNode) {
        self.catapult = catapult
        restPos = catapult.simdPosition
        currentPos = restPos
        physicsMode = false // Started off and gets turned on only if needed
        vel = float3(0.0)
        
        super.init()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setGrabMode(state: Bool) {
        physicsMode = !state  // physics mode is off when grab mode is on
        if physicsMode {
            currentPos = catapult.simdPosition
        }
    }
    
    func update(deltaTime seconds: TimeInterval, isServer: Bool) {
        super.update(deltaTime: seconds)
        
        if physicsMode {
            // add force in direction to rest point
            let offset = restPos - currentPos
            let force = offset * 1000.0 - vel * 10.0
            
            vel += force * Float(seconds)
            currentPos += vel * Float(seconds)
            catapult.simdPosition = currentPos
            
            catapult.eulerAngles.x *= 0.9 // bring back to 0
        }
    }
}
