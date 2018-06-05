/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Performance debugging markers for use with os_signpost.
*/

import os.signpost

extension StaticString {
    // Signpost names for signposts related loading/starting a game
    static let preload_assets = "PreloadAssets" as StaticString
    static let setup_level = "SetupLevel" as StaticString

    // Signpost names for signposts related to scenekit render loop
    static let render_loop = "RenderLoop" as StaticString
    static let logic_update = "GameLogicUpdate" as StaticString
    static let process_command = "ProcessCommand" as StaticString
    static let physics_sync = "PhysicsSync" as StaticString
    static let post_constraints_update = "PostConstraintsUpdate" as StaticString
    static let render_scene = "RenderScene" as StaticString

    // Signpost names for signposts related to networking
    static let network_action_sent = "NetworkActionSent" as StaticString
    static let network_action_received = "NetworkActionReceived" as StaticString
    static let network_physics_sent = "NetworkPhysicsSent" as StaticString
    static let network_physics_received = "NetworkPhysicsReceived" as StaticString
}

extension OSLog {
    // Custom log objects to use to classify signposts
    static let preload_assets = OSLog(subsystem: "SwiftShot", category: "Preload")
    static let setup_level = OSLog(subsystem: "SwiftShot", category: "LevelSetup")
    static let render_loop = OSLog(subsystem: "SwiftShot", category: "RenderLoop")
    static let network_data_sent = OSLog(subsystem: "SwiftShot", category: "NetworkDataSent")
    static let network_data_received = OSLog(subsystem: "SwiftShot", category: "NetworkDataReceived")
}

extension OSSignpostID {
    // Custom signpost ids for signposts. Same id can be used for signposts that aren't concurrent with each other
    // Signpost ids for signposts related loading/starting a game
    static let preload_assets = OSSignpostID(log: OSLog.preload_assets)
    static let setup_level = OSSignpostID(log: OSLog.setup_level)

    // Signpost ids for signposts related to scenekit render loop
    static let render_loop = OSSignpostID(log: OSLog.render_loop)

    // Signpost ids for signposts related to networking
    static let network_data_sent = OSSignpostID(log: OSLog.network_data_sent)
    static let network_data_received = OSSignpostID(log: OSLog.network_data_received)
}
