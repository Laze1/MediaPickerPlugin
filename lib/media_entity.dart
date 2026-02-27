/// 媒体实体类，用于接收选择图片/视频的结果。
///
/// 原图数据（始终为相册原始文件）：
/// - [originalPath] 原图路径
/// - [originalSize] 原图文件大小（字节）
/// - [originalWidth] / [originalHeight] 原图宽高
///
/// 交付数据（压缩或缩放后的文件，若未压缩/未缩放则与原图一致）：
/// - [path] 交付路径（压缩图/缩放图/原图）
/// - [size] 交付文件大小
/// - [width] / [height] 交付宽高
class MediaEntity {
  /// 媒体ID
  final int id;

  /// 原图路径（始终为相册原始文件路径）
  final String originalPath;

  /// 原图文件大小（字节）
  final int originalSize;

  /// 原图宽度
  final int originalWidth;

  /// 原图高度
  final int originalHeight;

  /// 交付路径（压缩后/缩放后的文件路径；若未压缩未缩放则为原图路径）
  final String path;

  /// 交付文件大小（字节）
  final int size;

  /// 交付宽度
  final int width;

  /// 交付高度
  final int height;

  /// 裁剪后的路径
  final String cutPath;

  /// 水印路径
  final String watermarkPath;

  /// 视频缩略图路径
  final String videoThumbnailPath;

  /// 沙箱路径
  final String sandboxPath;

  /// 时长（视频，单位：秒）
  final int duration;

  /// 是否已裁剪
  final bool isCut;

  /// MIME类型（如：image/jpeg, video/mp4）
  final String mimeType;

  /// 是否已压缩
  final bool compressed;

  /// 是否原图
  final bool isOriginal;

  /// 文件名
  final String fileName;

  const MediaEntity({
    required this.id,
    required this.originalPath,
    required this.originalSize,
    required this.originalWidth,
    required this.originalHeight,
    required this.path,
    required this.size,
    required this.width,
    required this.height,
    required this.duration,
    required this.fileName,
    this.cutPath = '',
    this.watermarkPath = '',
    this.videoThumbnailPath = '',
    this.sandboxPath = '',
    this.isCut = false,
    this.mimeType = '',
    this.compressed = false,
    this.isOriginal = false,
  });

  /// 从 Map 创建 MediaEntity
  factory MediaEntity.fromMap(Map<String, dynamic> map) {
    return MediaEntity(
      id: map['id'] as int? ?? 0,
      originalPath: map['originalPath'] as String? ?? '',
      originalSize: map['originalSize'] as int? ?? 0,
      originalWidth: map['originalWidth'] as int? ?? 0,
      originalHeight: map['originalHeight'] as int? ?? 0,
      path: map['path'] as String? ?? '',
      size: map['size'] as int? ?? 0,
      width: map['width'] as int? ?? 0,
      height: map['height'] as int? ?? 0,
      cutPath: map['cutPath'] as String? ?? '',
      watermarkPath: map['watermarkPath'] as String? ?? '',
      videoThumbnailPath: map['videoThumbnailPath'] as String? ?? '',
      sandboxPath: map['sandboxPath'] as String? ?? '',
      duration: map['duration'] as int? ?? 0,
      isCut: map['isCut'] as bool? ?? false,
      mimeType: map['mimeType'] as String? ?? '',
      compressed: map['compressed'] as bool? ?? false,
      isOriginal: map['isOriginal'] as bool? ?? false,
      fileName: map['fileName'] as String? ?? '',
    );
  }

  /// 转换为 Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'originalPath': originalPath,
      'originalSize': originalSize,
      'originalWidth': originalWidth,
      'originalHeight': originalHeight,
      'path': path,
      'size': size,
      'width': width,
      'height': height,
      'cutPath': cutPath,
      'watermarkPath': watermarkPath,
      'videoThumbnailPath': videoThumbnailPath,
      'sandboxPath': sandboxPath,
      'duration': duration,
      'isCut': isCut,
      'mimeType': mimeType,
      'compressed': compressed,
      'isOriginal': isOriginal,
      'fileName': fileName,
    };
  }

  /// 是否为图片
  bool get isImage => mimeType.startsWith('image/');

  /// 是否为视频
  bool get isVideo => mimeType.startsWith('video/');

  /// 获取实际使用的文件路径（交付路径，用于展示/上传）
  String get deliveryPath => path;

  @override
  String toString() {
    return 'MediaEntity(originalPath: $originalPath, path: $path, mimeType: $mimeType, width: $width, height: $height, size: $size)';
  }
}
