/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Wrapper for loading level scenes.
*/

import Foundation
import SceneKit

private let levelsPath = "gameassets.scnassets/levels/"

class GameLevel {
    
    enum Key: String {
        case gateway
        case bridge
        case farm
        case archFort
        case towers
    }
    
    let key: Key
    let name: String
    let identifier: String
    
    // Size of the level in meters
    let targetSize: CGSize
    
    private(set) var placed = false
    
    private var scene: SCNScene?
    private var levelNodeTemplate: SCNNode?
    private var levelNodeClone: SCNNode?
    private var lock = NSLock()
    
    private(set) var lodScale: Float = 1.0
    
    func load() {
        // have to do this
        lock.lock(); defer { lock.unlock() }
        
        // only load once - can be called from preload on another thread, or regular load
        if scene != nil {
            return
        }
        
        guard let sceneUrl = Bundle.main.url(forResource: path, withExtension: "scn") else {
            fatalError("Level \(path) not found")
        }
        do {
            let scene = try SCNScene(url: sceneUrl, options: nil)
            
            // start with animations and physics paused until the board is placed
            // we don't want any animations or things falling over while ARSceneView
            // is driving SceneKit and the view.
            scene.isPaused = true
            
            // walk down the scenegraph and update the children
            scene.rootNode.fixMaterials()
            
            self.scene = scene
            
            // this may not be the root, but lookup the identifier
            // will clone the tree done from this node
            levelNodeTemplate = scene.rootNode.childNode(withName: "_" + identifier, recursively: true)

        } catch {
            fatalError("Could not load level \(sceneUrl): \(error.localizedDescription)")
        }
    }
    
    // an instance of the active level
    var activeLevel: SCNNode? {
        guard let levelNode = levelNodeTemplate else { return nil }
        
        if let levelNodeClone = levelNodeClone {
            return levelNodeClone
        }
        
        levelNodeClone = levelNode.clone()
        return levelNodeClone
    }

    // Scale factor to assign to the level to make it appear 1 unit wide.
    var normalizedScale: Float {
        guard let levelNode = levelNodeTemplate else { return 1.0 }
        let levelSize = levelNode.horizontalSize.x
        guard levelSize > 0 else {
            fatalError("Level size is 0. This might indicate something is wrong with the assets")
        }
        return 1 / levelSize
    }
    
    var path: String { return levelsPath + identifier }
    
    static let gateway = GameLevel(key: .gateway, name: "Gateway", identifier: "level_gateway", targetSize: CGSize(width: 1.5, height: 2.7))
    static let bridge = GameLevel(key: .bridge, name: "Bridge", identifier: "level_bridge", targetSize: CGSize(width: 1.5, height: 2.7))
    static let farm = GameLevel(key: .farm, name: "Farm", identifier: "level_farm", targetSize: CGSize(width: 1.5, height: 2.7))
    static let archFort = GameLevel(key: .archFort, name: "Fort", identifier: "level_archFort", targetSize: CGSize(width: 1.5, height: 2.7))
    static let towers = GameLevel(key: .towers, name: "Towers", identifier: "level_towers", targetSize: CGSize(width: 1.5, height: 2.7))
    
    static let defaultLevel = gateway
    static let allLevels = [gateway, bridge, farm, archFort, towers]
    
    init(key: Key, name: String, identifier: String, targetSize: CGSize) {
        self.key = key
        self.name = name
        self.identifier = identifier
        self.targetSize = targetSize
    }
    
    static func level(at index: Int) -> GameLevel? {
        return index < allLevels.count ? allLevels[index] : nil
    }
    
    static func level(for key: Key) -> GameLevel? {
        return allLevels.first(where: { $0.key == key })
    }
    
    func reset() {
        placed = false
        levelNodeClone = nil
    }
    
    func placeLevel(on node: SCNNode, gameScene: SCNScene, boardScale: Float) {
        guard let activeLevel = activeLevel else { return }
        guard let scene = scene else { return }
        
        // set the environment onto the SCNView
        gameScene.lightingEnvironment.contents = scene.lightingEnvironment.contents
        gameScene.lightingEnvironment.intensity = scene.lightingEnvironment.intensity
        
        // set the cloned nodes representing the active level
        node.addChildNode(activeLevel)
        
        placed = true
        
        // the lod system doesn't honor the scaled camera,
        // so have to fix this manually in fixLevelsOfDetail with inverse scale
        // applied to the screenSpaceRadius
        lodScale = normalizedScale * boardScale
    }
}
