/*
See LICENSE folder for this sample’s licensing information.

Abstract:
View controller for in-game 2D overlay UI.
*/

import UIKit
import AVFoundation

private let log = Log()

protocol OverlayViewControllerDelegate: class {
    func overlayViewController(_ overlayViewController: UIViewController, didPressStartSoloGameButton: UIButton)
    func overlayViewController(_ overlayViewController: UIViewController, didSelect game: GameSession)
    func overlayViewController(_ overlayViewController: UIViewController, didStart game: GameSession)
    func overlayViewControllerSelectedSettings(_ overlayViewController: UIViewController)
}

enum GameSegue: String {
    case embeddedGameBrowser
    case embeddedOverlay
    case showSettings
    case levelSelector
}

class OverlayViewController: UIViewController {
    weak var delegate: OverlayViewControllerDelegate?
    
    @IBOutlet weak var hostButton: UIButton!
    @IBOutlet weak var joinButton: UIButton!
    @IBOutlet weak var backButton: UIButton!
    @IBOutlet weak var browserContainerView: UIView!
    @IBOutlet weak var blurView: UIVisualEffectView!
    @IBOutlet weak var nearbyGamesLabel: UILabel!
    var buttonBeep: ButtonBeep!
    var backButtonBeep: ButtonBeep!
    
    private let myself = UserDefaults.standard.myself
    
    let proximityManager = ProximityManager.shared
    var gameBrowser: GameBrowser?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        proximityManager.delegate = self
        hostButton.clipsToBounds = true
        hostButton.layer.cornerRadius = 30.0
        
        joinButton.clipsToBounds = true
        joinButton.layer.cornerRadius = 30.0

        buttonBeep = ButtonBeep(name: "button_forward.wav", volume: 0.5)
        backButtonBeep = ButtonBeep(name: "button_backward.wav", volume: 0.5)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if UserDefaults.standard.gameRoomMode {
            log.debug("Will start beacon ranging")
            proximityManager.start()
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        log.info("segue!")
        guard let segueIdentifier = segue.identifier,
            let segueType = GameSegue(rawValue: segueIdentifier) else {
                log.error("unknown segue \(String(describing: segue.identifier))")
                return
        }
        
        switch segueType {
        case .embeddedGameBrowser:
            guard let browser = segue.destination as? NetworkGameBrowserViewController else { return }
            gameBrowser = GameBrowser(myself: myself)
            browser.browser = gameBrowser
            browser.proximityManager = proximityManager
        default:
            break
        }
    }
    
    func joinGame(session: GameSession) {
        delegate?.overlayViewController(self, didSelect: session)
        setupOverlayVC()
    }
    
    @IBAction func startSoloGamePressed(_ sender: UIButton) {
        delegate?.overlayViewController(self, didPressStartSoloGameButton: sender)
    }
    
    @IBAction func startGamePressed(_ sender: UIButton) {
        buttonBeep.play()

        startGame(with: myself)
    }
    
    @IBAction func settingsPressed(_ sender: Any) {
        delegate?.overlayViewControllerSelectedSettings(self)
    }
   
    @IBAction func joinButtonPressed(_ sender: Any) {
        buttonBeep.play()
        showViews(forSetup: false)
    }
    
    @IBAction func backButtonPressed(_ sender: Any) {
        backButtonBeep.play()
        setupOverlayVC()
    }
    
    func setupOverlayVC() {
        showViews(forSetup: true)
    }
    
    func showViews(forSetup: Bool) {
        UIView.transition(with: view, duration: 1.0, options: [.transitionCrossDissolve], animations: {
            self.blurView.isHidden = forSetup
            self.browserContainerView.isHidden = forSetup
            self.backButton.isHidden = forSetup
            self.nearbyGamesLabel.isHidden = forSetup
            
            self.joinButton.isHidden = !forSetup
            self.hostButton.isHidden = !forSetup
        }, completion: nil)
    }
    
    func startGame(with player: Player) {
        let location: GameTableLocation?
        if UserDefaults.standard.gameRoomMode {
            location = proximityManager.closestLocation
        } else {
            location = nil
        }
        
        let gameSession = GameSession(myself: player, asServer: true, location: location, host: myself)
        delegate?.overlayViewController(self, didStart: gameSession)
        setupOverlayVC()
    }
}

extension OverlayViewController: ProximityManagerDelegate {
    func proximityManager(_ manager: ProximityManager, didChange location: GameTableLocation?) {
        gameBrowser?.refresh()
    }
    
    func proximityManager(_ manager: ProximityManager, didChange authorization: Bool) {

    }
}
