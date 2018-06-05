/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Container for scene-level physics sync data.
*/

import Foundation
import simd
import SceneKit

private let log = Log()

protocol PhysicsSyncSceneDataDelegate: class {
    func hasNetworkDelayStatusChanged(hasNetworkDelay: Bool)
    func spawnProjectile(objectIndex: Int) -> Projectile
    func despawnProjectile(_ projectile: Projectile)
    
    func playPhysicsSound(objectIndex: Int, soundEvent: CollisionAudioSampler.CollisionEvent)
}

/// - Tag: PhysicsSyncSceneData
class PhysicsSyncSceneData {
    private let lock = NSLock() // need thread protection because add used in main thread, while pack used in render update thread

    // Non-projectile sync
    private var nodeList = [SCNNode]()
    private var nodeDataList = [PhysicsNodeData]()
    
    // Projectile sync
    private var projectileList = [Projectile]()
    private var projectileDataList = [PhysicsPoolNodeData]()
    
    // Sound sync
    private var soundDataList = [CollisionSoundData]()

    // Put data into queue to help with stutters caused by data packet delays
    private var packetQueue = [PhysicsSyncData]()

    private let maxPacketCount = 8
    private let packetCountToSlowDataUsage = 4
    private var shouldRefillPackets = true
    private var justUpdatedHalfway = false
    private var packetReceived = 0
    
    weak var delegate: PhysicsSyncSceneDataDelegate?
    var isInitialized: Bool { return delegate != nil }
    
    // Network Delay
    private(set) var hasNetworkDelay = false
    private var lastNetworkDelay = TimeInterval(0.0)
    private let networkDelayStatusLifetime = 3.0
    
    // Put up a packet number to make sure that packets are in order
    private var lastPacketNumberRead = 0
    
    func addNode(node: SCNNode) {
        lock.lock() ; defer { lock.unlock() }
        nodeList.append(node)
        nodeDataList.append(PhysicsNodeData(node: node))
    }

    func generateData() -> PhysicsSyncData {
        lock.lock() ; defer { lock.unlock() }
        // Update Data of normal nodes
        for index in 0..<nodeList.count {
            nodeDataList[index] = PhysicsNodeData(node: nodeList[index])
        }

        // Update Data of projectiles in the pool
        for (index, projectile) in projectileList.enumerated() {
            projectileDataList[index] = PhysicsPoolNodeData(projectile: projectile)
        }

        // Packet number is used to determined the order of sync data.
        // Because Multipeer Connectivity does not guarantee the order of packet delivery,
        // we use the packet number to discard out of order packets.
        let packetNumber = GameTime.frameCount % PhysicsSyncData.maxPacketNumber
        let packet = PhysicsSyncData(packetNumber: packetNumber, nodeData: nodeDataList,
                                     projectileData: projectileDataList, soundData: soundDataList)
        
        // Clear sound data since it only needs to be played once
        soundDataList.removeAll()
        
        return packet
    }
    
    func updateFromReceivedData() {
        lock.lock() ; defer { lock.unlock() }
        discardOutOfOrderData()
        
        if shouldRefillPackets {
            if packetQueue.count >= maxPacketCount {
                shouldRefillPackets = false
            }
            return
        }
        
        if let oldestData = packetQueue.first {
            // Case when running out of data: Use one packet for two frames
            if justUpdatedHalfway {
                updateNodeFromData(isHalfway: false)
                justUpdatedHalfway = false
            } else if packetQueue.count <= packetCountToSlowDataUsage {
                if !justUpdatedHalfway {
                    apply(packet: oldestData)
                    packetQueue.removeFirst()

                    updateNodeFromData(isHalfway: true)
                    justUpdatedHalfway = true
                }
                
            // Case when enough data: Use one packet per frame as usual
            } else {
                apply(packet: oldestData)
                packetQueue.removeFirst()
            }
            
        } else {
            shouldRefillPackets = true
            log.info("out of packets")
            
            // Update network delay status used to display in sceneViewController
            if !hasNetworkDelay {
                delegate?.hasNetworkDelayStatusChanged(hasNetworkDelay: true)
            }
            hasNetworkDelay = true
            lastNetworkDelay = GameTime.time
        }
        
        while packetQueue.count > maxPacketCount {
            packetQueue.removeFirst()
        }
        
        // Remove networkDelay status after time passsed without a delay
        if hasNetworkDelay && GameTime.time - lastNetworkDelay > networkDelayStatusLifetime {
            delegate?.hasNetworkDelayStatusChanged(hasNetworkDelay: false)
            hasNetworkDelay = false
        }
    }

    func receive(packet: PhysicsSyncData) {
        lock.lock(); defer { lock.unlock() }
        packetQueue.append(packet)
        packetReceived += 1
    }

    private func apply(packet: PhysicsSyncData) {
        lastPacketNumberRead = packet.packetNumber
        nodeDataList = packet.nodeData
        projectileDataList = packet.projectileData
        soundDataList = packet.soundData
        
        // Play sound right away and clear the list
        guard let delegate = delegate else { fatalError("No Delegate") }
        for soundData in soundDataList {
            delegate.playPhysicsSound(objectIndex: soundData.gameObjectIndex, soundEvent: soundData.soundEvent)
        }
        soundDataList.removeAll()

        updateNodeFromData(isHalfway: false)
    }

    private func updateNodeFromData(isHalfway: Bool) {
        // Update Nodes
        let nodeCount = min(nodeList.count, nodeDataList.count)
        for index in 0..<nodeCount {
            // Ignore any specified indices
            if currentIgnoreList.contains(index) {
                continue
            }
            
            updateNode(nodeList[index], with: nodeDataList[index], isHalfway: isHalfway)
        }
        
        guard let delegate = delegate else { fatalError("No delegate") }
        
        for arrayIndex in 0..<projectileList.count {
            var projectile = projectileList[arrayIndex]
            let projectileData = projectileDataList[arrayIndex]
            
            // If the projectile must be spawned, spawn it.
            if projectileData.isAlive {
                // Spawn the projectile if it is exists on the other side, but not here
                if !projectile.isAlive {
                    projectile = delegate.spawnProjectile(objectIndex: projectile.index)
                    projectile.team = projectileData.team
                    projectileList[arrayIndex] = projectile
                }
                
                guard let node = projectile.physicsNode else { fatalError("Projectile \(projectile.index) has no physicsNode") }
                let nodeData = projectileData.nodeData
                
                updateNode(node, with: nodeData, isHalfway: isHalfway)
            } else {
                // Despawn the projectile if it was despawned on the other side
                if projectile.isAlive {
                    delegate.despawnProjectile(projectile)
                }
            }
        }
        
    }
    
    private func updateNode(_ node: SCNNode, with nodeData: PhysicsNodeData, isHalfway: Bool) {
        if isHalfway {
            node.simdWorldPosition = (nodeData.position + node.simdWorldPosition) * 0.5
            node.simdOrientation = simd_slerp(node.simdOrientation, nodeData.orientation, 0.5)
        } else {
            node.simdWorldPosition = nodeData.position
            node.simdOrientation = nodeData.orientation
        }
        
        if let physicsBody = node.physicsBody {
            physicsBody.resetTransform()
            physicsBody.simdVelocity = nodeData.velocity
            physicsBody.simdAngularVelocity = nodeData.angularVelocity
        }
    }
    
    private func discardOutOfOrderData() {
        // Discard data that are out of order
        while let oldestData = packetQueue.first {
            let packetNumber = oldestData.packetNumber
            // If packet number of more than last packet number, then it is in order.
            // For the edge case where packet number resets to 0 again, we test if the difference is more than half the max packet number.
            if packetNumber > lastPacketNumberRead ||
                ((lastPacketNumberRead - packetNumber) > PhysicsSyncData.halfMaxPacketNumber) {
                break
            } else {
                log.error("Packet out of order")
                packetQueue.removeFirst()
            }
        }
    }
    
    struct CatapultIgnoreInfo {
        var catapultID: Int
        var ignoreIndices: [Int]
    }
    
    // Keep the information on what indices belong to a catapultID
    private var catapultIgnoreInfoDict = [Int: CatapultIgnoreInfo]()
    private var currentIgnoreList = [Int]()
    
    // Put the nodeList index of this node into catapult's ignore list, so that we can ignore these nodes for a particular catapult
    func addCatapultIgnoreNode(node: SCNNode, catapultID: Int) {
        lock.lock() ; defer { lock.unlock() }
        nodeList.append(node)
        nodeDataList.append(PhysicsNodeData(node: node))
        
        // Create the CatapultIgnoreInfo if there isn't already one
        if catapultIgnoreInfoDict[catapultID] == nil {
            catapultIgnoreInfoDict[catapultID] = CatapultIgnoreInfo(catapultID: catapultID, ignoreIndices: [Int]())
        }
    
        let ignoreIndex = nodeList.count - 1
        catapultIgnoreInfoDict[catapultID]?.ignoreIndices.append(ignoreIndex)
    }

    func ignoreDataForCatapult(catapultID: Int) {
        lock.lock() ; defer { lock.unlock() }
        guard let catapultIgnoreInfo = catapultIgnoreInfoDict[catapultID] else { fatalError("No catapult ignore info for \(catapultID)") }
        currentIgnoreList = catapultIgnoreInfo.ignoreIndices
    }
    
    func stopIgnoringDataForCatapult() {
        lock.lock() ; defer { lock.unlock() }
        currentIgnoreList.removeAll()
    }
    
    // MARK: - Projectile Sync
    
    func addProjectile(_ projectile: Projectile) {
        lock.lock() ; defer { lock.unlock() }
        projectileList.append(projectile)
        projectileDataList.append(PhysicsPoolNodeData(projectile: projectile))
    }

    func replaceProjectile(_ projectile: Projectile) {
        lock.lock() ; defer { lock.unlock() }
        for (arrayIndex, oldProjectile) in projectileList.enumerated() where oldProjectile.index == projectile.index {
            projectileList[arrayIndex] = projectile
            return
        }
        fatalError("Cannot find the projectile to replace \(projectile.index)")
    }
    
    // MARK: - Sound Sync
    
    func addSound(gameObjectIndex: Int, soundEvent: CollisionAudioSampler.CollisionEvent) {
        soundDataList.append(CollisionSoundData(gameObjectIndex: gameObjectIndex, soundEvent: soundEvent))
    }
    
}
