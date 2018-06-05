/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Custom projectile selection.
*/

import Foundation
import SceneKit

enum ProjectileType: Int, Codable {
    case none = 0
    case cannonball
    case chicken
    
    var next: ProjectileType {
        switch self {
        case .none: return .cannonball
        case .cannonball: return .chicken
        case .chicken: return .cannonball
        }
    }
}

protocol ProjectileDelegate: class {
    var isServer: Bool { get }
    func addParticles(_ particlesNode: SCNNode, worldPosition: float3)
    func despawnProjectile(_ projectile: Projectile)
    func addNodeToLevel(node: SCNNode)
}

class Projectile: GameObject {
    var physicsBody: SCNPhysicsBody?
    var isAlive = false
    var team: TeamID = .none {
        didSet {
            // we assume the geometry and lod are unique to geometry and lod here
            geometryNode?.geometry?.firstMaterial?.diffuse.contents = team.color
            if let levelsOfDetail = geometryNode?.geometry?.levelsOfDetail {
                for lod in levelsOfDetail {
                    lod.geometry?.firstMaterial?.diffuse.contents = team.color
                }
            }
        }
    }
    
    weak var delegate: ProjectileDelegate?
    
    private var startTime: TimeInterval = 0.0
    var isLaunched = false
    var age: TimeInterval { return isLaunched ? (GameTime.time - startTime) : 0.0 }
    
    // Projectile life time should be set so that projectiles will not be depleted from the pool
    private var lifeTime: TimeInterval = 0.0
    private let fadeTimeToLifeTimeRatio = 0.1
    private var fadeStartTime: TimeInterval { return lifeTime * (1.0 - fadeTimeToLifeTimeRatio) }

    init(radius: CGFloat) {
        let ballShape = SCNSphere(radius: radius)
        ballShape.materials = [SCNMaterial(diffuse: UIColor.white)]
        let node = SCNNode(geometry: ballShape)
        let physicsShape = SCNPhysicsShape(node: node, options: nil)
        let physicsBody = SCNPhysicsBody(type: SCNPhysicsBodyType.dynamic, shape: physicsShape)
        physicsBody.contactTestBitMask = CollisionMask([.rigidBody, .glitterObject, .triggerVolume]).rawValue
        physicsBody.categoryBitMask = CollisionMask([.ball, .rigidBody, .phantom]).rawValue
        node.physicsBody = physicsBody
        
        super.init(node: node, index: nil, gamedefs: [String: Any]())
        self.physicsNode = node
        self.physicsBody = physicsBody
    }

    init(prototypeNode: SCNNode, index: Int?, gamedefs: [String: Any]) {
        let node = prototypeNode.clone()
        // geometry and materials are reference types, so here we
        // do a deep copy. that way, each projectile gets its own color.
        node.copyGeometryAndMaterials()
        
        guard let physicsNode = node.findNodeWithPhysicsBody(),
            let physicsBody = physicsNode.physicsBody else {
                fatalError("Projectile node has no physics")
        }
        
        physicsBody.contactTestBitMask = CollisionMask([.rigidBody, .glitterObject, .triggerVolume]).rawValue
        physicsBody.categoryBitMask = CollisionMask([.ball, .rigidBody, .phantom]).rawValue
        
        super.init(node: node, index: index, gamedefs: gamedefs)
        self.physicsNode = physicsNode
        self.physicsBody = physicsBody
    }
    
    convenience init(prototypeNode: SCNNode) {
        self.init(prototypeNode: prototypeNode, index: nil, gamedefs: [String: Any]())
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func launch(velocity: GameVelocity, lifeTime: TimeInterval, delegate: ProjectileDelegate) {
        startTime = GameTime.time
        isLaunched = true
        self.lifeTime = lifeTime
        self.delegate = delegate
        
        if let physicsNode = physicsNode,
            let physicsBody = physicsBody {
            
            physicsBody.simdVelocityFactor = float3(1.0, 1.0, 1.0)
            physicsBody.simdAngularVelocityFactor = float3(1.0, 1.0, 1.0)
            physicsBody.simdVelocity = velocity.vector
            
            physicsNode.name = "ball"
            physicsNode.simdWorldPosition = velocity.origin
            physicsBody.resetTransform()
        } else {
            fatalError("Projectile not setup")
        }
    }

    func onDidApplyConstraints(renderer: SCNSceneRenderer) {}

    func didBeginContact(contact: SCNPhysicsContact) {
        
    }

    func onSpawn() {

    }

    func update() {
        // Projectile should fade and disappear after a while
        if age > lifeTime {
            objectRootNode.opacity = 1.0
            despawn()
        } else if age > fadeStartTime {
            objectRootNode.opacity = CGFloat(1.0 - (age - fadeStartTime) / (lifeTime - fadeStartTime))
        }
    }
    
    func despawn() {
        guard let delegate = delegate else { fatalError("No Delegate") }
        delegate.despawnProjectile(self)
    }
    
}

// Chicken example of how we make a new projectile type
class ChickenProjectile: Projectile {}
