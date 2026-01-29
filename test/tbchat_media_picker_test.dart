import 'package:flutter_test/flutter_test.dart';
import 'package:tbchat_media_picker/tbchat_media_picker.dart';
import 'package:tbchat_media_picker/tbchat_media_picker_platform_interface.dart';
import 'package:tbchat_media_picker/tbchat_media_picker_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockTbchatMediaPickerPlatform
    with MockPlatformInterfaceMixin
    implements TbchatMediaPickerPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final TbchatMediaPickerPlatform initialPlatform = TbchatMediaPickerPlatform.instance;

  test('$MethodChannelTbchatMediaPicker is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelTbchatMediaPicker>());
  });

  test('getPlatformVersion', () async {
    TbchatMediaPicker tbchatMediaPickerPlugin = TbchatMediaPicker();
    MockTbchatMediaPickerPlatform fakePlatform = MockTbchatMediaPickerPlatform();
    TbchatMediaPickerPlatform.instance = fakePlatform;

    expect(await tbchatMediaPickerPlugin.getPlatformVersion(), '42');
  });
}
