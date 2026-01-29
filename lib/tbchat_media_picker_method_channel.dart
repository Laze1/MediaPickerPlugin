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
}
