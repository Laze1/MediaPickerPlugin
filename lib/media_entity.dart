/// 媒体实体类，用于接收选择图片/视频的结果
class MediaEntity {
  /// 媒体ID
  final int id;
  
  /// 文件路径(真实路径)
  final String path;
  
  /// 压缩后的路径
  final String compressPath;
  
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
  
  /// 宽度（图片/视频）
  final int width;
  
  /// 高度（图片/视频）
  final int height;
  
  /// 裁剪图片宽度
  final int cropImageWidth;
  
  /// 裁剪图片高度
  final int cropImageHeight;
  
  /// 裁剪偏移X
  final int cropOffsetX;
  
  /// 裁剪偏移Y
  final int cropOffsetY;
  
  /// 裁剪结果宽高比
  final double cropResultAspectRatio;
  
  /// 文件大小（字节）
  final int size;
  
  /// 是否原图
  final bool isOriginal;
  
  /// 文件名
  final String fileName;

  const MediaEntity({
    required this.id,
    required this.path,
    required this.duration,
    required this.size,
    required this.fileName,
    this.compressPath = '',
    this.cutPath = '',
    this.watermarkPath = '',
    this.videoThumbnailPath = '',
    this.sandboxPath = '',
    this.isCut = false,
    this.mimeType = '',
    this.compressed = false,
    this.width = 0,
    this.height = 0,
    this.cropImageWidth = 0,
    this.cropImageHeight = 0,
    this.cropOffsetX = 0,
    this.cropOffsetY = 0,
    this.cropResultAspectRatio = 0.0,
    this.isOriginal = false,
  });

  /// 从 Map 创建 MediaEntity
  factory MediaEntity.fromMap(Map<String, dynamic> map) {
    return MediaEntity(
      id: map['id'] as int? ?? 0,
      path: map['path'] as String? ?? '',
      compressPath: map['compressPath'] as String? ?? '',
      cutPath: map['cutPath'] as String? ?? '',
      watermarkPath: map['watermarkPath'] as String? ?? '',
      videoThumbnailPath: map['videoThumbnailPath'] as String? ?? '',
      sandboxPath: map['sandboxPath'] as String? ?? '',
      duration: map['duration'] as int? ?? 0,
      isCut: map['isCut'] as bool? ?? false,
      mimeType: map['mimeType'] as String? ?? '',
      compressed: map['compressed'] as bool? ?? false,
      width: map['width'] as int? ?? 0,
      height: map['height'] as int? ?? 0,
      cropImageWidth: map['cropImageWidth'] as int? ?? 0,
      cropImageHeight: map['cropImageHeight'] as int? ?? 0,
      cropOffsetX: map['cropOffsetX'] as int? ?? 0,
      cropOffsetY: map['cropOffsetY'] as int? ?? 0,
      cropResultAspectRatio: (map['cropResultAspectRatio'] as num?)?.toDouble() ?? 0.0,
      size: map['size'] as int? ?? 0,
      isOriginal: map['isOriginal'] as bool? ?? false,
      fileName: map['fileName'] as String? ?? '',
    );
  }

  /// 转换为 Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'path': path,
      'compressPath': compressPath,
      'cutPath': cutPath,
      'watermarkPath': watermarkPath,
      'videoThumbnailPath': videoThumbnailPath,
      'sandboxPath': sandboxPath,
      'duration': duration,
      'isCut': isCut,
      'mimeType': mimeType,
      'compressed': compressed,
      'width': width,
      'height': height,
      'cropImageWidth': cropImageWidth,
      'cropImageHeight': cropImageHeight,
      'cropOffsetX': cropOffsetX,
      'cropOffsetY': cropOffsetY,
      'cropResultAspectRatio': cropResultAspectRatio,
      'size': size,
      'isOriginal': isOriginal,
      'fileName': fileName,
    };
  }

  /// 是否为图片
  bool get isImage => mimeType.startsWith('image/');

  /// 是否为视频
  bool get isVideo => mimeType.startsWith('video/');

  /// 获取原图需求路径
  String getOriginalPath(){
    if(isImage && !isOriginal){
      return compressPath;
    }
    return path;
  }

  @override
  String toString() {
    return 'MediaEntity(path: $path, mimeType: $mimeType, width: $width, height: $height, size: $size)';
  }
}
