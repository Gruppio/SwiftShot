/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Performance debugging markers for GameAction.
*/

import Foundation

extension Action: CustomStringConvertible {
    var description: String {
        switch self {
        case .gameAction(let action):
            switch action {
            case .grabStart:
                return "grabStart"
            case .catapultRelease:
                return "catapultRelease"
            case .tryGrab:
                return "tryGrab"
            case .grabMove:
                return "grabMove"
            case .grabbableStatus:
                return "grabbableStatus"
            case .pickup:
                return "pickup"
            case .catapultKnockOut:
                return "catapultKnockOut"
            case .oneHitKOPrepareAnimation:
                return "oneHitKOPrepareAnimation"
            case .tryRelease:
                return "tryRelease"
            case .leverMove:
                return "levelMove"
            case .releaseEnd:
                return "releaseEnd"
            case .requestKnockoutSync:
                return "requestKnockoutSync"
            }
        case .boardSetup(let setup):
            switch setup {
            case .requestBoardLocation:
                return "requestBoardLocation"
            case .boardLocation:
                return "boardLocation"
            }
        case .physics:
            return "physics"
        case .startGameMusic:
            return "startGameMusic"
        }
    }
}
