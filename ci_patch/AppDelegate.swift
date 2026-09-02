import AVFoundation
import AVKit
import Flutter
import UIKit

private final class NativeAirPlayPlayerPlugin: NSObject, FlutterPlugin, AVPlayerViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
  private var playerViewController: AVPlayerViewController?
  private var pendingResult: FlutterResult?

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
      presentPlayer(
        url: url,
        title: args["title"] as? String,
        headers: args["headers"] as? [String: String] ?? [:],
        startMs: (args["startPositionMs"] as? NSNumber)?.int64Value ?? 0,
        result: result
      )
    case "isAvailable": result(true)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func presentPlayer(url: URL, title: String?, headers: [String: String], startMs: Int64, result: @escaping FlutterResult) {
    guard playerViewController == nil else {
      result(FlutterError(code: "already_open", message: "Native player is already open.", details: nil))
      return
    }

    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .moviePlayback, options: [])
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
    presenter.present(controller, animated: true) { [weak self] in
      controller.presentationController?.delegate = self
      if startMs > 0 {
        player.seek(to: CMTime(value: startMs, timescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero)
      }
      player.play()
    }
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { finishNativePlayback() }

  func playerViewController(_ playerViewController: AVPlayerViewController, willEndFullScreenPresentationWithAnimationCoordinator coordinator: UIViewControllerTransitionCoordinator) {
    coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.finishNativePlayback() }
  }

  private func finishNativePlayback() {
    guard let controller = playerViewController else { return }
    let player = controller.player
    let position = player?.currentTime().seconds ?? 0
    let duration = player?.currentItem?.duration.seconds ?? 0
    player?.pause()
    pendingResult?([
      "positionMs": position.isFinite ? Int64(max(0, position) * 1000) : 0,
      "durationMs": duration.isFinite ? Int64(max(0, duration) * 1000) : 0
    ])
    pendingResult = nil
    playerViewController = nil
  }

  private func topViewController() -> UIViewController? {
    let root = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .filter { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive }
      .flatMap { $0.windows }
      .first(where: { $0.isKeyWindow })?.rootViewController
    return topViewController(from: root)
  }

  private func topViewController(from root: UIViewController?) -> UIViewController? {
    if let nav = root as? UINavigationController { return topViewController(from: nav.visibleViewController) }
    if let tab = root as? UITabBarController { return topViewController(from: tab.selectedViewController) }
    if let presented = root?.presentedViewController { return topViewController(from: presented) }
    return root
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "NativeAirPlayPlayerPlugin") {
      NativeAirPlayPlayerPlugin.register(with: registrar)
    }
  }
}
