/*
See LICENSE folder for this sample’s licensing information.

Abstract:
ARSCNViewDelegate methods for the Game Scene View Controller.
*/

import ARKit

private let log = Log()

extension GameViewController: ARSCNViewDelegate {
    
    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        if anchor == gameBoard.anchor {
            // If board anchor was added, setup the level.
            DispatchQueue.main.async {
                if self.sessionState == .localizingToBoard {
                    self.sessionState = .setupLevel
                }
            }

            // We already created a node for the board anchor
            return gameBoard
        } else {
            // Ignore all other anchors
            return nil
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        if let boardAnchor = anchor as? BoardAnchor {
            // Update the game board's scale from the board anchor
            // The transform will have already been updated - without the scale
            node.simdScale = float3( Float(boardAnchor.size.width) )
        }
    }
    
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        log.info("camera tracking state changed to \(camera.trackingState)")
        DispatchQueue.main.async {
            self.trackingStateLabel.text = "\(camera.trackingState)"
        }
        
        switch camera.trackingState {
        case .normal:
            // Resume game if previously interrupted
            if isSessionInterrupted {
                isSessionInterrupted = false
            }
            
            // Fade in the board if previously hidden
            if gameBoard.isHidden {
                gameBoard.opacity = 0.0
                gameBoard.isHidden = false
                gameBoard.runAction(.fadeIn(duration: 0.6))
            }
            
            // Fade in the level if previously hidden
            if renderRoot.isHidden {
                renderRoot.opacity = 0.0
                renderRoot.isHidden = false
                renderRoot.runAction(.fadeIn(duration: 0.6))
            }
        case .limited:
            // Hide the game board and level if tracking is limited
            gameBoard.isHidden = true
            renderRoot.isHidden = true
        default:
            break
        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Get localized strings from error
        let errorWithInfo = error as NSError
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        
        // Use `compactMap(_:)` to remove optional error messages.
        let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")
        
        // Present the error message to the user
        showAlert(title: "Session Error", message: errorMessage, actions: nil)
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        log.info("[sessionWasInterrupted] --  \(sessionState)")
        
        // Inform the user that the session has been interrupted
        isSessionInterrupted = true
        
        // Hide game board and level
        gameBoard.isHidden = true
        renderRoot.isHidden = true
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        log.info("[sessionInterruptionEnded] --  \(sessionState)")
    }
    
    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool {
        return true
    }
}
