import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'tbchat_media_picker_platform_interface.dart';

/// An implementation of [TbchatMediaPickerPlatform] that uses method channels.
class MethodChannelTbchatMediaPicker extends TbchatMediaPickerPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('tbchat_media_picker');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Future<List<Map<String, dynamic>>> pickMedia({
    int mimeType = 0,
    int maxSelectNum = 1,
    int maxSize = 0,
  }) async {
    final result = await methodChannel.invokeMethod<String>(
      'pickMedia',
      {
        'mimeType': mimeType,
        'maxSelectNum': maxSelectNum,
        'maxSize': maxSize,
      },
    );
    
    if (result == null) {
      return [];
    }
    
    try {
      final jsonList = (jsonDecode(result) as List)
          .cast<Map<dynamic, dynamic>>()
          .map((map) => Map<String, dynamic>.from(map))
          .toList();
      return jsonList;
    } catch (e) {
      return [];
    }
  }
}
