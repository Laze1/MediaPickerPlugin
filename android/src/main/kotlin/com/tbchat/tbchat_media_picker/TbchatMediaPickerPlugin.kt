package com.tbchat.tbchat_media_picker

import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.luck.picture.lib.basic.PictureSelector
import com.luck.picture.lib.engine.CompressFileEngine
import com.luck.picture.lib.language.LanguageConfig
import com.luck.picture.lib.entity.LocalMedia
import com.luck.picture.lib.interfaces.OnResultCallbackListener
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import org.json.JSONArray
import top.zibin.luban.Luban
import top.zibin.luban.OnNewCompressListener
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStream
import java.util.ArrayList
import java.util.UUID

/**
 * Flutter 媒体选择插件（Android 端）.
 *
 * ## 职责
 * - 通过 MethodChannel "tbchat_media_picker" 与 Flutter 通信
 * - 使用 PictureSelector 打开系统相册，支持图片/视频选择
 * - 图片压缩：>10MB 用 SafeImageCompressor 避免 OOM，≤10MB 用 Luban
 * - 视频首帧缩略图生成
 * - 将选择结果序列化为 JSON，字段与 Dart 端 [MediaEntity.fromMap] 对应
 *
 * ## 压缩规则
 * - 未选原图：压缩后 path=compressPath，compressed=true
 * - 选原图且 >1000 万像素：仅缩放到 ≤1000 万，path 为缩放后路径
 * - 选原图且 ≤1000 万：不处理
 */
class TbchatMediaPickerPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {

    /** MethodChannel，需与 Dart 端 "tbchat_media_picker" 一致 */
    private lateinit var channel: MethodChannel

    /** 当前 Flutter Activity，由 ActivityAware 绑定；用于 present 选择器 */
    private var activity: Activity? = null

    /** pickMedia 异步回调；选择完成或取消后调用一次并置空，防止重复回调 */
    @Suppress("UNCHECKED_CAST")
    private var pendingResult: Result? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "tbchat_media_picker")
        channel.setMethodCallHandler(this)
    }

    /**
     * 处理 Flutter 侧方法调用.
     * 仅支持 "pickMedia"；其他方法返回 notImplemented.
     */
    override fun onMethodCall(call: MethodCall, result: Result) {
        if (call.method != "pickMedia") {
            result.notImplemented()
            return
        }
        if (activity == null) {
            result.error("NO_ACTIVITY", "Activity is not available", null)
            return
        }

        pendingResult = result
        val args = PickMediaArgs.from(call.arguments as? Map<*, *>)

        try {
            openPicker(args)
        } catch (e: Exception) {
            finishWithError("PICK_ERROR", "Failed to open media picker: ${e.message}")
        }
    }

    /**
     * 打开相册选择器.
     * 配置 PictureSelector：媒体类型、选择模式、压缩引擎、视频缩略图等.
     */
    private fun openPicker(args: PickMediaArgs) {
        val act = activity!!
        PictureSelector.create(act)
            .openGallery(args.mediaType)
            .setSelectionMode(args.selectionMode)
            .setImageEngine(GlideEngine.createGlideEngine())
            .setLanguage(toPictureLanguage(args.language))
            .setImageSpanCount(args.effectiveGridCount)
            .setMaxSelectNum(args.maxSelectNum)
            .setMaxVideoSelectNum(args.maxSelectNum)
            .isWithSelectVideoImage(args.mimeType == 0)
            .isOriginalControl(true)
            .isOriginalSkipCompress(true)
            .isDisplayCamera(false)
            .setSelectMaxFileSize(args.effectiveMaxSize)
            .isPageStrategy(true, 40)
            .isFilterSizeDuration(true)
            .isGif(true)
            .isWebp(true)
            .isBmp(true)
            .setVideoThumbnailListener { ctx, videoPath, callback ->
                callback?.onCallback(videoPath, getVideoThumbnail(ctx!!, videoPath!!))
            }
            .setCompressEngine(createCompressEngine())
            .forResult(createResultListener(args.maxWidth, args.maxHeight))
    }

    /**
     * 创建压缩引擎.
     * - 大图（>10MB）：子线程 SafeImageCompressor 压缩，callback 必须 post 到主线程（否则 PictureSelector 会报 "Can't create handler"）
     * - 小图：Luban 批量压缩，其 listener 已在主线程回调
     */
    private fun createCompressEngine(): CompressFileEngine {
        return CompressFileEngine { context, source, compressCallback ->
            val mainHandler = Handler(Looper.getMainLooper())
            fun uriToPath(uri: Uri): String =
                if (uri.scheme == "content") uri.toString() else (uri.path ?: uri.toString())

            val smallUris = ArrayList<Uri>()
            for (uri in source) {
                val path = uriToPath(uri)
                val size = SafeImageCompressor.getSourceSize(context, path)
                if (size > SafeImageCompressor.LARGE_IMAGE_THRESHOLD_BYTES) {
                    Thread {
                        try {
                            val resultPath = SafeImageCompressor.compress(
                                context, path, context.cacheDir,
                                SafeImageCompressor.DEFAULT_MAX_SIDE_PX,
                                SafeImageCompressor.DEFAULT_QUALITY
                            )
                            mainHandler.post { compressCallback?.onCallback(path, resultPath) }
                        } catch (e: Exception) {
                            Log.e(TAG, "Safe compress failed: ${e.message}")
                            mainHandler.post { compressCallback?.onCallback(path, null) }
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
                    .setCompressListener(object : OnNewCompressListener {
                        override fun onStart() {}
                        override fun onSuccess(src: String?, compressFile: File?) {
                            compressCallback?.onCallback(src, compressFile?.absolutePath)
                        }
                        override fun onError(src: String?, e: Throwable?) {
                            compressCallback?.onCallback(src, null)
                        }
                    })
                    .launch()
            }
        }
    }

    /**
     * 创建选择结果回调.
     * 选择完成：显示 loading，后台构建 JSON，完成后回传；取消：直接返回空数组 "[]".
     */
    private fun createResultListener(maxWidth: Int, maxHeight: Int): OnResultCallbackListener<LocalMedia> {
        return object : OnResultCallbackListener<LocalMedia> {
            override fun onResult(result: ArrayList<LocalMedia>) {
                handleSelectionResult(result, maxWidth, maxHeight)
            }
            override fun onCancel() {
                finishWithSuccess(JSONArray().toString())
            }
        }
    }

    /**
     * 处理选择结果.
     * 1. 空结果：直接返回 "[]"
     * 2. 无 Activity：同步构建 JSON 并返回
     * 3. 有 Activity：显示 loading → 后台线程构建 JSON → 主线程关闭 loading 并回调
     */
    private fun handleSelectionResult(result: ArrayList<LocalMedia>, maxWidth: Int, maxHeight: Int) {
        if (result.isEmpty()) {
            finishWithSuccess(JSONArray().toString())
            return
        }
        val act = activity
        if (act == null) {
            finishWithSuccess(
                MediaResultMapper.toJsonArray(result, null, null, maxWidth, maxHeight)
            )
            return
        }
        val ctx = act.applicationContext
        val cacheDir = ctx.cacheDir
        val loadingDialog = LoadingHelper.createDialog(act)
        act.runOnUiThread { loadingDialog.show() }

        Thread {
            try {
                val jsonStr = MediaResultMapper.toJsonArray(result, ctx, cacheDir, maxWidth, maxHeight)
                act.runOnUiThread {
                    dismissSafely(loadingDialog)
                    finishWithSuccess(jsonStr)
                }
            } catch (e: Exception) {
                act.runOnUiThread {
                    dismissSafely(loadingDialog)
                    finishWithError("RESULT_ERROR", "Failed to process result: ${e.message}")
                }
            }
        }.start()
    }

    /**
     * 生成视频首帧缩略图，写入 cache 目录.
     * content:// 使用 Context.setDataSource 避免 setDataSource(String) 报错.
     * 失败返回空字符串，PictureSelector 会使用默认处理.
     */
    private fun getVideoThumbnail(context: Context, videoPath: String): String {
        return try {
            val retriever = MediaMetadataRetriever()
            retriever.setDataSource(context, Uri.parse(videoPath))
            val bitmap = retriever.getFrameAtTime(0, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            retriever.release()
            if (bitmap != null) {
                val thumbFile = File(context.cacheDir, "video_thumb_${UUID.randomUUID()}.jpg")
                FileOutputStream(thumbFile).use { out: OutputStream ->
                    bitmap.compress(Bitmap.CompressFormat.JPEG, 85, out)
                }
                thumbFile.absolutePath
            } else ""
        } catch (e: Exception) {
            Log.e(TAG, "getVideoThumbnail failed: $e")
            ""
        }
    }

    /**
     * Flutter language 参数映射为 PictureSelector LanguageConfig.
     * 0=跟随系统，1=简体中文，2=繁体中文，3=英语.
     */
    private fun toPictureLanguage(language: Int): Int = when (language) {
        1 -> LanguageConfig.CHINESE
        2 -> LanguageConfig.TRADITIONAL_CHINESE
        3 -> LanguageConfig.ENGLISH
        else -> LanguageConfig.SYSTEM_LANGUAGE
    }

    private fun finishWithSuccess(json: String) {
        pendingResult?.success(json)
        pendingResult = null
    }

    private fun finishWithError(code: String, message: String) {
        pendingResult?.error(code, message, null)
        pendingResult = null
    }

    /** 安全关闭 Dialog，忽略异常（如已 dismiss） */
    private fun dismissSafely(dialog: android.app.Dialog) {
        try {
            dialog.dismiss()
        } catch (_: Exception) {}
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

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

    companion object {
        private const val TAG = "TbchatMediaPickerPlugin"
    }
}
