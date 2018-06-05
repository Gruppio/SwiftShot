/*
See LICENSE folder for this sample’s licensing information.

Abstract:
User interaction for the slingshot.
*/

import Foundation
import SceneKit

class CatapultInteraction: Interaction, GrabInteractionDelegate {
    weak var delegate: InteractionDelegate?

    private var catapults = [Int: Catapult]()
    
    // this is a ball that doesn't have physics
    private var dummyBall: SCNNode
    
    var grabInteraction: GrabInteraction? {
        didSet {
            // Add hook up to grabInteraction delegate automatically
            if let grabInteraction = grabInteraction {
                grabInteraction.grabDelegate = self
            }
        }
    }
    
    required init(delegate: InteractionDelegate) {
        self.delegate = delegate
        dummyBall = SCNNode.loadSCNAsset(modelFileName: "projectiles_ball_8k")
        
        // stri the geometry out of a low-lod model, assume it doesn't have an lod
        if let geometry = dummyBall.geometry {
            let lod = SCNNode.loadSCNAsset(modelFileName: "projectiles_ball")
            if let lodGeometry = lod.geometry {
                lodGeometry.materials = geometry.materials
                
                // this radius will be replaced by fixLevelsOfDetail
                // when the level is placed
                geometry.levelsOfDetail = [SCNLevelOfDetail(geometry: lodGeometry, screenSpaceRadius: 100)]
            }
        }
    }
    
    func addCatapult(_ catapult: Catapult) {
        guard let grabInteraction = grabInteraction else { fatalError("GrabInteraction not set") }
        grabInteraction.addGrabbable(catapult)
        catapults[catapult.catapultID] = catapult
        setProjectileOnCatapult(catapult, projectileType: .cannonball)
    }
    
    private func setProjectileOnCatapult(_ catapult: Catapult, projectileType: ProjectileType) {
        guard let delegate = delegate else { fatalError("No delegate") }
        
        let projectile = TrailBallProjectile(prototypeNode: dummyBall.clone())
        projectile.isAlive = true
        projectile.team = catapult.teamID
        
        guard let physicsNode = projectile.physicsNode else { fatalError("Projectile has no physicsNode") }
        physicsNode.physicsBody = nil
        delegate.addCatapultPhysicsIgnoreNodeToLevel(physicsNode, catapultID: catapult.catapultID)

        catapult.setProjectileType(projectileType: projectileType, projectile: projectile.objectRootNode)
    }
    
    func canGrabAnyCatapult(cameraRay: Ray) -> Bool {
        return catapults.contains(where: { $0.value.canGrab(cameraRay: cameraRay) })
    }
    
    // MARK: - Interactions

    func update(cameraInfo: CameraInfo) {
        for catapult in catapults.values {
            catapult.update()
        }
    }
    
    // MARK: - Game Action Handling
    
    func handle(gameAction: GameAction, player: Player) {
        if case .catapultRelease(let data) = gameAction {
            guard let delegate = delegate else { fatalError("No Delegate") }
            handleCatapultReleaseAction(data: data, player: player, delegate: delegate)
        }
    }
    
    private func releaseCatapultGrab(catapultID: Int) {
        guard let catapult = catapults[catapultID] else { fatalError("No catapult \(catapultID)") }
        guard let grabInteraction = grabInteraction else { fatalError("GrabInteraction not set") }
        catapult.isGrabbed = false
        
        // Empty grabbedCatapult if this catapult was grabbed by player
        if let grabbedCatapult = grabInteraction.grabbedGrabbable as? Catapult, grabbedCatapult.catapultID == catapultID {
            guard let delegate = delegate else { fatalError("No delegate") }
            delegate.stopIgnoringPhysicsOnCatapult()
            grabInteraction.grabbedGrabbable = nil
        }
    }
    
    func handleCatapultReleaseAction(data: SlingData, player: Player, delegate: InteractionDelegate) {
        if let catapult = catapults[data.catapultID] {
            catapult.onLaunch(velocity: GameVelocity.zero)
            releaseCatapultGrab(catapultID: data.catapultID)
        }
    }
    
    // MARK: - Grab Interaction Delegate
    
    func shouldForceRelease(grabbable: Grabbable) -> Bool {
        guard let catapult = grabbable as? Catapult else { fatalError("Grabbable is not catapult") }
        return catapult.isPulledTooFar || isCatapultFloating(catapult)
    }
    
    private func isCatapultFloating(_ catapult: Catapult) -> Bool {
        guard let delegate = delegate else { fatalError("No Delegate") }
        guard let physicsBody = catapult.base.physicsBody else { return false }
        let contacts = delegate.physicsWorld.contactTest(with: physicsBody, options: nil)
        return contacts.isEmpty
    }
    
    func onGrabStart(grabbable: Grabbable, cameraInfo: CameraInfo, player: Player) {
        guard let delegate = delegate else { fatalError("No Delegate") }
        guard let catapult = grabbable as? Catapult else { return }
        
        // If this isn't server, we should ignore the physics data from the server for this player's catapult,
        // and use the information calculated on this player's device instead (to prevent lag)
        if !delegate.isServer {
            delegate.ignorePhysicsOnCatapult(catapult.catapultID)
        }
        
        catapult.onGrabStart()
    }
    
    func onServerRelease(grabbable: Grabbable, cameraInfo: CameraInfo, player: Player) {
        guard let delegate = delegate else { fatalError("No Delegate") }
        guard let catapult = grabbable as? Catapult else { return }
        
        // Launch the ball
        guard let velocity = catapult.tryGetLaunchVelocity(cameraInfo: cameraInfo) else { return }
        
        catapult.onLaunch(velocity: velocity)
        slingBall(catapult: catapult, velocity: velocity)
        catapult.releaseSlingGrab()
        
        releaseCatapultGrab(catapultID: catapult.catapultID)
        
        let slingData = SlingData(catapultID: catapult.catapultID, projectileType: catapult.projectileType, velocity: velocity)
        
        // succeed in launching catapult, notify all clients of the update
        delegate.serverDispatchActionToAll(gameAction: .catapultRelease(slingData))
    }
    
    func onServerGrab(grabbable: Grabbable, cameraInfo: CameraInfo, player: Player) {
        guard let catapult = grabbable as? Catapult else { return }
        catapult.serverGrab(cameraRay: cameraInfo.ray)
        
        // the player has committed to a side
        if player.teamID == .none {
            player.teamID = catapult.teamID
        }
    }
    
    func onUpdateGrabStatus(grabbable: Grabbable, cameraInfo: CameraInfo) {
        guard let catapult = grabbable as? Catapult else { return }
        catapult.ballVisible = .visible
        catapult.onGrab(cameraInfo)
    }
    
    // MARK: - Collision
    
    let minImpuseToReleaseCatapult: CGFloat = 1.5
    
    func didCollision(node: SCNNode, otherNode: SCNNode, pos: float3, impulse: CGFloat) {
        if let gameObject = node.nearestParentGameObject(), let catapult = gameObject as? Catapult {
            guard let otherGameObject = otherNode.nearestParentGameObject() else { return }
            
            // Projectile case
            if let projectile = otherGameObject as? Projectile {
                let node = catapult.base
                guard let physicsBody = node.physicsBody else { fatalError("Catapult has no physicsBody") }
                
                // Do not let projectile from the same team kill the catapult
                if catapult.teamID == projectile.team {
                    physicsBody.simdVelocity = float3()
                    physicsBody.simdAngularVelocity = float4(0.0, 1.0, 0.0, 0.0)
                }
            }
            
            // Server tries to release the catapult if it got impulse from block or projectile
            guard impulse > minImpuseToReleaseCatapult else { return }
            guard let delegate = delegate else { fatalError("No delegate") }
            guard delegate.isServer else { return }
            
            // Any game objects (blocks or projectiles) case
            let data = GrabInfo(grabbableID: catapult.catapultID, cameraInfo: catapult.lastCameraInfo)
            delegate.dispatchActionToServer(gameAction: .tryRelease(data))
        }
    }
    
    // MARK: - Sling Ball
    
    func slingBall(catapult: Catapult, velocity: GameVelocity) {
        guard let delegate = delegate else { fatalError("No delegate") }
        let newProjectile = delegate.spawnProjectile()
        newProjectile.team = catapult.teamID
        
        delegate.addNodeToLevel(newProjectile.objectRootNode)
        
        // The lifeTime of projectile needed to sustain the pool is defined by:
        // (Catapult Count) * (1 + (lifeTime) / (cooldownTime)) = (Pool Count)
        let poolCount = delegate.gameObjectPoolCount()
        let lifeTime = Double(poolCount / catapults.count - 1) * catapult.coolDownTime
        
        newProjectile.launch(velocity: velocity, lifeTime: lifeTime, delegate: delegate.projectileDelegate)
        
        // assign the catapult source to this ball
        if let physicsNode = newProjectile.physicsNode, let physBody = physicsNode.physicsBody {
            physicsNode.setValue(catapult.catapultID, forKey: "Source")
            physBody.collisionBitMask = CollisionMask([.rigidBody, .glitterObject, .ball]).rawValue
            if catapult.teamID == .blue {
                physBody.collisionBitMask |= CollisionMask.catapultYellow.rawValue
            } else {
                physBody.collisionBitMask |= CollisionMask.catapultBlue.rawValue
            }
        }
    }
    
    func handleTouch(type: TouchType, hitInfo: GameRayCastHitInfo) {
        
    }
}

extension CatapultInteraction: VortexActivationDelegate {
    func vortexDidActivate(_ vortex: VortexInteraction) {
        // Kill all catapults when vortex activates
        guard let delegate = delegate else { fatalError("No delegate") }
        for catapult in catapults.values {
            let data = HitCatapult(catapultID: catapult.catapultID, justKnockedout: false, vortex: true)
            delegate.dispatchActionToAll(gameAction: .catapultKnockOut(data))
        }
    }
}
