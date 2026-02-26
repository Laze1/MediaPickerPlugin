import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tbchat_media_picker/tbchat_media_picker.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  List<MediaEntity> _selectedMedia = [];
  bool _isLoading = false;

  Future<void> _pickMedia({
    int mimeType = 0,
    int maxSelectNum = 1,
  }) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final results = await TbchatMediaPicker.pickMedia(
        mimeType: mimeType,
        maxSelectNum: maxSelectNum,
        gridCount: 3,
      );

      setState(() {
        _selectedMedia = results;
        _isLoading = false;
      });
    } on PlatformException catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        debugPrint('选择失败: ${e.message}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选择失败: ${e.message}')),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        debugPrint('发生错误: ${e.toString()}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发生错误: $e')),
        );
      }
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    } else {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    if (minutes > 0) {
      return '$minutes分$remainingSeconds秒';
    }
    return '$remainingSeconds秒';
  }

  /// 获取文件大小（异步）
  Future<int> _getFileSize(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        return await file.length();
      }
    } catch (e) {
      debugPrint('获取文件大小失败: $e');
    }
    return 0;
  }

  /// 获取图片文件的宽高，返回 "宽 × 高"；失败或非图片返回空字符串
  Future<String> _getImageDimensions(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return '';
      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return '';
      return '${image.width} × ${image.height}';
    } catch (e) {
      debugPrint('获取图片尺寸失败: $e');
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('媒体选择器示例'),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '选择媒体文件',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _pickMedia(mimeType: 0, maxSelectNum: 9),
                            icon: const Icon(Icons.photo_library),
                            label: const Text('图片和视频\n(最多9张)'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _pickMedia(mimeType: 1, maxSelectNum: 9),
                            icon: const Icon(Icons.image),
                            label: const Text('仅图片\n(最多9张)'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _pickMedia(mimeType: 2, maxSelectNum: 1),
                            icon: const Icon(Icons.videocam),
                            label: const Text('仅视频\n(单选)'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _pickMedia(mimeType: 0, maxSelectNum: 1),
                            icon: const Icon(Icons.photo),
                            label: const Text('单选\n(图片/视频)'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    if (_selectedMedia.isNotEmpty) ...[
                      const Divider(),
                      Text(
                        '已选择 ${_selectedMedia.length} 个文件',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ..._selectedMedia.asMap().entries.map((entry) {
                        final index = entry.key;
                        final media = entry.value;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 预览区：放在 id 上方，展示图片/视频及压缩缩略图（如有）
                                _buildMediaPreview(media),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Icon(
                                      media.isImage
                                          ? Icons.image
                                          : media.isVideo
                                              ? Icons.videocam
                                              : Icons.insert_drive_file,
                                      color: Theme.of(context).primaryColor,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '文件 ${index + 1}',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                // 基本信息
                                if (media.id > 0)
                                  _buildInfoRow('ID', media.id.toString()),
                                if (media.fileName.isNotEmpty)
                                  _buildInfoRow('文件名', media.fileName),
                                if (media.mimeType.isNotEmpty)
                                  _buildInfoRow('MIME类型', media.mimeType),
                                if (media.size > 0)
                                  _buildInfoRow('文件大小', _formatFileSize(media.size)),
                                if (media.duration > 0)
                                  _buildInfoRow('时长', _formatDuration(media.duration)),
                                
                                // 尺寸信息
                                if (media.width > 0 && media.height > 0)
                                  _buildInfoRow('尺寸', '${media.width} × ${media.height}'),
                                if (media.cropImageWidth > 0 && media.cropImageHeight > 0)
                                  _buildInfoRow('裁剪尺寸', '${media.cropImageWidth} × ${media.cropImageHeight}'),
                                if (media.cropOffsetX != 0 || media.cropOffsetY != 0)
                                  _buildInfoRow('裁剪偏移', 'X: ${media.cropOffsetX}, Y: ${media.cropOffsetY}'),
                                if (media.cropResultAspectRatio > 0)
                                  _buildInfoRow('裁剪宽高比', media.cropResultAspectRatio.toStringAsFixed(2)),
                                
                                // 路径信息
                                if (media.path.isNotEmpty)
                                  _buildInfoRow('路径', media.path),
                                if (media.cutPath.isNotEmpty)
                                  _buildInfoRow('裁剪路径', media.cutPath),
                                if (media.compressPath.isNotEmpty) ...[
                                  _buildInfoRow('压缩路径', media.compressPath),
                                  FutureBuilder<int>(
                                    future: _getFileSize(media.compressPath),
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState == ConnectionState.waiting) {
                                        return _buildInfoRow('压缩后大小', '加载中...');
                                      } else if (snapshot.hasData && snapshot.data! > 0) {
                                        return _buildInfoRow('压缩后大小', _formatFileSize(snapshot.data!));
                                      } else {
                                        return const SizedBox.shrink();
                                      }
                                    },
                                  ),
                                  FutureBuilder<String>(
                                    future: _getImageDimensions(media.compressPath),
                                    builder: (context, snapshot) {
                                      if (snapshot.connectionState == ConnectionState.waiting) {
                                        return _buildInfoRow('压缩后尺寸', '加载中...');
                                      } else if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                                        return _buildInfoRow('压缩后尺寸', snapshot.data!);
                                      } else {
                                        return const SizedBox.shrink();
                                      }
                                    },
                                  ),
                                ],
                                if (media.watermarkPath.isNotEmpty)
                                  _buildInfoRow('水印路径', media.watermarkPath),
                                if (media.videoThumbnailPath.isNotEmpty)
                                  _buildInfoRow('视频缩略图', media.videoThumbnailPath),
                                if (media.sandboxPath.isNotEmpty)
                                  _buildInfoRow('沙箱路径', media.sandboxPath),
                                
                                // 状态信息
                                _buildInfoRow('已裁剪', media.isCut ? '是' : '否'),
                                _buildInfoRow('已压缩', media.compressed ? '是' : '否'),
                                _buildInfoRow('原图', media.isOriginal ? '是' : '否'),
                                ],
                            ),
                          ),
                        );
                      }),
                    ] else ...[
                      const SizedBox(height: 24),
                      const Center(
                        child: Text(
                          '请点击上方按钮选择媒体文件',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 在 id 上方展示选择的图片/视频；若有压缩图则一并展示
  Widget _buildMediaPreview(MediaEntity media) {
    const double previewHeight = 120;
    const double spacing = 8;

    Widget thumbnail(String path, String label) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: previewHeight,
          height: previewHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                File(path),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.grey.shade200,
                  child: const Center(
                    child: Icon(Icons.broken_image, size: 32, color: Colors.grey),
                  ),
                ),
              ),
              if (label.isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    color: Colors.black54,
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    if (media.isImage) {
      final hasCompress = media.compressPath.isNotEmpty && media.compressPath != media.path;
      if (hasCompress) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            thumbnail(media.path, '原图'),
            const SizedBox(width: spacing),
            thumbnail(media.compressPath, '压缩'),
          ],
        );
      }
      final displayPath = media.sandboxPath.isNotEmpty ? media.sandboxPath : media.path;
      if (displayPath.isEmpty) return const SizedBox.shrink();
      return thumbnail(displayPath, '');
    }

    if (media.isVideo) {
      if (media.videoThumbnailPath.isNotEmpty) {
        return thumbnail(media.videoThumbnailPath, '视频缩略图');
      }
      return SizedBox(
        height: previewHeight,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            color: Colors.grey.shade200,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.videocam, size: 48, color: Colors.grey),
                  SizedBox(height: 4),
                  Text('视频', style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
