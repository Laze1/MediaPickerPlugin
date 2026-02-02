import 'package:flutter_test/flutter_test.dart';
import 'package:tbchat_media_picker/tbchat_media_picker_platform_interface.dart';
import 'package:tbchat_media_picker/tbchat_media_picker_method_channel.dart';

void main() {
  final TbchatMediaPickerPlatform initialPlatform = TbchatMediaPickerPlatform.instance;

  test('$MethodChannelTbchatMediaPicker is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelTbchatMediaPicker>());
  });

}
