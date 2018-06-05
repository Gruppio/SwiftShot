/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Manages the multipeer networking for a game.
*/

import Foundation
import MultipeerConnectivity
import simd
import os.signpost

private let log = Log()
private let locationKey = "LocationAttributeName"

protocol GameSessionDelegate: class {
    func gameSession(_ session: GameSession, received command: GameCommand)
    func gameSession(_ session: GameSession, joining player: Player)
    func gameSession(_ session: GameSession, leaving player: Player)
}

/// - Tag: GameSession
class GameSession: NSObject {

    let myself: Player
    private var peers: Set<Player> = []

    let isServer: Bool
    let session: MCSession
    var location: GameTableLocation?
    let host: Player

    weak var delegate: GameSessionDelegate?

    private var serviceAdvertiser: MCNearbyServiceAdvertiser?

    private lazy var encoder: PropertyListEncoder = {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }()
    private lazy var decoder = PropertyListDecoder()

    init(myself: Player, asServer: Bool, location: GameTableLocation?, host: Player) {
        self.myself = myself
        let encryptionPreference: MCEncryptionPreference = UserDefaults.standard.useEncryption ? .required : .none
        self.session = MCSession(peer: myself.peerID, securityIdentity: nil, encryptionPreference: encryptionPreference)
        self.isServer = asServer
        self.location = location
        self.host = host
        super.init()
        self.session.delegate = self
    }

    // for use when acting as game server
    func startAdvertising() {
        guard serviceAdvertiser == nil else { return } // already advertising
        
        let discoveryInfo: [String: String]?
        if let location = location {
            discoveryInfo = [locationKey: String(location.identifier)]
        } else {
            discoveryInfo = nil
        }
        let advertiser = MCNearbyServiceAdvertiser(peer: myself.peerID,
                                                   discoveryInfo: discoveryInfo,
                                                   serviceType: SwiftShotGameService.playerService)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        serviceAdvertiser = advertiser
    }

    func stopAdvertising() {
        log.info("stop advertising")
        serviceAdvertiser?.stopAdvertisingPeer()
        serviceAdvertiser = nil
    }

    // for beacon use
    func updateLocation(newLocation: GameTableLocation) {
        location = newLocation
    }

    // MARK: Actions
    func send(action: Action) {
        guard !peers.isEmpty else { return }
        do {
            var bits = WritableBitStream()
            try action.encode(to: &bits)
            let data = bits.packData()
            let peerIds = peers.map { $0.peerID }
            try session.send(data, toPeers: peerIds, with: .reliable)
            if action.description != "physics" {
                 os_signpost(type: .event, log: .network_data_sent, name: .network_action_sent, signpostID: .network_data_sent,
                             "Action : %s", action.description)
            } else {
                let bytes = Int32(exactly: data.count) ?? Int32.max
                os_signpost(type: .event, log: .network_data_sent, name: .network_physics_sent, signpostID: .network_data_sent,
                            "%d Bytes Sent", bytes)
            }
        } catch {
            log.error("sending failed: \(error)")
        }
    }

    func send(action: Action, to player: Player) {
        do {
            var bits = WritableBitStream()
            try action.encode(to: &bits)
            let data = bits.packData()
            if data.count > 10_000 {
                try sendLarge(data: data, to: player.peerID)
            } else {
                try sendSmall(data: data, to: player.peerID)
            }
            if action.description != "physics" {
                os_signpost(type: .event, log: .network_data_sent, name: .network_action_sent, signpostID: .network_data_sent,
                            "Action : %s", action.description)
            } else {
                let bytes = Int32(exactly: data.count) ?? Int32.max
                os_signpost(type: .event, log: .network_data_sent, name: .network_physics_sent, signpostID: .network_data_sent,
                            "%d Bytes Sent", bytes)
            }
        } catch {
            log.error("sending failed: \(error)")
        }
    }

    func sendSmall(data: Data, to peer: MCPeerID) throws {
        try session.send(data, toPeers: [peer], with: .reliable)
    }

    func sendLarge(data: Data, to peer: MCPeerID) throws {
        let fileName = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try data.write(to: fileName)
        session.sendResource(at: fileName, withName: "Action", toPeer: peer) { error in
            if let error = error {
                log.error("sending failed: \(error)")
                return
            }
            log.info("send succeeded, removing temp file")
            do {
                try FileManager.default.removeItem(at: fileName)
            } catch {
                log.error("removing failed: \(error)")
            }
        }
    }

    func receive(data: Data, from peerID: MCPeerID) {
        guard let player = peers.first(where: { $0.peerID == peerID }) else {
            log.info("peer \(peerID) unknown!")
            return
        }
        do {
            var bits = ReadableBitStream(data: data)
            let action = try Action(from: &bits)
            let command = GameCommand(player: player, action: action)
            delegate?.gameSession(self, received: command)
            if action.description != "physics" {
                os_signpost(type: .event, log: .network_data_received, name: .network_action_received, signpostID: .network_data_received,
                            "Action : %s", action.description)
            } else {
                let peerID = Int32(truncatingIfNeeded: peerID.displayName.hashValue)
                let bytes = Int32(exactly: data.count) ?? Int32.max
                os_signpost(type: .event, log: .network_data_received, name: .network_physics_received, signpostID: .network_data_received,
                            "%d Bytes Sent from %d", bytes, peerID)
            }
        } catch {
            log.error("deserialization error: \(error)")
        }
    }
}

/// - Tag: GameSession-MCSessionDelegate
extension GameSession: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        log.info("peer \(peerID) state is now \(state.rawValue)")
        let player = Player(peerID: peerID)
        switch state {
        case .connected:
            peers.insert(player)
            delegate?.gameSession(self, joining: player)
        case .connecting:
            break
        case.notConnected:
            peers.remove(player)
            delegate?.gameSession(self, leaving: player)
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        receive(data: data, from: peerID)
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        log.info("peer \(peerID) sent a stream named \(streamName)")
    }

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        log.info("peer \(peerID) started sending a resource named \(resourceName)")
    }

    func session(_ session: MCSession,
                 didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        log.info("peer \(peerID) finished sending a resource named \(resourceName)")
        if let error = error {
            log.error("failed to receive resource: \(error)")
            return
        }
        guard let url = localURL else { log.error("what what no url?"); return }

        do {
            // .mappedIfSafe makes the initializer attempt to map the file directly into memory
            // using mmap(2), rather than serially copying the bytes into memory.
            // this is faster and our app isn't charged for the memory usage.
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            receive(data: data, from: peerID)
            // removing the file is done by the session, so long as we're done with it before the
            // delegate method returns.
        } catch {
            log.error("dealing with resource failed: \(error)")
        }
    }
}

extension GameSession: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        log.info("got request from \(peerID), accepting!")
        invitationHandler(true, session)
    }
}
