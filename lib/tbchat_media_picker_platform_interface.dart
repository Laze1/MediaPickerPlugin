import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'media_entity.dart';
import 'tbchat_media_picker_method_channel.dart';

abstract class TbchatMediaPickerPlatform extends PlatformInterface {
  /// Constructs a TbchatMediaPickerPlatform.
  TbchatMediaPickerPlatform() : super(token: _token);

  static final Object _token = Object();

  static TbchatMediaPickerPlatform _instance = MethodChannelTbchatMediaPicker();

  /// The default instance of [TbchatMediaPickerPlatform] to use.
  ///
  /// Defaults to [MethodChannelTbchatMediaPicker].
  static TbchatMediaPickerPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [TbchatMediaPickerPlatform] when
  /// they register themselves.
  static set instance(TbchatMediaPickerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<List<MediaEntity>> pickMedia({
    int mimeType = 0, // 0: all (image and video), 1: image, 2: video
    int maxSelectNum = 1,
    int maxSize = 0,
    int gridCount = 4, // 选择器每排显示数量（网格列数）
  }) {
    throw UnimplementedError('pickMedia() has not been implemented.');
  }
}
