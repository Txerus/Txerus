from pathlib import Path
import plistlib

# ---------------------------------------------------------------------------
# Movies / series player
# ---------------------------------------------------------------------------
p = Path('playtorrio/lib/pages/player/player_screen.dart')
s = p.read_text()

def replace_once(old: str, new: str, label: str) -> None:
    global s
    if old not in s:
        raise SystemExit(f'Patch anchor not found: {label}')
    s = s.replace(old, new, 1)

replace_once(
    "import '../../services/player/player_settings.dart';\n",
    "import '../../services/player/player_settings.dart';\nimport '../../services/player/ios_airplay_hls.dart';\n",
    'player import',
)
replace_once(
    "  bool _isLoading = true;\n",
    "  bool _isLoading = true;\n  String? _resolvedNativeStreamUrl;\n  Map<String, String> _resolvedNativeStreamHeaders = const {};\n  bool _preparingAirPlay = false;\n",
    'player state',
)
replace_once(
    "      final cleanUri = Uri.parse(sanitizedUrlStr);\n      print('[PlayerScreen] Opening direct network stream URL: $cleanUri (headers: ${playerHeaders.keys})');",
    "      final cleanUri = Uri.parse(sanitizedUrlStr);\n      _resolvedNativeStreamUrl = cleanUri.toString();\n      _resolvedNativeStreamHeaders = Map<String, String>.from(playerHeaders);\n      print('[PlayerScreen] Opening direct network stream URL: $cleanUri (headers: ${playerHeaders.keys})');",
    'resolved URL',
)

native_method = """  Future<void> _openIosNativePlayer() async {
    if (!Platform.isIOS || _preparingAirPlay) return;
    final url = _resolvedNativeStreamUrl;
    if (url == null || url.isEmpty) return;
    final wasPlaying = _isPlaying;
    final start = _player.state.position;
    await _player.pause();
    if (mounted) {
      setState(() => _preparingAirPlay = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Préparation AirPlay / PiP…'), duration: Duration(seconds: 3)),
      );
    }
    try {
      final result = await IosAirPlayHls.open(
        sourceUrl: url,
        title: widget.detail?.name ?? _currentTitle,
        headers: _resolvedNativeStreamHeaders,
        startPosition: start,
      );
      if (result != null && result.absolutePosition > Duration.zero) {
        await _player.seek(result.absolutePosition);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('AirPlay / PiP : $e')));
    } finally {
      if (mounted) {
        setState(() => _preparingAirPlay = false);
        if (wasPlaying) await _player.play();
      }
    }
  }

"""
replace_once("  Future<void> _handleDownloadMedia() async {\n", native_method + "  Future<void> _handleDownloadMedia() async {\n", 'native player method')
replace_once(
    "                      quality: _currentSource.name,\n                      onDownload:",
    "                      quality: _currentSource.name,\n                      onCast: (!_isLoading && !_preparingAirPlay && Platform.isIOS && _resolvedNativeStreamUrl != null)\n                          ? _openIosNativePlayer\n                          : null,\n                      onDownload:",
    'cast button',
)
p.write_text(s)

# ---------------------------------------------------------------------------
# IPTV / Live TV player
# ---------------------------------------------------------------------------
iptv = Path('playtorrio/lib/pages/iptv/iptv_player_page.dart')
t = iptv.read_text()

def iptv_replace_once(old: str, new: str, label: str) -> None:
    global t
    if old not in t:
        raise SystemExit(f'IPTV patch anchor not found: {label}')
    t = t.replace(old, new, 1)

iptv_replace_once("import '../../services/player/player_settings.dart';\n", "import '../../services/player/player_settings.dart';\nimport '../../services/player/ios_airplay_hls.dart';\n", 'IPTV import')
iptv_replace_once("  bool _isLoading = true;\n  bool _isPlaying = false;\n", "  bool _isLoading = true;\n  bool _isPlaying = false;\n  bool _preparingAirPlay = false;\n  bool _nativeAirPlayActive = false;\n", 'IPTV state')
iptv_replace_once("      if (!mounted) return;\n\n      final isPlaying = _isPlaying;", "      if (!mounted || _nativeAirPlayActive || _preparingAirPlay) return;\n\n      final isPlaying = _isPlaying;", 'IPTV watchdog guard')

iptv_native_method = """  Future<void> _openIosNativePlayer() async {
    if (!Platform.isIOS || _preparingAirPlay || _nativeAirPlayActive) return;
    if (widget.hits.isEmpty || _activeHitIndex >= widget.hits.length) return;
    final currentHit = widget.hits[_activeHitIndex];
    final streamUrl = currentHit.streamUrl;
    if (streamUrl.isEmpty) return;
    final wasPlaying = _isPlaying;
    final start = _isLiveStream ? Duration.zero : _position;
    _hideControlsTimer?.cancel();
    if (mounted) {
      setState(() { _preparingAirPlay = true; _nativeAirPlayActive = true; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isLiveStream ? 'Préparation TV / AirPlay / PiP…' : 'Préparation AirPlay / PiP…'), duration: const Duration(seconds: 3)),
      );
    }
    await _player.pause();
    try {
      final result = await IosAirPlayHls.open(
        sourceUrl: streamUrl,
        title: currentHit.stream.name.isNotEmpty ? currentHit.stream.name : widget.channel.name,
        headers: const {'User-Agent': 'VLC/3.0.20 LibVLC/3.0.20', 'Accept': '*/*', 'Connection': 'keep-alive'},
        startPosition: start,
      );
      if (!_isLiveStream && result != null && result.absolutePosition > Duration.zero) await _player.seek(result.absolutePosition);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('TV AirPlay / PiP : $e')));
    } finally {
      if (!mounted) return;
      setState(() { _preparingAirPlay = false; _nativeAirPlayActive = false; });
      if (_isLiveStream) await _initPlayer(); else if (wasPlaying) await _player.play();
      _startHideControlsTimer();
    }
  }

"""
iptv_replace_once("  void _togglePlayPause() {\n", iptv_native_method + "  void _togglePlayPause() {\n", 'IPTV native player method')
iptv_replace_once(
    "                                    const Spacer(),\n\n                                    // Aspect Ratio Selector / Popover Button",
    "                                    const Spacer(),\n\n                                    if (Platform.isIOS) ...[\n                                      IconButton(\n                                        icon: _preparingAirPlay\n                                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))\n                                            : const Icon(Icons.cast_rounded, color: Colors.white, size: 24),\n                                        tooltip: 'AirPlay / TV / PiP',\n                                        onPressed: (!_isLoading && !_preparingAirPlay && !_nativeAirPlayActive) ? _openIosNativePlayer : null,\n                                      ),\n                                      const SizedBox(width: 6),\n                                    ],\n\n                                    // Aspect Ratio Selector / Popover Button",
    'IPTV AirPlay control',
)
iptv.write_text(t)

# FFmpegKit for local HLS remuxing.
pubspec = Path('playtorrio/pubspec.yaml')
ps = pubspec.read_text()
if 'ffmpeg_kit_flutter_new:' not in ps:
    anchor = '  path_provider: ^2.1.6\n'
    if anchor not in ps: raise SystemExit('Patch anchor not found: pubspec path_provider')
    ps = ps.replace(anchor, anchor + '  ffmpeg_kit_flutter_new: ^4.6.2\n', 1)
    pubspec.write_text(ps)

# ---------------------------------------------------------------------------
# iOS native configuration: AirPlay/PiP + official iOS 27 CarPlay Video scene.
# ---------------------------------------------------------------------------
plist_path = Path('playtorrio/ios/Runner/Info.plist')
with plist_path.open('rb') as f:
    plist = plistlib.load(f)
ats = plist.setdefault('NSAppTransportSecurity', {})
ats['NSAllowsLocalNetworking'] = True
plist['NSLocalNetworkUsageDescription'] = 'PlayTorrio utilise le réseau local pour diffuser la vidéo vers AirPlay.'
bg = plist.setdefault('UIBackgroundModes', [])
if 'audio' not in bg: bg.append('audio')

scene_manifest = plist.setdefault('UIApplicationSceneManifest', {})
scene_manifest['UIApplicationSupportsMultipleScenes'] = True
configs = scene_manifest.setdefault('UISceneConfigurations', {})
configs['CPTemplateApplicationSceneSessionRoleApplication'] = [{
    'UISceneConfigurationName': 'PlayTorrio CarPlay',
    'UISceneClassName': 'CPTemplateApplicationScene',
    'UISceneDelegateClassName': '$(PRODUCT_MODULE_NAME).PlayTorrioCarPlaySceneDelegate',
}]
with plist_path.open('wb') as f:
    plistlib.dump(plist, f, fmt=plistlib.FMT_XML, sort_keys=False)

# Requested capabilities. These are managed Apple entitlements: a signing
# profile must contain them for a real device build to expose PlayTorrio in
# CarPlay. Keeping them in the project makes the IPA ready for an eligible
# signer/profile rather than relying on legacy private CarPlay tricks.
entitlements_path = Path('playtorrio/ios/Runner/Runner.entitlements')
entitlements = {
    'com.apple.developer.carplay-video': True,
    'com.apple.developer.carplay-audio': True,
}
with entitlements_path.open('wb') as f:
    plistlib.dump(entitlements, f, fmt=plistlib.FMT_XML, sort_keys=False)

pbx = Path('playtorrio/ios/Runner.xcodeproj/project.pbxproj')
pbx_text = pbx.read_text()
# Ensure every Runner build configuration references the entitlements file.
if 'CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;' not in pbx_text:
    pbx_text = pbx_text.replace(
        'PRODUCT_BUNDLE_IDENTIFIER = com.example.playtorrio;',
        'CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;\n\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.example.playtorrio;'
    )
    pbx.write_text(pbx_text)

print('PlayTorrio V3 patch applied: movies + IPTV AirPlay/PiP + iOS 27 CarPlay Video scene.')
