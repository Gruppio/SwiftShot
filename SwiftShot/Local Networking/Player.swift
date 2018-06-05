/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Indentifies a player in the game.
*/

import Foundation
import MultipeerConnectivity
import simd

class Player: Hashable {
    
    static func == (lhs: Player, rhs: Player) -> Bool {
        return lhs.peerID == rhs.peerID
    }
    
    let hashValue: Int
    
    let peerID: MCPeerID
    var username: String { return peerID.displayName }
    var teamID: TeamID = .none
    
    init(peerID: MCPeerID) {
        self.peerID = peerID
        self.hashValue = peerID.hashValue
    }

    init(username: String) {
        self.peerID = MCPeerID(displayName: username)
        self.hashValue = self.peerID.hashValue
    }
}
