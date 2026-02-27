package com.tbchat.tbchat_media_picker

import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.util.Log
import com.luck.picture.lib.basic.PictureSelector
import com.luck.picture.lib.config.SelectMimeType
import com.luck.picture.lib.config.SelectModeConfig
import com.luck.picture.lib.engine.CompressFileEngine
import com.luck.picture.lib.entity.LocalMedia
import com.luck.picture.lib.interfaces.OnResultCallbackListener
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStream
import java.util.ArrayList
import java.util.UUID
import org.json.JSONArray
import org.json.JSONObject
import top.zibin.luban.Luban
import top.zibin.luban.OnNewCompressListener

/**
 * Flutter 媒体选择插件（Android 端）.
 *
 * 通过 MethodChannel "tbchat_media_picker" 与 Flutter 通信，使用本地 PictureSelector 打开相册，
 * 支持图片/视频选择、压缩（Luban / 大图安全压缩）、视频首帧缩略图，并将结果序列化为 JSON 数组回传， 与 [MediaEntity] 字段一一对应。
 *
 * 压缩规则：
 * - 未选原图：图片 &gt; 10MB 用 [SafeImageCompressor] 安全压缩，≤10MB 用 Luban；返回 compressPath，compressed=true。
 * - 选原图：不压缩；仅当图片 &gt;1000 万像素时做像素缩放到 ≤1000 万（[resizeToMaxPixels]），path 为缩放后路径，无 compressPath。
 */
class TbchatMediaPickerPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {

    /** 与 Flutter 通信的 MethodChannel，名称需与 Dart 端一致 */
    private lateinit var channel: MethodChannel

    /** 当前 Flutter 宿主 Activity，用于 present 选择器；由 ActivityAware 在 attach/detach 时赋值 */
    private var activity: Activity? = null

    /** pickMedia 的异步回调，在用户完成选择或取消后调用一次并置空，避免重复回调 */
    @Suppress("UNCHECKED_CAST") private var pendingResult: Result? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "tbchat_media_picker")
        channel.setMethodCallHandler(this)
    }

    /**
     * 处理 Flutter 侧方法调用.
     * - pickMedia: 打开相册选择图片/视频，参数 mimeType/maxSelectNum/maxSize，结果通过 pendingResult 回传 JSON 数组或错误.
     */
    override fun onMethodCall(call: MethodCall, result: Result) {
        if (call.method == "pickMedia") {
            if (activity == null) {
                result.error("NO_ACTIVITY", "Activity is not available", null)
                return
            }

            pendingResult = result

            // 解析参数
            val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
            val mimeType = args["mimeType"] as? Int ?: 0 // 0: 全部(图+视频), 1: 仅图片, 2: 仅视频
            val maxSelectNum = args["maxSelectNum"] as? Int ?: 1
            var maxSize = args["maxSize"] as? Long ?: 0L
            val gridCount = args["gridCount"] as? Int ?: 4 // 每排显示数量，默认 4

            try {
                val mediaType =
                        when (mimeType) {
                            1 -> SelectMimeType.TYPE_IMAGE
                            2 -> SelectMimeType.TYPE_VIDEO
                            else -> SelectMimeType.TYPE_ALL
                        }
                val selectionMode =
                        if (maxSelectNum > 1) SelectModeConfig.MULTIPLE else SelectModeConfig.SINGLE

                if (maxSize == 0L) {
                    maxSize = 1024 * 1024 * 1024L // 0 表示不限制，此处按 1GB 处理
                }

                PictureSelector.create(activity!!)
                        .openGallery(mediaType)
                        .setSelectionMode(selectionMode)
                        .setImageEngine(GlideEngine.createGlideEngine())
                        // .setLanguage() //设置相册语言
                        .setImageSpanCount(if (gridCount > 0) gridCount else 4) // 每排显示数量
                        .setMaxSelectNum(maxSelectNum) // 设置图片最大选择数量
                        .setMaxVideoSelectNum(maxSelectNum) // 设置视频最大选择数量
                        .isWithSelectVideoImage(true) // 支持图片视频同选
                        .isOriginalControl(true) // 原图选项
                        .isOriginalSkipCompress(true) // 选原图时不走压缩引擎，仅做 >10M 像素缩放
                        .isDisplayCamera(false) // 不显示相机
                        .setSelectMaxFileSize(maxSize) // 设置最大选择大小
                        .isPageStrategy(true, 40) // 分页模式，每页10条
                        .isFilterSizeDuration(true) // 过滤视频小于1秒和文件小于1kb
                        .isGif(true) // 是否显示gif文件
                        .isWebp(true) // 是否显示webp文件
                        .isBmp(true) // 是否显示bmp文件
                        .setVideoThumbnailListener { context, videoPath, thumbnailCallback ->
                            thumbnailCallback?.onCallback(
                                    videoPath,
                                    getVideoThumbnail(context!!, videoPath!!)
                            )
                        }
                        .setCompressEngine(
                                CompressFileEngine { context, source, compressCallback ->
                                    fun uriToPath(uri: Uri): String =
                                        if (uri.scheme == "content") uri.toString() else (uri.path ?: uri.toString())

                                    val smallUris = ArrayList<Uri>()
                                    for (uri in source) {
                                        val path = uriToPath(uri)
                                        val size = SafeImageCompressor.getSourceSize(context, path)
                                        if (size > SafeImageCompressor.LARGE_IMAGE_THRESHOLD_BYTES) {
                                            // 大图（>10MB）：子线程安全压缩，避免 OOM
                                            Thread {
                                                try {
                                                    val resultPath = SafeImageCompressor.compress(
                                                            context,
                                                            path,
                                                            context.cacheDir,
                                                            SafeImageCompressor.DEFAULT_MAX_SIDE_PX,
                                                            SafeImageCompressor.DEFAULT_QUALITY
                                                    )
                                                    compressCallback?.onCallback(path, resultPath)
                                                } catch (e: Exception) {
                                                    Log.e("TbchatMediaPickerPlugin", "Safe compress failed: ${e.message}")
                                                    compressCallback?.onCallback(path, null)
                                                }
                                            }.start()
                                        } else {
                                            smallUris.add(uri)
                                        }
                                    }
                                    if (smallUris.isNotEmpty()) {
                                        Luban.with(context)
                                            .load(smallUris)
                                            .setTargetDir(context.cacheDir.path)
                                            .setCompressListener(
                                                    object : OnNewCompressListener {
                                                        override fun onStart() {}
                                                        override fun onSuccess(
                                                                src: String?,
                                                                compressFile: File?
                                                        ) {
                                                            compressCallback?.onCallback(
                                                                    src,
                                                                    compressFile?.absolutePath
                                                            )
                                                        }

                                                        override fun onError(
                                                                src: String?,
                                                                e: Throwable?
                                                        ) {
                                                            compressCallback?.onCallback(src, null)
                                                        }
                                                    }
                                            )
                                            .launch()
                                    }
                                }
                        )
                        .forResult(
                                object : OnResultCallbackListener<LocalMedia> {
                                    override fun onResult(result: ArrayList<LocalMedia>) {
                                        Log.d("TbchatMediaPickerPlugin", "onResult: $result")
                                        handleSelectionResult(result)
                                    }

                                    override fun onCancel() {
                                        pendingResult?.success(JSONArray().toString())
                                        pendingResult = null
                                    }
                                }
                        )
            } catch (e: Exception) {
                pendingResult?.error(
                        "PICK_ERROR",
                        "Failed to open media picker: ${e.message}",
                        null
                )
                pendingResult = null
            }
        } else {
            result.notImplemented()
        }
    }

    /**
     * 将 PictureSelector 返回的 [LocalMedia] 列表转成 JSON 数组字符串并回传 Flutter. 字段与 Dart 端 MediaEntity.fromMap
     * 一致，便于双端统一解析.
     * 选原图时：不压缩，仅当图片 >1000 万像素时做像素缩放到 ≤1000 万，path/sandboxPath 用缩放后路径.
     */
    private fun handleSelectionResult(result: ArrayList<LocalMedia>) {
        try {
            if (result.isEmpty()) {
                pendingResult?.success(JSONArray().toString())
                pendingResult = null
                return
            }

            val ctx = activity?.applicationContext
            val cacheDir = ctx?.cacheDir
            val jsonArray = JSONArray()
            for (media in result) {
                val originalPath = media.realPath ?: ""
                var path = originalPath
                var sandboxPath = media.sandboxPath ?: path
                var width = media.width
                var height = media.height
                var size = media.size
                var originalSize = media.size
                var originalWidth = media.width
                var originalHeight = media.height

                if (media.isOriginal && (media.mimeType ?: "").startsWith("image/") && ctx != null && cacheDir != null) {
                    val pixels = width.toLong() * height
                    if (pixels > SafeImageCompressor.MAX_PIXELS_ORIGINAL) {
                        val resizedPath = SafeImageCompressor.resizeToMaxPixels(ctx, originalPath, cacheDir, SafeImageCompressor.MAX_PIXELS_ORIGINAL)
                        if (!resizedPath.isNullOrBlank()) {
                            path = resizedPath
                            size = File(resizedPath).length().coerceAtLeast(0)
                            val scale = kotlin.math.sqrt(SafeImageCompressor.MAX_PIXELS_ORIGINAL.toDouble() / pixels)
                            width = maxOf(1, (media.width * scale).toInt())
                            height = maxOf(1, (media.height * scale).toInt())
                        }
                    }
                } else if (!media.isOriginal && (media.mimeType ?: "").startsWith("image/")) {
                    val hasCompress = !(media.compressPath.isNullOrBlank())
                    if (hasCompress) {
                        path = media.compressPath!!
                        // 交付数据使用压缩后文件的实际大小与尺寸
                        if (ctx != null) {
                            val compressedSize = SafeImageCompressor.getSourceSize(ctx, path)
                            if (compressedSize > 0L && compressedSize != SafeImageCompressor.LARGE_IMAGE_THRESHOLD_BYTES + 1) {
                                size = compressedSize
                            }
                            SafeImageCompressor.getSourceDimensions(ctx, path)?.let { (w, h) ->
                                width = w
                                height = h
                            }
                        }
                        if (size == 0L) size = File(path).length().coerceAtLeast(0)
                        // 原图数据从原图路径读取
                        if (ctx != null && originalPath.isNotEmpty()) {
                            val srcSize = SafeImageCompressor.getSourceSize(ctx, originalPath)
                            if (srcSize > 0L && srcSize != SafeImageCompressor.LARGE_IMAGE_THRESHOLD_BYTES + 1) {
                                originalSize = srcSize
                            }
                            SafeImageCompressor.getSourceDimensions(ctx, originalPath)?.let { (w, h) ->
                                originalWidth = w
                                originalHeight = h
                            }
                        }
                    }
                }

                val jsonObject = JSONObject()
                jsonObject.put("id", media.id)
                jsonObject.put("originalPath", originalPath)
                jsonObject.put("originalSize", originalSize)
                jsonObject.put("originalWidth", originalWidth)
                jsonObject.put("originalHeight", originalHeight)
                jsonObject.put("path", path)
                jsonObject.put("size", size)
                jsonObject.put("width", width)
                jsonObject.put("height", height)
                jsonObject.put("cutPath", media.cutPath ?: "")
                jsonObject.put("watermarkPath", media.watermarkPath ?: "")
                jsonObject.put("videoThumbnailPath", media.videoThumbnailPath ?: "")
                jsonObject.put("duration", media.duration / 1000)
                jsonObject.put("isChecked", media.isChecked)
                jsonObject.put("isCut", media.isCut)
                jsonObject.put("position", media.position)
                jsonObject.put("num", media.num)
                jsonObject.put("mimeType", media.mimeType ?: "")
                jsonObject.put("chooseModel", media.chooseModel)
                jsonObject.put("isCameraSource", media.isCameraSource)
                jsonObject.put("compressed", media.isCompressed)
                jsonObject.put("isOriginal", media.isOriginal)
                jsonObject.put("fileName", media.fileName ?: "")
                jsonObject.put("parentFolderName", media.parentFolderName ?: "")
                jsonObject.put("bucketId", media.bucketId)
                jsonObject.put("dateAddedTime", media.dateAddedTime)
                jsonObject.put("customData", media.customData ?: "")
                jsonObject.put("isMaxSelectEnabledMask", media.isMaxSelectEnabledMask)
                jsonObject.put("isGalleryEnabledMask", media.isGalleryEnabledMask)
                jsonObject.put("isEditorImage", media.isEditorImage)
                jsonArray.put(jsonObject)
            }

            pendingResult?.success(jsonArray.toString())
            pendingResult = null
        } catch (e: Exception) {
            pendingResult?.error("RESULT_ERROR", "Failed to process result: ${e.message}", null)
            pendingResult = null
        }
    }

    /**
     * 取视频首帧作为缩略图，写入 cache 目录并返回本地路径. 若 [videoPath] 为 content:// 则使用 [Context] 重载的 setDataSource，避免
     * setDataSource(String) 报错. 失败时返回空字符串，由 PictureSelector 使用默认处理.
     */
    private fun getVideoThumbnail(context: Context, videoPath: String): String {
        return try {
            val retriever = MediaMetadataRetriever()
            retriever.setDataSource(context, Uri.parse(videoPath))
            val bitmap = retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            retriever.release()
            if (bitmap != null) {
                val cacheDir = context.cacheDir
                val thumbFile = File(cacheDir, "video_thumb_${UUID.randomUUID()}.jpg")
                FileOutputStream(thumbFile).use { out: OutputStream ->
                    bitmap.compress(Bitmap.CompressFormat.JPEG, 85, out)
                }
                thumbFile.absolutePath
            } else ""
        } catch (e: Exception) {
            Log.e("TbchatMediaPickerPlugin", "getVideoThumbnail failed: $e")
            ""
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    /** Activity 绑定后保存引用，用于 present 相册选择器 */
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }
}
