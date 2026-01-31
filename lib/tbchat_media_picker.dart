
import 'tbchat_media_picker_platform_interface.dart';

class TbchatMediaPicker {  /// 选择媒体文件（图片和视频）
  /// 
  /// [mimeType] 媒体类型：0-全部（图片和视频，默认），1-仅图片，2-仅视频
  /// [maxSelectNum] 最大选择数量，默认为1
  /// [maxSize] 最大选择大小，默认为不限制
  /// 
  /// 
  /// 返回选择的媒体文件列表，每个文件包含以下字段：
  /// - path: 文件路径
  /// - realPath: 真实文件路径
  /// - mimeType: MIME类型
  /// - width: 宽度（图片/视频）
  /// - height: 高度（图片/视频）
  /// - duration: 时长（视频，单位：毫秒）
  /// - size: 文件大小（字节）
  /// - fileName: 文件名
  /// - bucketId: 相册ID
  /// - id: 媒体ID
  /// - isCut: 是否已裁剪
  /// - cutPath: 裁剪后的路径
  /// - compressPath: 压缩后的路径
  static Future<List<Map<String, dynamic>>> pickMedia({
    int mimeType = 0, // 默认全部（图片和视频）
    int maxSelectNum = 1,
    int maxSize = 0
  }) {
    return TbchatMediaPickerPlatform.instance.pickMedia(
      mimeType: mimeType,
      maxSelectNum: maxSelectNum,
      maxSize: maxSize,
    );
  }
}
