from pathlib import Path

p = Path('playtorrio/lib/pages/player/player_screen.dart')
s = p.read_text()

def replace_once(old: str, new: str, label: str) -> None:
    global s
    if old not in s:
        raise SystemExit(f'Patch anchor not found: {label}')
    s = s.replace(old, new, 1)

replace_once(
    "import '../../services/player/player_settings.dart';\n",
    "import '../../services/player/player_settings.dart';\nimport '../../services/player/ios_native_player.dart';\n",
    'player import',
)

replace_once(
    "  bool _isLoading = true;\n",
    "  bool _isLoading = true;\n  String? _resolvedNativeStreamUrl;\n  Map<String, String> _resolvedNativeStreamHeaders = const {};\n",
    'player state',
)

replace_once(
    "      final cleanUri = Uri.parse(sanitizedUrlStr);\n      print('[PlayerScreen] Opening direct network stream URL: $cleanUri (headers: ${playerHeaders.keys})');",
    "      final cleanUri = Uri.parse(sanitizedUrlStr);\n      _resolvedNativeStreamUrl = cleanUri.toString();\n      _resolvedNativeStreamHeaders = Map<String, String>.from(playerHeaders);\n      print('[PlayerScreen] Opening direct network stream URL: $cleanUri (headers: ${playerHeaders.keys})');",
    'resolved URL',
)

native_method = """  Future<void> _openIosNativePlayer() async {
    if (!Platform.isIOS) return;
    final url = _resolvedNativeStreamUrl;
    if (url == null || url.isEmpty) return;

    final wasPlaying = _isPlaying;
    await _player.pause();

    try {
      final result = await IosNativePlayer.open(
        url: url,
        title: widget.detail?.name ?? _currentTitle,
        headers: _resolvedNativeStreamHeaders,
        startPosition: _player.state.position,
      );

      if (result != null && result.position > Duration.zero) {
        await _player.seek(result.position);
      }
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Native iOS player failed: ${e.message ?? e.code}')),
        );
      }
    } finally {
      if (mounted && wasPlaying) {
        await _player.play();
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
    "                      quality: _currentSource.name,\n                      onCast: (!_isLoading && Platform.isIOS && _resolvedNativeStreamUrl != null)\n                          ? _openIosNativePlayer\n                          : null,\n                      onDownload:",
    'cast button',
)

p.write_text(s)
print('PlayTorrio AirPlay/PiP patch applied successfully.')
