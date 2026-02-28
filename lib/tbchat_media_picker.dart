import 'media_entity.dart';
import 'tbchat_media_picker_platform_interface.dart';

export 'media_entity.dart';

class TbchatMediaPicker {
  /// 选择媒体文件（图片和视频）
  ///
  /// [mimeType] 媒体类型：0-全部（图片和视频，默认），1-仅图片，2-仅视频
  /// [maxSelectNum] 最大选择数量，默认为1
  /// [maxSize] 最大选择大小（字节），默认为0（不限制，实际会设置为1GB）
  /// [gridCount] 选择器每排的显示数量（相册网格列数），默认为4
  /// [maxWidth] 图片最大宽度限制，0 表示不限制；超出时缩放到该值以内
  /// [maxHeight] 图片最大高度限制，0 表示不限制；超出时缩放到该值以内
  /// [language] 选择器语言：0-跟随系统，1-简体中文，2-繁体中文，3-英语
  ///
  /// 返回选择的媒体文件列表，每个文件为 [MediaEntity] 对象
  static Future<List<MediaEntity>> pickMedia({
    int mimeType = 0,
    int maxSelectNum = 1,
    int maxSize = 0,
    int gridCount = 4,
    int maxWidth = 0,
    int maxHeight = 0,
    int language = 0,
  }) {
    return TbchatMediaPickerPlatform.instance.pickMedia(
      mimeType: mimeType,
      maxSelectNum: maxSelectNum,
      maxSize: maxSize,
      gridCount: gridCount,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      language: language,
    );
  }
}
