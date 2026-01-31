/// 媒体实体类，用于接收选择图片/视频的结果
class MediaEntity {
  /// 媒体ID
  final int id;
  
  /// 文件路径
  final String path;
  
  /// 真实文件路径
  final String realPath;
  
  /// 原始路径
  final String originalPath;
  
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
  
  /// 时长（视频，单位：毫秒）
  final int duration;
  
  /// 是否已选中
  final bool isChecked;
  
  /// 是否已裁剪
  final bool isCut;
  
  /// 位置
  final int position;
  
  /// 编号
  final int number;
  
  /// MIME类型（如：image/jpeg, video/mp4）
  final String mimeType;
  
  /// 选择模式
  final int chooseModel;
  
  /// 是否来自相机
  final bool isCameraSource;
  
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
  
  /// 父文件夹名称
  final String parentFolderName;
  
  /// 相册ID
  final int bucketId;
  
  /// 添加时间（时间戳，毫秒）
  final int dateAddedTime;
  
  /// 自定义数据
  final String customData;
  
  /// 是否达到最大选择数遮罩
  final bool isMaxSelectEnabledMask;
  
  /// 是否相册启用遮罩
  final bool isGalleryEnabledMask;
  
  /// 是否编辑图片
  final bool isEditorImage;

  const MediaEntity({
    required this.id,
    required this.path,
    required this.realPath,
    required this.originalPath,
    required this.compressPath,
    required this.cutPath,
    required this.watermarkPath,
    required this.videoThumbnailPath,
    required this.sandboxPath,
    required this.duration,
    required this.isChecked,
    required this.isCut,
    required this.position,
    required this.number,
    required this.mimeType,
    required this.chooseModel,
    required this.isCameraSource,
    required this.compressed,
    required this.width,
    required this.height,
    required this.cropImageWidth,
    required this.cropImageHeight,
    required this.cropOffsetX,
    required this.cropOffsetY,
    required this.cropResultAspectRatio,
    required this.size,
    required this.isOriginal,
    required this.fileName,
    required this.parentFolderName,
    required this.bucketId,
    required this.dateAddedTime,
    required this.customData,
    required this.isMaxSelectEnabledMask,
    required this.isGalleryEnabledMask,
    required this.isEditorImage,
  });

  /// 从 Map 创建 MediaEntity
  factory MediaEntity.fromMap(Map<String, dynamic> map) {
    return MediaEntity(
      id: map['id'] as int? ?? 0,
      path: map['path'] as String? ?? '',
      realPath: map['realPath'] as String? ?? '',
      originalPath: map['originalPath'] as String? ?? '',
      compressPath: map['compressPath'] as String? ?? '',
      cutPath: map['cutPath'] as String? ?? '',
      watermarkPath: map['watermarkPath'] as String? ?? '',
      videoThumbnailPath: map['videoThumbnailPath'] as String? ?? '',
      sandboxPath: map['sandboxPath'] as String? ?? '',
      duration: map['duration'] as int? ?? 0,
      isChecked: map['isChecked'] as bool? ?? false,
      isCut: map['isCut'] as bool? ?? false,
      position: map['position'] as int? ?? 0,
      number: map['num'] as int? ?? 0,
      mimeType: map['mimeType'] as String? ?? '',
      chooseModel: map['chooseModel'] as int? ?? 0,
      isCameraSource: map['isCameraSource'] as bool? ?? false,
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
      parentFolderName: map['parentFolderName'] as String? ?? '',
      bucketId: map['bucketId'] as int? ?? 0,
      dateAddedTime: map['dateAddedTime'] as int? ?? 0,
      customData: map['customData'] as String? ?? '',
      isMaxSelectEnabledMask: map['isMaxSelectEnabledMask'] as bool? ?? false,
      isGalleryEnabledMask: map['isGalleryEnabledMask'] as bool? ?? false,
      isEditorImage: map['isEditorImage'] as bool? ?? false,
    );
  }

  /// 转换为 Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'path': path,
      'realPath': realPath,
      'originalPath': originalPath,
      'compressPath': compressPath,
      'cutPath': cutPath,
      'watermarkPath': watermarkPath,
      'videoThumbnailPath': videoThumbnailPath,
      'sandboxPath': sandboxPath,
      'duration': duration,
      'isChecked': isChecked,
      'isCut': isCut,
      'position': position,
      'num': number,
      'mimeType': mimeType,
      'chooseModel': chooseModel,
      'isCameraSource': isCameraSource,
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
      'parentFolderName': parentFolderName,
      'bucketId': bucketId,
      'dateAddedTime': dateAddedTime,
      'customData': customData,
      'isMaxSelectEnabledMask': isMaxSelectEnabledMask,
      'isGalleryEnabledMask': isGalleryEnabledMask,
      'isEditorImage': isEditorImage,
    };
  }

  /// 是否为图片
  bool get isImage => mimeType.startsWith('image/');

  /// 是否为视频
  bool get isVideo => mimeType.startsWith('video/');

  @override
  String toString() {
    return 'MediaEntity(path: $path, mimeType: $mimeType, width: $width, height: $height, size: $size)';
  }
}
