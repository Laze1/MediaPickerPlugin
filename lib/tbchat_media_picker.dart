
import 'tbchat_media_picker_platform_interface.dart';

class TbchatMediaPicker {
  Future<String?> getPlatformVersion() {
    return TbchatMediaPickerPlatform.instance.getPlatformVersion();
  }
}
