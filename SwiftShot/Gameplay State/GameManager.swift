/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Responsible for tracking the state of the game: which objects are where, who's in the game, etc.
*/

import Foundation
import SceneKit
import GameplayKit
import simd
import AVFoundation
import os.signpost

private let log = Log()

protocol GameManagerDelegate: class {
    func manager(_ manager: GameManager, received: BoardSetupAction, from: Player)
    func manager(_ manager: GameManager, joiningPlayer player: Player)
    func manager(_ manager: GameManager, leavingPlayer player: Player)
    func manager(_ manager: GameManager, joiningHost host: Player)
    func manager(_ manager: GameManager, leavingHost host: Player)
    func managerDidStartGame(_ manager: GameManager)
    func managerDidWinGame(_ manager: GameManager)
    func manager(_ manager: GameManager, hasNetworkDelay: Bool)
}

/// - Tag: GameManager
class GameManager: NSObject {
    
    // actions coming from the main thread/UI layer
    struct TouchEvent {
        var type: TouchType
        var hit: GameRayCastHitInfo
    }
    
    // interactions with the scene must be on the main thread
    let level: GameLevel
    private let scene: SCNScene
    private let levelNode: SCNNode
    
    // use this to access the simulation scaled camera
    private(set) var pointOfViewSimulation: SCNNode

    // these come from ARSCNView currentlys
    let physicsWorld: SCNPhysicsWorld
    private var pointOfView: SCNNode // can be in sim or render space
    
    private var gameBoard: GameBoard?
    private var tableBoxObject: GameObject?
    
    // should be the inverse of the level's world transform
    private var renderToSimulationTransform = float4x4.identity {
        didSet {
            sfxCoordinator.renderToSimulationTransform = renderToSimulationTransform
        }
    }
    // don't execute any code from SCNView renderer until this is true
    private(set) var isInitialized = false
    
    private var hasBeenWon: Bool = false
    private var gamedefs: [String: Any]
    private var gameObjects = Set<GameObject>()      // keep track of all of our entities here
    private var gameCamera: GameCamera?
    private var gameLight: GameLight?
    
    private let session: GameSession?
    private let sfxCoordinator: SFXCoordinator
    private let musicCoordinator: MusicCoordinator
    private let useWallClock: Bool

    var catapults = [Catapult]()
    private let catapultsLock = NSLock()
    private var gameCommands = [GameCommand]()
    private let commandsLock = NSLock()
    private var touchEvents = [TouchEvent]()
    private let touchEventsLock = NSLock()

    private var categories = [String: [GameObject]] ()  // this object can be used to group like items if their gamedefs include a category

    // Refernces to Metal do not compile for the Simulator
#if !targetEnvironment(simulator)
    private var flagSimulation: MetalClothSimulator
#endif
    
    // Physics
    private let physicsSyncData = PhysicsSyncSceneData()
    private let gameObjectPool = GameObjectPool()
    private let interactionManager = InteractionManager()
    private let gameObjectManager = GameObjectManager()
    
    let currentPlayer = UserDefaults.standard.myself

    let isNetworked: Bool
    let isServer: Bool

    var teamANumCatapultsDisabled: Int {
        catapultsLock.lock(); defer { catapultsLock.unlock() }
        return catapults.filter { $0.teamID == .yellow && $0.disabled }.count
    }
    
    var teamBNumCatapultsDisabled: Int {
        catapultsLock.lock(); defer { catapultsLock.unlock() }
        return catapults.filter { $0.teamID == .blue && $0.disabled }.count
    }

    init(sceneView: SCNView, level: GameLevel, session: GameSession?,
         audioEnvironment: AVAudioEnvironmentNode, musicCoordinator: MusicCoordinator) {
        
        // make our own scene instead of using the incoming one
        self.scene = sceneView.scene!
        self.physicsWorld = scene.physicsWorld
        physicsWorld.gravity = SCNVector3(0.0, -10, 0)
        
#if !targetEnvironment(simulator)
        self.flagSimulation = MetalClothSimulator(device: sceneView.device!)
#endif
        
        // this is a node, that isn't attached to the ARSCNView
        self.pointOfView = sceneView.pointOfView!
        self.pointOfViewSimulation = pointOfView.clone()
        
        self.level = level
        
        self.session = session
        self.sfxCoordinator = SFXCoordinator(audioEnvironment: audioEnvironment)
        self.musicCoordinator = musicCoordinator
        self.useWallClock = UserDefaults.standard.synchronizeMusicWithWallClock

        // init entity system
        gamedefs = GameObject.loadGameDefs(file: "gameassets.scnassets/data/entities_def")

        // load the level if it wasn't already pre-loaded
        level.load()

        // start with a copy of the level, never change the originals, since we use original to reset
        self.levelNode = level.activeLevel!

        self.isNetworked = session != nil
        self.isServer = session?.isServer ?? true // Solo game act like a server
        
        super.init()
        
        self.session?.delegate = self
        physicsWorld.contactDelegate = self   // get notified of collisions
    }
    
    func unload() {
        levelNode.removeFromParentNode()
    }
    
    deinit {
        unload()
    }

    weak var delegate: GameManagerDelegate?

    func send(boardAction: BoardSetupAction) {
        session?.send(action: .boardSetup(boardAction))
    }

    func send(boardAction: BoardSetupAction, to player: Player) {
        session?.send(action: .boardSetup(boardAction), to: player)
    }

    func send(gameAction: GameAction) {
        session?.send(action: .gameAction(gameAction))
    }

    // MARK: - processing touches
    func handleTouch(type: TouchType, hit: GameRayCastHitInfo) {
        guard !UserDefaults.standard.spectator else { return }
        touchEventsLock.lock(); defer { touchEventsLock.unlock() }
        touchEvents.append(TouchEvent(type: type, hit: hit))
    }
    
    func updateCamera(cameraInfo: CameraInfo) {
        if gameCamera == nil {
            // need the real render camera in order to set rendering state
            let camera = pointOfView
            camera.name = "GameCamera"
            gameCamera = GameCamera(camera)
            _ = initGameObject(for: camera)
            
            gameCamera?.updateProps()
        }
        // transfer props to the current camera
        gameCamera?.transferProps()

        interactionManager.updateAll(cameraInfo: cameraInfo)
    }

    // MARK: - inbound from network
    private func process(command: GameCommand) {
        os_signpost(type: .begin, log: .render_loop, name: .process_command, signpostID: .render_loop,
                    "Action : %s", command.action.description)
        switch command.action {
        case .gameAction:
            interactionManager.handleGameCommandAll(self, gameCommand: command)
        case .boardSetup(let boardAction):
            if let player = command.player {
                delegate?.manager(self, received: boardAction, from: player)
            }
        case .physics(let physicsData):
            physicsSyncData.receive(packet: physicsData)
        case .startGameMusic(let timeData):
            // Start music at the correct place.
            if let player = command.player {
                handleStartGameMusic(timeData, from: player)
            }
        }
        os_signpost(type: .end, log: .render_loop, name: .process_command, signpostID: .render_loop,
                    "Action : %s", command.action.description)
    }
    
    // MARK: update
    // Called from rendering loop once per frame
    /// - Tag: GameManager-update
    func update(timeDelta: TimeInterval) {
        processCommandQueue()
        processTouches()
        syncPhysics()
        
        // removeFallenNodes only run once every 6 frames since it was found to be heavy on performance
        if GameTime.frameCount % 6 == 0 {
            removeFallenNodes(node: levelNode)
        }
#if !targetEnvironment(simulator)
        flagSimulation.update(levelNode)
#endif
        
        gameObjectManager.update()

        for entity in gameObjects {
            for component in entity.components where component is UpdatableComponent {
                guard let updateableComponent = component as? UpdatableComponent else { continue }
                updateableComponent.update(deltaTime: timeDelta, isServer: isServer)
            }
        }
    }

    let maxCatapults = 6
    
    // keep track of which catapults we can see as candidates for grabbing/highlighting
    func updateCatapultVisibility(renderer: SCNSceneRenderer, camera: SCNNode) {
        catapultsLock.lock(); defer { catapultsLock.unlock() }
        guard !catapults.isEmpty && catapults.count == maxCatapults else { return }
        
        // track which are visible
        for catapult in catapults {
            // projectile part should be available, otherwise this is not highlightable
            guard let projectile = catapult.projectile, var visGeo = projectile.findNodeWithGeometry() else {
                catapult.isVisible = false
                continue
            }
            
            // use bigger geo when already highlighted to avoid highlight from flipping back and fourth
            if catapult.isHighlighted, let highlight = catapult.highlightObject {
                visGeo = highlight
            }
            
            // this is done in scaled space
            let isVisible = renderer.isNode(visGeo.findNodeWithGeometry()!, insideFrustumOf: camera)
            catapult.isVisible = isVisible
            
            catapult.projectedPos = float3(renderer.projectPoint(catapult.base.worldPosition))
            catapult.projectedPos.x /= Float(UIScreen.main.bounds.width)
            catapult.projectedPos.y /= Float(UIScreen.main.bounds.height)
        }
    }

    private func processCommandQueue() {
        // retrieving the command should happen with the lock held, but executing
        // it should be outside the lock.
        // inner function lets us take advantage of the defer keyword
        // for lock management.
        func nextCommand() -> GameCommand? {
            commandsLock.lock(); defer { commandsLock.unlock() }
            if gameCommands.isEmpty {
                return nil
            } else {
                return gameCommands.removeFirst()
            }
        }

        while let command = nextCommand() {
            process(command: command)
        }
    }

    private func processTouches() {
        func nextTouch() -> TouchEvent? {
            touchEventsLock.lock(); defer { touchEventsLock.unlock() }
            if touchEvents.isEmpty {
                return nil
            } else {
                return touchEvents.removeFirst()
            }
        }

        while let touch = nextTouch() {
            process(touch)
        }
    }

    private func process(_ touch: TouchEvent) {
        interactionManager.handleTouch(type: touch.type, hit: touch.hit)
    }

    func queueAction(gameAction: GameAction) {
        commandsLock.lock(); defer { commandsLock.unlock() }
        gameCommands.append(GameCommand(player: currentPlayer, action: .gameAction(gameAction)))
    }

    private func syncPhysics() {
        os_signpost(type: .begin, log: .render_loop, name: .physics_sync, signpostID: .render_loop,
                    "Physics sync started")
        if isNetworked && physicsSyncData.isInitialized {
            if isServer {
                let physicsData = physicsSyncData.generateData()
                session?.send(action: .physics(physicsData))
            } else {
                physicsSyncData.updateFromReceivedData()
            }
        }
        os_signpost(type: .end, log: .render_loop, name: .physics_sync, signpostID: .render_loop,
                    "Physics sync finished")
        
    }
    
    func playWinSound() {
        delegate?.managerDidWinGame(self)
    }

    func startGameMusic(from interaction: Interaction) {
        log.debug("3-2-1-GO music effect is done, time to start the game music")
        startGameMusicEverywhere()
    }

    // Status for SceneViewController to query and display UI interaction
    func canGrabACatapult(cameraRay: Ray) -> Bool {
        guard let catapultInteraction = interactionManager.interaction(of: CatapultInteraction.self) as? CatapultInteraction else {
            return false
        }
        return catapultInteraction.canGrabAnyCatapult(cameraRay: cameraRay)
    }
    
    func displayWin() {
        guard let victory = interactionManager.interaction(of: VictoryInteraction.self) as? VictoryInteraction else {
            fatalError("No Victory Effect")
        }
        victory.activateVictory()
    }
    
    func isCurrentPlayerGrabbingACatapult() -> Bool {
        let interaction = interactionManager.interaction(of: GrabInteraction.self)
        if let grabInteraction = interaction as? GrabInteraction,
            let grabbedGrabbable = grabInteraction.grabbedGrabbable,
            grabbedGrabbable as? Catapult != nil {
            return true
        }
        return false
    }
    
    // Configures the node from the level to be placed on the provided board.
    func addLevel(to node: SCNNode, gameBoard: GameBoard) {
        self.gameBoard = gameBoard
        
        level.placeLevel(on: node, gameScene: scene, boardScale: gameBoard.scale.x)
        
        updateRenderTransform()
        
        if let activeLevel = level.activeLevel {
            fixLevelsOfDetail(activeLevel)
        }
    }
    
    func fixLevelsOfDetail(_ node: SCNNode) {
        // set screenSpacePercent to 0 for high-poly lod always,
        // or to much greater than 1 for low-poly lod always
        let screenSpacePercent: Float = 0.15
        var screenSpaceRadius = SCNNode.computeScreenSpaceRadius(screenSpacePercent: screenSpacePercent)
        
        // The lod system doesn't account for camera being scaled
        // so do it ourselves.  Here we remove the scale.
        screenSpaceRadius /= level.lodScale
        
        let showLOD = UserDefaults.standard.showLOD
        node.fixLevelsOfDetail(screenSpaceRadius: screenSpaceRadius, showLOD: showLOD)
    }
    
    // call this if the level moves from AR changes or user moving/scaling it
    func updateRenderTransform() {
        guard let gameBoard = self.gameBoard else { return }
        
        // Scale level to normalized scale (1 unit wide) for rendering
        let levelNodeTransform = float4x4(scale: level.normalizedScale)
        renderToSimulationTransform = levelNodeTransform.inverse * gameBoard.simdWorldTransform.inverse
    }

    // Initializes all the objects and interactions for the game, and prepares
    // to process user input.
    func start() {
        // Now we initialize all the game objects and interactions for the game.

        // reset the index that we assign to GameObjects.
        // test to make sure no GameObjects are built prior
        // also be careful that the server increments the counter for new nodes
        GameObject.resetIndexCounter()
        categories = [String: [GameObject]] ()
        
        initializeGameObjectPool()
        
        initializeLevel()
        initBehaviors()
        
        // Initialize interactions that add objects to the level
        initializeInteractions()

        tableBoxObject = addTableTopOcclusionBox(level: levelNode)
        physicsSyncData.delegate = self
        
        // Start advertising game
        if let session = session, session.isServer {
            session.startAdvertising()
        }
        
        delegate?.managerDidStartGame(self)

        startGameMusicEverywhere()

        isInitialized = true
    }

    func releaseLevel() {
        // remove all audio players added to AVAudioEngine.
        sfxCoordinator.removeAllAudioSamplers()
        level.reset()
    }
    
    func initBehaviors() {
        // after everything is setup, add the behaviors if any
        for gameObject in gameObjects {
            
            // update constraints
            for component in gameObject.components where component is PhysicsBehaviorComponent {
                if let behaviorComponent = component as? PhysicsBehaviorComponent {
                    behaviorComponent.initBehavior(levelRoot: levelNode, world: physicsWorld)
                }
            }
        }
    }

    // MARK: - Table Occlusion

    // Create an opaque object representing the table used to occlude falling objects
    private func addTableTopOcclusionBox(level: SCNNode) -> GameObject {
        let height: Float = 20
        let tableBoxShape = SCNBox(width: 15, height: CGFloat(height), length: 27, chamferRadius: 0.01)
        let tableBoxNode = SCNNode(geometry: tableBoxShape)
        
        tableBoxNode.setNodeToOccluder()
        level.addChildNode(tableBoxNode)
        tableBoxNode.simdPosition = float3(0.0, -height * 0.5 - 0.05, 0.0) // avoid z-fight with ShadowPlane
        
        // scale up the physics shape scale so that objects land on the shadow plane
        let physicsShape = SCNPhysicsShape(geometry: tableBoxShape, options: [SCNPhysicsShape.Option.scale: 1.0025])
        let physicsBody = SCNPhysicsBody(type: SCNPhysicsBodyType.static, shape: physicsShape)
        physicsBody.contactTestBitMask = CollisionMask([.ball, .rigidBody]).rawValue
        tableBoxNode.physicsBody = physicsBody
        tableBoxNode.name = "table"

        // make a table object so we can attach audio component to it
        let tableObject = initGameObject(for: tableBoxNode)
        return tableObject
    }
    
    // MARK: - Remove Out of Bound Nodes

    // go through whole scene to remove objects that are far away
    private func removeFallenNodes(node: SCNNode) {
        // remove this node if we have to and make it invisible, but don't delete it and mess up the networking indices
        if shouldRemove(node: node) {
            node.removeFromParentNode()
        } else {    // if we didn't move then check children
            for child in node.childNodes {
                removeFallenNodes(node: child)
            }
        }
    }
    
    // logic to check if we should really remove a node or not
    private func shouldRemove(node: SCNNode) -> Bool {
        // Only remove dynamic node
        guard node.physicsBody?.type == .dynamic else { return false }
        
        // check past min/max bounds
        // the border was chosen experimentally to see what feels good
        let minBounds = float3(-80.0, -10.0, -80.0) // -10.0 represents 1.0 meter high table
        let maxBounds = float3(80.0, 1000.0, 80.0)
        let position = node.presentation.simdWorldPosition
        
        // this is only checking position, but bounds could be offset or bigger
        return min(position, minBounds) != minBounds ||
               max(position, maxBounds) != maxBounds
    }

    // MARK: - Initialize Game Functions
    private func teamName(for node: SCNNode) -> String? {
        guard let name = node.name else { return nil }

        // set to A or B, don't set blocks to teamAA, AB, AC
        if name == "_teamA" || name == "_teamB" {
            let teamName = name
            return teamName.isEmpty ? nil : String(teamName)
        }

        return nil
    }

    // Walk all the nodes looking for actual objects.
    private func enumerateHierarchy(_ node: SCNNode, teamName: String? = nil) {
        // If the node has no name or a name does not contain
        // a type identifier, we look at its children.
        guard let name = node.name, let type = node.typeIdentifier else {
            let extractedName = self.teamName(for: node)
            let newTeamName = extractedName ?? teamName
            for child in node.childNodes {
                enumerateHierarchy(child, teamName: newTeamName)
            }
            return
        }

        configure(node: node, name: name, type: type, team: teamName)
    }

    private func configure(node: SCNNode, name: String, type: String, team: String?) {
        // For nodes with types, we create at most one gameObject, configured
        // based on the node type.
        
        // only report team blocks
        if team != nil {
            log.debug("configuring \(name) on team \(team!)")
        }
        
        switch type {
        case "catapult":
            // replaces the placeholder node with a working catapult
            let catapultNode = Catapult.replaceCatapultPlaceholder(node)

            // Create Catapult GameObject
            let identifier = catapults.count
            let catapult = Catapult(catapultNode, sfxCoordinator: sfxCoordinator, identifier: identifier, gamedefs: gamedefs)
            gameObjects.insert(catapult)
            setupAudioComponent(for: catapult)

            catapultNode.name = name
            
            catapult.delegate = self
            catapults.append(catapult)

            catapult.updateProps()
            
            physicsSyncData.addCatapultIgnoreNode(node: catapult.base, catapultID: catapult.catapultID)
            
        case "ShadowPlane":
            // don't add a game object, but don't visit it either
            return
            
        case "ShadowLight":
            if gameLight == nil {
                node.name = "GameLight"
                let light = initGameObject(for: node)
                gameObjects.insert(light)
                gameLight = GameLight(node)
                gameLight?.updateProps()
            }
            gameLight?.transferProps()
            return

        default:
            // This handles all other objects, including blocks, reset switches, etc.
            // All special functionality is defined in entities_def.json file
            
            // can't removing these throw off the object index
            // if not all clients remove these
            switch type {
            case "cloud":
                if !UserDefaults.standard.showClouds {
                    node.removeFromParentNode()
                    return
                }
            case "flag":
                if !UserDefaults.standard.showFlags {
                   node.removeFromParentNode()
                    return
                } else {
#if !targetEnvironment(simulator)
                    flagSimulation.createFlagSimulationFromNode(node)
#endif
                    }
            case "resetSwitch":
                if !UserDefaults.standard.showResetLever {
                    node.removeFromParentNode()
                    return
                }
            default:
                break
            }
            
            let gameObject = initGameObject(for: node)
            
            // hardcoded overrides for physics happens here
            if !gameObject.usePredefinedPhysics {
                // Constrain the angularVelocity until first ball fires.
                // This is done to stabilize the level.
                gameObject.physicsNode?.physicsBody?.simdAngularVelocityFactor = float3(0.0, 0.0, 0.0)
                
                if let physicsNode = gameObject.physicsNode,
                    let physicsBody = physicsNode.physicsBody {
                        let density = gameObject.density
                        if density > 0 {
                            physicsNode.calculateMassFromDensity(name: name, density: density)
                        }
                        physicsBody.resetTransform()
                }
            }
        
            // add to network synchronization code
            if let physicsNode = gameObject.physicsNode {
                physicsSyncData.addNode(node: physicsNode)
                
                if gameObject.isBlockObject {
                    gameObjectManager.addBlockObject(block: gameObject)
                }
            }
            
            if gameObject.categorize {
                if categories[gameObject.category] == nil {
                    categories[gameObject.category] = [GameObject]()
                }
                categories[gameObject.category]!.append(gameObject)
            }
        }
    }
    
    private func postUpdateHierarchy(_ node: SCNNode) {
        if let nameRestore = node.value(forKey: "nameRestore") as? String {
            node.name = nameRestore
        }
        
        for child in node.childNodes {
            postUpdateHierarchy(child)
        }
    }
    
    private func initializeGameObjectPool() {
        gameObjectPool.projectileDelegate = self
        gameObjectPool.createPoolObjects(delegate: self)
        
        // GameObjectPool has a fixed number of items which we need to add to physicsSyncData and gameObjectManager
        for projectile in gameObjectPool.projectilePool {
            physicsSyncData.addProjectile(projectile)
            gameObjectManager.addProjectile(projectile)
            setupAudioComponent(for: projectile)
        }
    }

    private func setupAudioComponent(for object: GameObject) {
        if let audioComponent = object.component(ofType: GameAudioComponent.self) {
            sfxCoordinator.setupGameAudioComponent(audioComponent)
            audioComponent.delegate = self
        }
    }
    
    private func initializeLevel() {
        // enumerateHierarchy is recursive and may find catapults at any level
        // putting the lock outside ensures that the win condition won't be evaluated
        // on an incomplete set of catapults.
        catapultsLock.lock(); defer { catapultsLock.unlock() }
        
        enumerateHierarchy(levelNode)

        // do post init functions here
        postUpdateHierarchy(levelNode)
    }

    private func initializeInteractions() {
        // Grab Interaction
        let grabInteraction = GrabInteraction(delegate: self)
        interactionManager.addInteraction(grabInteraction)
        
        // Highlight Interaction
        let highlightInteraction = HighlightInteraction(delegate: self)
        highlightInteraction.grabInteraction = grabInteraction
        highlightInteraction.sfxCoordinator = sfxCoordinator
        interactionManager.addInteraction(highlightInteraction)

        // Catapult Interaction
        let catapultInteraction = CatapultInteraction(delegate: self)
        catapultInteraction.grabInteraction = grabInteraction
        interactionManager.addInteraction(catapultInteraction)

        // Fill Catapult Interaction with catapults
        guard !catapults.isEmpty else { fatalError("Catapult not initialized") }
        for catapult in catapults {
            catapultInteraction.addCatapult(catapult)
        }

        // Catapult Disable Interaction
        interactionManager.addInteraction(CatapultDisableInteraction(delegate: self))
        
        // Vortex
        let vortex = VortexInteraction(delegate: self)
        vortex.vortexActivationDelegate = catapultInteraction
        vortex.sfxCoordinator = sfxCoordinator
        vortex.musicCoordinator = musicCoordinator
        interactionManager.addInteraction(vortex)
        
        // Lever
        let lever = LeverInteraction(delegate: self)
        var switches = [GameObject]()
        if let processedSwitches = categories["reset"] {
            switches = processedSwitches
        }
        lever.setup(resetSwitches: switches, interactionToActivate: vortex)
        lever.sfxCoordinator = sfxCoordinator
        interactionManager.addInteraction(lever)
        
        // Victory
        interactionManager.addInteraction(VictoryInteraction(delegate: self))
    }
    
    // MARK: - Physics scaling
    func copySimulationCamera() {
        // copy the POV camera to minimize the need to lock, this is right after ARKit updates it in
        // the render thread, and before we scale the actual POV camera for rendering
        pointOfViewSimulation.simdWorldTransform = pointOfView.simdWorldTransform
    }
    
    func scaleCameraToRender() {
        pointOfView.simdWorldTransform = renderToSimulationTransform * pointOfView.simdWorldTransform
    }

    func scaleCameraToSimulation() {
        pointOfView.simdWorldTransform = pointOfViewSimulation.simdWorldTransform
    }
    
    func renderSpacePositionToSimulationSpace(pos: float3) -> float3 {
        return (renderToSimulationTransform * float4(pos, 1.0)).xyz
    }
    
    func renderSpaceDirectionToSimulationSpace(dir: float3) -> float3 {
        return (renderToSimulationTransform * float4(dir, 0.0)).xyz
    }

    func renderSpaceTransformToSimulationSpace(transform: float4x4) -> float4x4 {
        return renderToSimulationTransform * transform
    }
    
    func simulationSpacePositionToRenderSpace(pos: float3) -> float3 {
        return (renderToSimulationTransform.inverse * float4(pos, 1.0)).xyz
    }

    func initGameObject(for node: SCNNode) -> GameObject {
        let gameObject = GameObject(node: node, gamedefs: gamedefs)
        
        gameObjects.insert(gameObject)
        setupAudioComponent(for: gameObject)
        return gameObject
    }

    // after collision we care about is detected, we check for any collision related components and process them
    func didCollision(nodeA: SCNNode, nodeB: SCNNode, pos: float3, impulse: CGFloat) {
        // let any collision handling components on nodeA respond to the collision with nodeB

        if let entity = nodeA.nearestParentGameObject() {
            for component in entity.components where component is CollisionHandlerComponent {
                if let handler = component as? CollisionHandlerComponent {
                    handler.didCollision(manager: self, node: nodeA, otherNode: nodeB, pos: pos, impulse: impulse)
                }
            }
        }
        
        // let any collision handling components in nodeB respond to the collision with nodeA
        if let entity = nodeB.nearestParentGameObject() {
            for component in entity.components where component is CollisionHandlerComponent {
                if let handler = component as? CollisionHandlerComponent {
                    handler.didCollision(manager: self, node: nodeB, otherNode: nodeA, pos: pos, impulse: impulse)
                }
            }
        }
        
        interactionManager.didCollision(nodeA: nodeA, nodeB: nodeB, pos: pos, impulse: impulse)
    }
    
    func didBeginContact(nodeA: SCNNode, nodeB: SCNNode, pos: float3, impulse: CGFloat) {
        interactionManager.didCollision(nodeA: nodeA, nodeB: nodeB, pos: pos, impulse: impulse)
    }
    
    func onDidApplyConstraints(renderer: SCNSceneRenderer) {
        gameObjectManager.onDidApplyConstraints(renderer: renderer)
    }
    
    func playPhysicsSound(objectIndex: Int, soundEvent: CollisionAudioSampler.CollisionEvent) {
        // Find the correct GameObject and play the collision sound
        for gameObject in gameObjects where gameObject.index == objectIndex {
            if let audioComponent = gameObject.component(ofType: GameAudioComponent.self) {
                audioComponent.playCollisionSound(soundEvent)
            }
            return
        }
    }

    /// Start the game music on the server device and all connected
    /// devices
    func startGameMusicEverywhere() {
        guard isServer else { return }

        // Start music locally:
        let timeData = startGameMusicNow()
        handleStartGameMusic(timeData, from: currentPlayer)

        // Start the game music on all connected clients:
        session?.send(action: .startGameMusic(timeData))
    }

    func startGameMusic(for player: Player) {
        // Begin by handling an empty message. Our timestamp will be added and
        // sent in ping/pong to estimate latency.
        handleStartGameMusic(StartGameMusicTime(startNow: false, timestamps: []), from: player)
    }

    func startGameMusicNow() -> StartGameMusicTime {
        let cal = Calendar(identifier: .gregorian)
        let dc = cal.dateComponents([.year, .month, .day], from: Date())
        let reference = cal.date(from: dc)! // chose a reference date of the start of today.
        let now = Date().timeIntervalSince(reference)
        if useWallClock {
            return StartGameMusicTime(startNow: true, timestamps: [now])
        } else {
            return StartGameMusicTime(startNow: true, timestamps: [0])
        }
    }

    func handleStartGameMusic(_ timeData: StartGameMusicTime, from player: Player) {
        if useWallClock {
            handleStartGameMusicWithWallClock(timeData, from: player)
        } else {
            handleStartGameMusicWithLatencyEstimate(timeData, from: player)
        }
    }

    func handleStartGameMusicWithWallClock(_ timeData: StartGameMusicTime, from player: Player) {
        guard let session = session else {
            fatalError("Need a game session")
        }
        // This synchronization method uses the wall clock of the two devices. It
        // relies on them both having a very accurate clock, which really may not be
        // the case.
        //
        // Choose a time reference closer to the present so that milliseconds since
        // this reference can be expressed in UInt32.

        let cal = Calendar(identifier: .gregorian)
        let dc = cal.dateComponents([.year, .month, .day], from: Date())
        let reference = cal.date(from: dc)! // chose a reference date of the start of today.
        let now = Date().timeIntervalSince(reference)

        if timeData.startNow {
            guard timeData.timestamps.count == 1 else {
                fatalError("expected to have serverTimestamps.count == 1")
            }
            let startWallTime = timeData.timestamps[0]
            let position = now - startWallTime
            log.debug("handleStartGameMusic (either), playing music from start time \(position)")
            musicCoordinator.playMusic(name: "music_gameplay", startTime: position)
        } else {
            if isServer {
                let position = musicCoordinator.currentMusicTime()
                let newData = StartGameMusicTime(startNow: true, timestamps: [now - position])
                session.send(action: .startGameMusic(newData), to: player)
            }
        }
    }

    func handleStartGameMusicWithLatencyEstimate(_ timeData: StartGameMusicTime, from player: Player) {
        guard let session = session else {
            fatalError("Need a game session")
        }
        // This synchronization method uses an echoed message (like ping) to calculate
        // the time taken to send a message to the other device and back and make an
        // estimate of latency based on the average of a few of these round trips.

        let cal = Calendar(identifier: .gregorian)
        let dc = cal.dateComponents([.year, .month, .day], from: Date())
        let reference = cal.date(from: dc)! // chose a reference date of the start of today.
        let now = Date().timeIntervalSince(reference)

        if timeData.startNow {
            guard timeData.timestamps.count == 1 else {
                fatalError("expected to have serverTimestamps.count == 1")
            }
            let position = timeData.timestamps[0]
            log.debug("handleStartGameMusic (either), playing music from start time \(position)")
            musicCoordinator.playMusic(name: "music_gameplay", startTime: position)
        } else {
            if isServer {
                let numberOfRoundTripsToEstimateLatency = 4 // must be less than 16 to fit in data structure.
                // A round trip has a start and an end time, so we want one more than this in the array.
                if timeData.timestamps.count < numberOfRoundTripsToEstimateLatency + 1 {
                    var timestamps = timeData.timestamps
                    timestamps.append(now)
                    let newData = StartGameMusicTime(startNow: false, timestamps: timestamps)
                    session.send(action: .startGameMusic(newData), to: player)
                } else {
                    // Estimate the latency as the time taken for a few messages to go across and back
                    // divided by the number of ping/pongs and assuming the halfway point.
                    let count = timeData.timestamps.count
                    let latencyEstimate = 0.5 * (timeData.timestamps[count - 1] - timeData.timestamps[0]) / TimeInterval(count - 1)
                    let position = musicCoordinator.currentMusicTime()
                    let newData = StartGameMusicTime(startNow: true, timestamps: [position + latencyEstimate])
                    session.send(action: .startGameMusic(newData), to: player)
                }
            } else {
                // echo the same message back to the server
                log.debug("handleStartGameMusic (client), sending action \(timeData) to player \(player)")
                session.send(action: .startGameMusic(timeData), to: player)
            }
        }
    }

    func updateSessionLocation(_ location: GameTableLocation) {
        session?.updateLocation(newLocation: location)
    }
}

extension GameManager: GameSessionDelegate {
    func gameSession(_ session: GameSession, received command: GameCommand) {
        commandsLock.lock(); defer { commandsLock.unlock() }
        // Check if the action received is used to setup the board
        // If so, process it and don't wait for the next update cycle to unqueue the event
        // The GameManager is paused at that time of joining a game
        if case Action.boardSetup(_) = command.action {
            process(command: command)
        } else {
            gameCommands.append(command)
        }
    }
    
    func gameSession(_ session: GameSession, joining player: Player) {
        if player == session.host {
            delegate?.manager(self, joiningHost: player)
        } else {
            delegate?.manager(self, joiningPlayer: player)
        }
    }
    
    func gameSession(_ session: GameSession, leaving player: Player) {
        if player == session.host {
            delegate?.manager(self, leavingHost: player)
        } else {
            delegate?.manager(self, leavingPlayer: player)
        }
    }
}

extension GameManager: CatapultDelegate {
    func catapultDidBreak(_ catapult: Catapult, justKnockedout: Bool, vortex: Bool) {
        if justKnockedout {
            sfxCoordinator.playCatapultBreak(catapult: catapult, vortex: vortex)
        }
        gameObjectManager.addBlockObject(block: catapult)
    }

    func catapultDidBeginGrab(_ catapult: Catapult) {
        // start haptics and sounds too for each catapult
        sfxCoordinator.playGrabBall(catapult: catapult)
    }
    
    func catapultDidMove(_ catapult: Catapult, stretchDistance: Float, stretchRate: Float) {
        // sounds - balloon squeak
        // haptics - vibrate with more energy depending on pull
        let playHaptic = isCurrentPlayerGrabbingACatapult()
        sfxCoordinator.playStretch(catapult: catapult, stretchDistance: stretchDistance, stretchRate: stretchRate, playHaptic: playHaptic)
    }
    
    func catapultDidLaunch(_ catapult: Catapult, velocity: GameVelocity) {
        // sounds - twang of bow or rubber band
        // haptics - big launch vibrate
        sfxCoordinator.stopStretch(catapult: catapult)
        let playHaptic = isCurrentPlayerGrabbingACatapult()
        sfxCoordinator.playLaunch(catapult: catapult, velocity: velocity, playHaptic: playHaptic)
        if !UserDefaults.standard.hasOnboarded, playHaptic {
            UserDefaults.standard.hasOnboarded = true
        }
    }
}

extension GameManager: InteractionDelegate {
    var projectileDelegate: ProjectileDelegate { return self }
    
    var allBlockObjects: [GameObject] {
        return gameObjectManager.blockObjects
    }
    
    func removeTableBoxNodeFromLevel() {
        tableBoxObject?.objectRootNode.removeFromParentNode()
        guard let shadowPlane = levelNode.childNode(withName: "ShadowPlane", recursively: true) else { return }
        shadowPlane.runAction(.fadeOut(duration: 0.5))
    }
    
    func removeAllPhysicsBehaviors() {
        physicsWorld.removeAllBehaviors()
    }
        
    func addInteraction(_ interaction: Interaction) {
        interactionManager.addInteraction(interaction)
    }
    
    func addNodeToLevel(_ node: SCNNode) {
        levelNode.addChildNode(node)
    }
    
    func addNodeToPhysicsSync(_ node: SCNNode) {
        physicsSyncData.addNode(node: node)
    }
    
    func spawnProjectile() -> Projectile {
        let projectile = gameObjectPool.spawnProjectile()
        physicsSyncData.replaceProjectile(projectile)
        gameObjectManager.replaceProjectile(projectile)
        // It would be better to use a preallocated audio sampler here if
        // loading a new one takes too long. But it appears ok for now...
        setupAudioComponent(for: projectile)
        return projectile
    }
    
    func createProjectile() -> Projectile {
        return gameObjectPool.createProjectile(for: .cannonball, index: nil)
    }
    
    func gameObjectPoolCount() -> Int { return gameObjectPool.initialPoolCount }
    
    func addCatapultPhysicsIgnoreNodeToLevel(_ node: SCNNode, catapultID: Int) {
        levelNode.addChildNode(node)
        physicsSyncData.addCatapultIgnoreNode(node: node, catapultID: catapultID)
    }
    
    func ignorePhysicsOnCatapult(_ catapultID: Int) {
        physicsSyncData.ignoreDataForCatapult(catapultID: catapultID)
    }
    
    func stopIgnoringPhysicsOnCatapult() {
        physicsSyncData.stopIgnoringDataForCatapult()
    }
    
    func dispatchActionToServer(gameAction: GameAction) {
        if isServer {
            queueAction(gameAction: gameAction)
        } else {
            send(gameAction: gameAction) // send to host
        }
    }
    
    func dispatchActionToAll(gameAction: GameAction) {
        queueAction(gameAction: gameAction)
        send(gameAction: gameAction)
    }
    
    func serverDispatchActionToAll(gameAction: GameAction) {
        if isServer {
            send(gameAction: gameAction)
        }
    }
    
    func dispatchToPlayer(gameAction: GameAction, player: Player) {
        if currentPlayer == player {
            queueAction(gameAction: gameAction)
        } else {
            session?.send(action: .gameAction(gameAction), to: player)
        }
    }
}

extension GameManager: ProjectileDelegate {
    func despawnProjectile(_ projectile: Projectile) {
        gameObjectPool.despawnProjectile(projectile)
    }
    
    func addParticles(_ particlesNode: SCNNode, worldPosition: float3) {
        levelNode.addChildNode(particlesNode)
        particlesNode.simdWorldPosition = worldPosition
    }
    
    func addNodeToLevel(node: SCNNode) {
        levelNode.addChildNode(node)
    }
}

extension GameManager: PhysicsSyncSceneDataDelegate {
    func hasNetworkDelayStatusChanged(hasNetworkDelay: Bool) {
        delegate?.manager(self, hasNetworkDelay: hasNetworkDelay)
    }
    
    func spawnProjectile(objectIndex: Int) -> Projectile {
        let projectile = gameObjectPool.spawnProjectile(objectIndex: objectIndex)
        projectile.delegate = self
        
        levelNode.addChildNode(projectile.objectRootNode)
        gameObjectManager.replaceProjectile(projectile)
        return projectile
    }
}

extension GameManager: GameObjectPoolDelegate {
    var gamedefinitions: [String: Any] { return gamedefs }
    
    func onSpawnedProjectile() {
        // Release all physics contraints
        for block in gameObjectManager.blockObjects {
            block.physicsNode?.physicsBody?.simdAngularVelocityFactor = float3(1.0, 1.0, 1.0)
        }
    }
}

extension GameManager: GameAudioComponentDelegate {
    func gameAudioComponent(_ component: GameAudioComponent, didPlayCollisionEvent collisionEvent: CollisionAudioSampler.CollisionEvent) {
        // For the server device, play the sound locally immediately.
        if isServer {
            component.playCollisionSound(collisionEvent)
            
            // Add to the network sync
            guard let gameObject = component.entity as? GameObject else { fatalError("Component is not attached to GameObject") }
            physicsSyncData.addSound(gameObjectIndex: gameObject.index, soundEvent: collisionEvent)
        }
    }
}

extension GameManager: SCNPhysicsContactDelegate {
    func physicsWorld(_ world: SCNPhysicsWorld, didEnd contact: SCNPhysicsContact) {
        self.didCollision(nodeA: contact.nodeA, nodeB: contact.nodeB,
                             pos: float3(contact.contactPoint), impulse: contact.collisionImpulse)
    }
    
    func physicsWorld(_ world: SCNPhysicsWorld, didBegin contact: SCNPhysicsContact) {
        self.didBeginContact(nodeA: contact.nodeA, nodeB: contact.nodeB,
                                pos: float3(contact.contactPoint), impulse: contact.collisionImpulse)
    }
}
