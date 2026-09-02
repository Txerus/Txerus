from pathlib import Path
import plistlib

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
        const SnackBar(
          content: Text('Préparation AirPlay / PiP…'),
          duration: Duration(seconds: 3),
        ),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AirPlay / PiP : $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _preparingAirPlay = false);
        if (wasPlaying) await _player.play();
      }
    }
  }

"""

replace_once(
    "  Future<void> _handleDownloadMedia() async {\n",
    native_method + "  Future<void> _handleDownloadMedia() async {\n",
    'native player method',
)

replace_once(
    "                      quality: _currentSource.name,\n                      onDownload:",
    "                      quality: _currentSource.name,\n                      onCast: (!_isLoading && !_preparingAirPlay && Platform.isIOS && _resolvedNativeStreamUrl != null)\n                          ? _openIosNativePlayer\n                          : null,\n                      onDownload:",
    'cast button',
)

p.write_text(s)

# Add maintained FFmpegKit package for iOS HLS transcoding.
pubspec = Path('playtorrio/pubspec.yaml')
ps = pubspec.read_text()
if 'ffmpeg_kit_flutter_new:' not in ps:
    anchor = '  path_provider: ^2.1.6\n'
    if anchor not in ps:
        raise SystemExit('Patch anchor not found: pubspec path_provider')
    ps = ps.replace(anchor, anchor + '  ffmpeg_kit_flutter_new: ^4.6.2\n', 1)
    pubspec.write_text(ps)

# Permit the on-device HLS server. It binds to the iPhone LAN address so an
# Apple TV can fetch the HLS playlist/segments during native AirPlay playback.
plist_path = Path('playtorrio/ios/Runner/Info.plist')
with plist_path.open('rb') as f:
    plist = plistlib.load(f)
ats = plist.setdefault('NSAppTransportSecurity', {})
ats['NSAllowsLocalNetworking'] = True
plist['NSLocalNetworkUsageDescription'] = 'PlayTorrio utilise le réseau local pour diffuser la vidéo vers AirPlay.'
bg = plist.setdefault('UIBackgroundModes', [])
if 'audio' not in bg:
    bg.append('audio')
with plist_path.open('wb') as f:
    plistlib.dump(plist, f, fmt=plistlib.FMT_XML, sort_keys=False)

print('PlayTorrio AirPlay/PiP V2 patch applied successfully.')
