import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'media_entity.dart';
import 'tbchat_media_picker_platform_interface.dart';

/// An implementation of [TbchatMediaPickerPlatform] that uses method channels.
class MethodChannelTbchatMediaPicker extends TbchatMediaPickerPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('tbchat_media_picker');

  @override
  Future<List<MediaEntity>> pickMedia({
    int mimeType = 0,
    int maxSelectNum = 1,
    int maxSize = 0,
    int gridCount = 4,
  }) async {
    final result = await methodChannel.invokeMethod<String>(
      'pickMedia',
      {
        'mimeType': mimeType,
        'maxSelectNum': maxSelectNum,
        'maxSize': maxSize,
        'gridCount': gridCount,
      },
    );
    
    if (result == null || result.isEmpty) {
      return [];
    }
    
    try {
      final jsonList = (jsonDecode(result) as List)
          .cast<Map<dynamic, dynamic>>()
          .map((map) => Map<String, dynamic>.from(map))
          .toList();
      
      return jsonList.map((map) => MediaEntity.fromMap(map)).toList();
    } catch (e) {
      return [];
    }
  }
}
