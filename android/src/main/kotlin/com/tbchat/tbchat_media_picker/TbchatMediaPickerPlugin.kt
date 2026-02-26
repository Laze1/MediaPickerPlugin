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
 * 支持图片/视频选择、压缩（Luban）、视频首帧缩略图，并将结果序列化为 JSON 数组回传， 与 [MediaEntity] 字段一一对应。
 *
 * 不点原图时的行为：
 * - 会走 setCompressEngine 注入的 Luban 压缩（仅对图片）。
 * - Luban：根据原图尺寸计算 inSampleSize 做采样（长边≥1664 时可能缩小 2/4 倍或按 1280 为基准），
 *   再以 JPEG 质量 60 压缩写入 cache 目录。
 * - 返回：path 为原图路径，compressPath 为压缩后路径；compressed=true；分辨率可能降低，质量 60。
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
                                    Luban.with(context)
                                            .load(source)
                                            .setTargetDir(context.cacheDir.path)
                                            .setCompressListener(
                                                    object : OnNewCompressListener {
                                                        override fun onStart() {}
                                                        override fun onSuccess(
                                                                source: String?,
                                                                compressFile: File?
                                                        ) {
                                                            compressCallback?.onCallback(
                                                                    source,
                                                                    compressFile?.absolutePath
                                                            )
                                                        }

                                                        override fun onError(
                                                                source: String?,
                                                                e: Throwable?
                                                        ) {
                                                            compressCallback?.onCallback(
                                                                    source,
                                                                    null
                                                            )
                                                        }
                                                    }
                                            )
                                            .launch()
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
     */
    private fun handleSelectionResult(result: ArrayList<LocalMedia>) {
        try {
            if (result.isEmpty()) {
                pendingResult?.success(JSONArray().toString())
                pendingResult = null
                return
            }

            val jsonArray = JSONArray()
            for (media in result) {
                val jsonObject = JSONObject()
                jsonObject.put("id", media.id)
                jsonObject.put("path", media.realPath ?: "") // 直接使用真实路径，不使用path
                jsonObject.put("originalPath", media.originalPath ?: "")
                jsonObject.put("compressPath", media.compressPath ?: "")
                jsonObject.put("cutPath", media.cutPath ?: "")
                jsonObject.put("watermarkPath", media.watermarkPath ?: "")
                jsonObject.put("videoThumbnailPath", media.videoThumbnailPath ?: "")
                jsonObject.put("sandboxPath", media.sandboxPath ?: "")
                jsonObject.put("duration", media.duration / 1000) // 转换为秒
                jsonObject.put("isChecked", media.isChecked)
                jsonObject.put("isCut", media.isCut)
                jsonObject.put("position", media.position)
                jsonObject.put("num", media.num)
                jsonObject.put("mimeType", media.mimeType ?: "")
                jsonObject.put("chooseModel", media.chooseModel)
                jsonObject.put("isCameraSource", media.isCameraSource)
                jsonObject.put("compressed", media.isCompressed)
                jsonObject.put("width", media.width)
                jsonObject.put("height", media.height)
                jsonObject.put("cropImageWidth", media.cropImageWidth)
                jsonObject.put("cropImageHeight", media.cropImageHeight)
                jsonObject.put("cropOffsetX", media.cropOffsetX)
                jsonObject.put("cropOffsetY", media.cropOffsetY)
                jsonObject.put("cropResultAspectRatio", media.cropResultAspectRatio.toDouble())
                jsonObject.put("size", media.size)
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
