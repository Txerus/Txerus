import 'dart:io';
import 'package:flutter/services.dart';

class IosNativePlayerResult {
  final Duration position;
  final Duration duration;
  const IosNativePlayerResult({required this.position, required this.duration});
}

abstract final class IosNativePlayer {
  static const MethodChannel _channel = MethodChannel('playtorrio/native_player');
  static bool get supported => Platform.isIOS;

  static Future<IosNativePlayerResult?> open({
    required String url,
    required String title,
    Map<String, String> headers = const {},
    Duration startPosition = Duration.zero,
  }) async {
    if (!Platform.isIOS) return null;
    final response = await _channel.invokeMapMethod<String, dynamic>('open', <String, dynamic>{
      'url': url,
      'title': title,
      'headers': headers,
      'startPositionMs': startPosition.inMilliseconds,
    });
    if (response == null) return null;
    return IosNativePlayerResult(
      position: Duration(milliseconds: (response['positionMs'] as num?)?.toInt() ?? 0),
      duration: Duration(milliseconds: (response['durationMs'] as num?)?.toInt() ?? 0),
    );
  }
}
