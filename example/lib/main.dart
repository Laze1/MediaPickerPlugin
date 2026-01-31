import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final _tbchatMediaPickerPlugin = TbchatMediaPicker();
  List<Map<String, dynamic>> _selectedMedia = [];
  bool _isLoading = false;

  Future<void> _pickMedia({
    int mimeType = 0,
    int maxSelectNum = 1,
  }) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final results = await _tbchatMediaPickerPlugin.pickMedia(
        mimeType: mimeType,
        maxSelectNum: maxSelectNum,
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

  String _formatDuration(int milliseconds) {
    if (milliseconds < 1000) {
      return '${milliseconds}ms';
    }
    final seconds = milliseconds ~/ 1000;
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    if (minutes > 0) {
      return '${minutes}分${remainingSeconds}秒';
    }
    return '${remainingSeconds}秒';
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
                        final isImage = (media['mimeType'] as String? ?? '')
                            .startsWith('image/');
                        final isVideo = (media['mimeType'] as String? ?? '')
                            .startsWith('video/');

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      isImage
                                          ? Icons.image
                                          : isVideo
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
                                _buildInfoRow('文件名', media['fileName'] ?? '未知'),
                                _buildInfoRow('路径', media['path'] ?? ''),
                                if (media['width'] != null && media['height'] != null)
                                  _buildInfoRow(
                                    '尺寸',
                                    '${media['width']} × ${media['height']}',
                                  ),
                                if (media['duration'] != null && media['duration'] > 0)
                                  _buildInfoRow(
                                    '时长',
                                    _formatDuration(media['duration'] as int),
                                  ),
                                if (media['size'] != null)
                                  _buildInfoRow(
                                    '大小',
                                    _formatFileSize(media['size'] as int),
                                  ),
                                _buildInfoRow('MIME类型', media['mimeType'] ?? ''),
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
}
