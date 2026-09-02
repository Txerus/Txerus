import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'ios_native_player.dart';

class IosAirPlayHlsResult {
  final Duration absolutePosition;
  const IosAirPlayHlsResult(this.absolutePosition);
}

abstract final class IosAirPlayHls {
  static String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";

  static String _headersArg(Map<String, String> headers) {
    if (headers.isEmpty) return '';
    final lines = headers.entries
        .where((e) => e.key.trim().isNotEmpty)
        .map((e) => '${e.key}: ${e.value}')
        .join('\\r\\n');
    return '-headers ${_quote('$lines\\r\\n')} ';
  }

  static Future<String> _bestHost() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final ip = address.address;
          if (ip.startsWith('192.168.') || ip.startsWith('10.')) return ip;
          if (ip.startsWith('172.')) {
            final parts = ip.split('.');
            final second = parts.length > 1 ? int.tryParse(parts[1]) : null;
            if (second != null && second >= 16 && second <= 31) return ip;
          }
        }
      }
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!address.isLoopback) return address.address;
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  static Future<HttpServer> _startServer(Directory root) async {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0, shared: true);
    server.listen((request) async {
      try {
        final relative = request.uri.pathSegments.isEmpty
            ? 'master.m3u8'
            : request.uri.pathSegments.last;
        final safeName = relative.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '');
        final file = File('${root.path}/$safeName');
        if (!await file.exists()) {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
          return;
        }

        if (safeName.endsWith('.m3u8')) {
          request.response.headers.contentType = ContentType('application', 'vnd.apple.mpegurl');
          request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache, no-store');
        } else if (safeName.endsWith('.m4s')) {
          request.response.headers.contentType = ContentType('video', 'iso.segment');
        } else if (safeName.endsWith('.mp4')) {
          request.response.headers.contentType = ContentType('video', 'mp4');
        }
        request.response.headers.set('Access-Control-Allow-Origin', '*');
        await request.response.addStream(file.openRead());
        await request.response.close();
      } catch (_) {
        try {
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        } catch (_) {}
      }
    });
    return server;
  }

  static Future<void> _waitForPlaylist(File playlist) async {
    final deadline = DateTime.now().add(const Duration(seconds: 35));
    while (DateTime.now().isBefore(deadline)) {
      if (await playlist.exists()) {
        try {
          final text = await playlist.readAsString();
          if (text.contains('#EXTINF') || text.contains('#EXT-X-MAP')) return;
        } catch (_) {}
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw StateError('Le flux AirPlay n’a pas pu être préparé dans le délai imparti.');
  }

  static Future<IosAirPlayHlsResult?> open({
    required String sourceUrl,
    required String title,
    required Map<String, String> headers,
    required Duration startPosition,
  }) async {
    if (!Platform.isIOS) return null;

    final temp = await getTemporaryDirectory();
    final dir = await Directory(
      '${temp.path}/playtorrio_airplay_${DateTime.now().millisecondsSinceEpoch}',
    ).create(recursive: true);
    final playlist = File('${dir.path}/master.m3u8');

    HttpServer? server;
    int? sessionId;
    try {
      server = await _startServer(dir);
      final host = await _bestHost();
      final hlsUrl = 'http://$host:${server.port}/master.m3u8';

      final ss = startPosition > Duration.zero
          ? '-ss ${(startPosition.inMilliseconds / 1000.0).toStringAsFixed(3)} '
          : '';
      final headerArg = _headersArg(headers);
      final input = _quote(sourceUrl);
      final segmentPattern = _quote('${dir.path}/seg_%06d.m4s');
      final initName = 'init.mp4';
      final output = _quote(playlist.path);

      // V2 deliberately transcodes to Apple-native H.264/AAC. This avoids the
      // black-screen failure seen when AVPlayer receives MKV/unsupported codecs.
      // VideoToolbox keeps the conversion hardware accelerated on iPhone.
      final command =
          '-hide_banner -loglevel warning -y '
          '$ss$headerArg'
          '-i $input '
          '-map 0:v:0 -map 0:a:0? -sn -dn '
          '-c:v h264_videotoolbox -allow_sw 1 -realtime 1 '
          '-b:v 6500k -maxrate 9000k -bufsize 13000k -pix_fmt yuv420p '
          '-c:a aac -b:a 192k -ac 2 '
          '-force_key_frames ${_quote('expr:gte(t,n_forced*2)')} '
          '-f hls -hls_time 2 -hls_playlist_type event '
          '-hls_segment_type fmp4 -hls_fmp4_init_filename $initName '
          '-hls_flags independent_segments+temp_file '
          '-hls_segment_filename $segmentPattern $output';

      final session = await FFmpegKit.executeAsync(command, (completed) async {
        // Completion is expected when the source ends or when we cancel after
        // closing AVPlayer. Runtime errors are surfaced by the playlist timeout.
      });
      sessionId = session.getSessionId();

      await _waitForPlaylist(playlist);

      final native = await IosNativePlayer.open(
        url: hlsUrl,
        title: title,
        headers: const {},
        startPosition: Duration.zero,
      );

      if (native == null) return null;
      return IosAirPlayHlsResult(startPosition + native.position);
    } finally {
      if (sessionId != null) {
        try {
          await FFmpegKit.cancel(sessionId);
        } catch (_) {}
      }
      try {
        await server?.close(force: true);
      } catch (_) {}
      try {
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {}
    }
  }
}
