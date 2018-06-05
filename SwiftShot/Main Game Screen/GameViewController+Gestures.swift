/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Gesture interaction methods for the Game Scene View Controller.
*/

import UIKit
import SceneKit

extension GameViewController: UIGestureRecognizerDelegate {
    
    // MARK: - UI Gestures and Touches
    @IBAction func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        
        let location = gesture.location(in: sceneView)
        
        switch sessionState {
        case .placingBoard, .adjustingBoard:
            if !gameBoard.isBorderHidden {
                sessionState = .setupLevel
            }
        case .gameInProgress:
            let info = rayCastHitInfo(forTouch: location)
            gameManager?.handleTouch(type: .tapped, hit: info)
        default:
            break
        }
    }
    
    @IBAction func handlePinch(_ gesture: ThresholdPinchGestureRecognizer) {
        guard canAdjustBoard else { return }
        
        sessionState = .adjustingBoard
        
        switch gesture.state {
        case .changed where gesture.isThresholdExceeded:
            gameBoard.scale(by: Float(gesture.scale))
            gesture.scale = 1
        default:
            break
        }
    }
    
    @IBAction func handleRotation(_ gesture: ThresholdRotationGestureRecognizer) {
        guard canAdjustBoard else { return }
        
        sessionState = .adjustingBoard
        
        switch gesture.state {
        case .changed where gesture.isThresholdExceeded:
            if gameBoard.eulerAngles.x > .pi / 2 {
                gameBoard.simdEulerAngles.y += Float(gesture.rotation)
            } else {
                gameBoard.simdEulerAngles.y -= Float(gesture.rotation)
            }
            gesture.rotation = 0
        default:
            break
        }
    }
    
    @IBAction func handlePan(_ gesture: ThresholdPanGestureRecognizer) {
        
        guard canAdjustBoard else { return }
        
        sessionState = .adjustingBoard
        
        let location = gesture.location(in: sceneView)
        let results = sceneView.hitTest(location, types: .existingPlane)
        guard let nearestPlane = results.first else {
            return
        }
        
        switch gesture.state {
        case .began:
            panOffset = nearestPlane.worldTransform.columns.3.xyz - gameBoard.simdWorldPosition
        case .changed:
            gameBoard.simdWorldPosition = nearestPlane.worldTransform.columns.3.xyz - panOffset
        default:
            break
        }
    }
    
    @IBAction func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard canAdjustBoard else { return }
        
        sessionState = .adjustingBoard
        gameBoard.useDefaultScale()
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let location = touches.first?.location(in: sceneView) else { return }
        touch(type: .began, location: location)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let location = touches.first?.location(in: sceneView) else { return }
        touch(type: .ended, location: location)
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let location = touches.first?.location(in: sceneView) else { return }
        touch(type: .ended, location: location)
    }
    
    private func touch(type: TouchType, location: CGPoint) {
        let info = rayCastHitInfo(forTouch: location)
        gameManager?.handleTouch(type: type, hit: info)
    }
    
    private func rayCastHitInfo(forTouch location: CGPoint) -> (GameRayCastHitInfo) {
        
        let rayCastDistance: Float = 50.0
        let pointX = Float(location.x)
        let pointY = Float(location.y)
        
        guard let gameManager = self.gameManager else {
            // return a dummy object
            return GameRayCastHitInfo(position: float3(), direction: float3(0, 0, 1), hits: [])
        }
        
        var origin = sceneView.unprojectPoint(float3(pointX, pointY, 0.0))
        var farPoint = sceneView.unprojectPoint(float3(pointX, pointY, 0.999))
        origin = gameManager.renderSpacePositionToSimulationSpace(pos: origin)
        farPoint = gameManager.renderSpacePositionToSimulationSpace(pos: farPoint)
    
        let direction = normalize(farPoint - origin)
        let destination = direction * rayCastDistance + origin
        let sceneHits = sceneView.scene.rootNode.hitTestWithSegment(from: origin, to: destination, options: nil)
        
        return GameRayCastHitInfo(position: origin, direction: direction, hits: sceneHits)
    }
    
    func gestureRecognizer(_ first: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith second: UIGestureRecognizer) -> Bool {
        if first is UIRotationGestureRecognizer && second is UIPinchGestureRecognizer {
            return true
        } else if first is UIRotationGestureRecognizer && second is UIPanGestureRecognizer {
            return true
        } else if first is UIPinchGestureRecognizer && second is UIRotationGestureRecognizer {
            return true
        } else if first is UIPinchGestureRecognizer && second is UIPanGestureRecognizer {
            return true
        } else if first is UIPanGestureRecognizer && second is UIPinchGestureRecognizer {
            return true
        } else if first is UIPanGestureRecognizer && second is UIRotationGestureRecognizer {
            return true
        }
        return false
    }
}
