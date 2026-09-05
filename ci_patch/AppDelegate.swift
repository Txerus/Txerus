import AVFoundation
import AVKit
import CarPlay
import Flutter
import UIKit

private final class NativeAirPlayPlayerPlugin: NSObject, FlutterPlugin, AVPlayerViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
  private var playerViewController: AVPlayerViewController?
  private var pendingResult: FlutterResult?
  private var isPiPActive = false
  private var isPiPTransitioning = false
  private var isFinishing = false

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "playtorrio/native_player", binaryMessenger: registrar.messenger())
    let instance = NativeAirPlayPlayerPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "open":
      guard let args = call.arguments as? [String: Any],
            let urlString = args["url"] as? String,
            let url = URL(string: urlString) else {
        result(FlutterError(code: "bad_args", message: "Missing or invalid URL.", details: nil))
        return
      }
      presentPlayer(url: url, title: args["title"] as? String, headers: args["headers"] as? [String: String] ?? [:], startMs: (args["startPositionMs"] as? NSNumber)?.int64Value ?? 0, result: result)
    case "isAvailable":
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func presentPlayer(url: URL, title: String?, headers: [String: String], startMs: Int64, result: @escaping FlutterResult) {
    guard playerViewController == nil else {
      result(FlutterError(code: "already_open", message: "Native player is already open.", details: nil))
      return
    }
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
      try session.setActive(true)
    } catch {
      NSLog("[PlayTorrio NativePlayer] AVAudioSession warning: \(error)")
    }
    var options: [String: Any] = [:]
    if !headers.isEmpty { options["AVURLAssetHTTPHeaderFieldsKey"] = headers }
    let item = AVPlayerItem(asset: AVURLAsset(url: url, options: options))
    let player = AVPlayer(playerItem: item)
    player.allowsExternalPlayback = true
    player.usesExternalPlaybackWhileExternalScreenIsActive = true
    player.preventsDisplaySleepDuringVideoPlayback = true
    let controller = AVPlayerViewController()
    controller.player = player
    controller.delegate = self
    controller.showsPlaybackControls = true
    controller.allowsPictureInPicturePlayback = true
    if #available(iOS 14.2, *) { controller.canStartPictureInPictureAutomaticallyFromInline = true }
    if #available(iOS 15.0, *), let title = title {
      let metadata = AVMutableMetadataItem()
      metadata.identifier = .commonIdentifierTitle
      metadata.value = title as NSString
      metadata.extendedLanguageTag = "und"
      item.externalMetadata = [metadata.copy() as! AVMetadataItem]
    }
    guard let presenter = topViewController() else {
      result(FlutterError(code: "no_presenter", message: "Unable to find an iOS view controller.", details: nil))
      return
    }
    pendingResult = result
    playerViewController = controller
    isPiPActive = false
    isPiPTransitioning = false
    isFinishing = false
    controller.modalPresentationStyle = .fullScreen
    presenter.present(controller, animated: true) { [weak self] in
      controller.presentationController?.delegate = self
      if startMs > 0 { player.seek(to: CMTime(value: startMs, timescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero) }
      player.play()
    }
  }

  func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) { isPiPTransitioning = true }
  func playerViewControllerDidStartPictureInPicture(_ playerViewController: AVPlayerViewController) { isPiPActive = true; isPiPTransitioning = false }
  func playerViewController(_ playerViewController: AVPlayerViewController, failedToStartPictureInPictureWithError error: Error) { isPiPActive = false; isPiPTransitioning = false }
  func playerViewControllerWillStopPictureInPicture(_ playerViewController: AVPlayerViewController) { isPiPTransitioning = true }
  func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) { isPiPActive = false; isPiPTransitioning = false }

  func playerViewController(_ playerViewController: AVPlayerViewController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
    if playerViewController.presentingViewController != nil || playerViewController.viewIfLoaded?.window != nil { completionHandler(true); return }
    guard let presenter = topViewController() else { completionHandler(false); return }
    presenter.present(playerViewController, animated: true) {
      playerViewController.presentationController?.delegate = self
      completionHandler(true)
    }
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    guard !isPiPActive && !isPiPTransitioning else { return }
    finishNativePlayback()
  }

  func playerViewController(_ playerViewController: AVPlayerViewController, willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
    coordinator.animate(alongsideTransition: nil) { [weak self] _ in
      guard let self = self, !self.isPiPActive, !self.isPiPTransitioning else { return }
      if playerViewController.presentingViewController != nil || playerViewController.viewIfLoaded?.window != nil { return }
      self.finishNativePlayback()
    }
  }

  private func finishNativePlayback() {
    guard !isFinishing, !isPiPActive, !isPiPTransitioning, let controller = playerViewController else { return }
    isFinishing = true
    let player = controller.player
    let position = player?.currentTime().seconds ?? 0
    let duration = player?.currentItem?.duration.seconds ?? 0
    player?.pause()
    pendingResult?(["positionMs": position.isFinite ? Int64(max(0, position) * 1000) : 0, "durationMs": duration.isFinite ? Int64(max(0, duration) * 1000) : 0])
    pendingResult = nil
    playerViewController = nil
    isFinishing = false
  }

  private func topViewController() -> UIViewController? {
    let root = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }.flatMap { $0.windows }.first(where: { $0.isKeyWindow })?.rootViewController
    return topViewController(from: root)
  }

  private func topViewController(from root: UIViewController?) -> UIViewController? {
    if let nav = root as? UINavigationController { return topViewController(from: nav.visibleViewController) }
    if let tab = root as? UITabBarController { return topViewController(from: tab.selectedViewController) }
    if let presented = root?.presentedViewController, presented !== playerViewController { return topViewController(from: presented) }
    return root
  }
}

@available(iOS 14.0, *)
@objc(PlayTorrioCarPlaySceneDelegate)
final class PlayTorrioCarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
  private weak var interfaceController: CPInterfaceController?
  private weak var carWindow: CPWindow?

  func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
    NSLog("[PlayTorrio CarPlay V5] didConnect interfaceController")
    configure(interfaceController: interfaceController, window: nil)
  }

  func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController, to window: CPWindow) {
    NSLog("[PlayTorrio CarPlay V5] didConnect interfaceController + CPWindow")
    configure(interfaceController: interfaceController, window: window)
  }

  func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
    NSLog("[PlayTorrio CarPlay V5] didDisconnect interfaceController")
    self.interfaceController = nil
    self.carWindow = nil
  }

  func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnect interfaceController: CPInterfaceController, from window: CPWindow) {
    NSLog("[PlayTorrio CarPlay V5] didDisconnect interfaceController + CPWindow")
    self.interfaceController = nil
    self.carWindow = nil
  }

  private func configure(interfaceController: CPInterfaceController, window: CPWindow?) {
    self.interfaceController = interfaceController
    self.carWindow = window
    if let window { NSLog("[PlayTorrio CarPlay V5] CPWindow screen bounds = \(window.screen.bounds)") }

    let tv = CPListItem(text: "TV / IPTV", detailText: "Chaînes en direct")
    tv.handler = { [weak self] _, completion in self?.showInfo(title: "TV / IPTV", text: "Ouvre la chaîne sur l’iPhone puis utilise le lecteur natif PlayTorrio."); completion() }
    let movies = CPListItem(text: "Films & Séries", detailText: "Lecture PlayTorrio")
    movies.handler = { [weak self] _, completion in self?.showInfo(title: "Films & Séries", text: "La vidéo CarPlay reste contrôlée par iOS et le véhicule."); completion() }
    let diagnostics = CPListItem(text: "Diagnostic CarPlay V5", detailText: window == nil ? "Scène sans CPWindow" : "CPWindow connectée")
    let root = CPListTemplate(title: "PlayTorrio", sections: [CPListSection(items: [tv, movies, diagnostics])])
    interfaceController.setRootTemplate(root, animated: false, completion: nil)
  }

  private func showInfo(title: String, text: String) {
    guard let interfaceController else { return }
    let action = CPAlertAction(title: "OK", style: .default) { _ in }
    interfaceController.presentTemplate(CPAlertTemplate(titleVariants: [title, text], actions: [action]), animated: true, completion: nil)
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    NSLog("[PlayTorrio CarPlay V5] app launched")
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NativeAirPlayPlayerPlugin") { NativeAirPlayPlayerPlugin.register(with: registrar) }
  }
}
