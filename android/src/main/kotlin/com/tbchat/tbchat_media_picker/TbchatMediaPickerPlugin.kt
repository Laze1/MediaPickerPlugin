package com.tbchat.tbchat_media_picker

import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.io.FileOutputStream
import java.io.OutputStream
import java.util.UUID
import com.luck.picture.lib.basic.PictureSelector
import com.luck.picture.lib.config.SelectMimeType
import com.luck.picture.lib.config.SelectModeConfig
import com.luck.picture.lib.engine.CompressFileEngine
import com.luck.picture.lib.entity.LocalMedia
import com.luck.picture.lib.interfaces.OnKeyValueResultCallbackListener
import com.luck.picture.lib.interfaces.OnResultCallbackListener
import com.luck.picture.lib.interfaces.OnVideoThumbnailEventListener
import com.luck.picture.lib.style.PictureSelectorStyle
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import org.json.JSONArray
import org.json.JSONObject
import top.zibin.luban.Luban
import top.zibin.luban.OnNewCompressListener
import java.io.File
import java.util.ArrayList

/** TbchatMediaPickerPlugin */
class TbchatMediaPickerPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware {
    // The MethodChannel that will the communication between Flutter and native Android
    private lateinit var channel: MethodChannel
    private var activity: Activity? = null
    @Suppress("UNCHECKED_CAST")
    private var pendingResult: Result? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "tbchat_media_picker")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        if (call.method == "getPlatformVersion") {
            result.success("Android ${android.os.Build.VERSION.RELEASE}")
        } else if (call.method == "pickMedia") {
            if (activity == null) {
                result.error("NO_ACTIVITY", "Activity is not available", null)
                return
            }
            
            // 保存 result，在回调中使用
            pendingResult = result
            
            // 解析参数
            val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
            val mimeType = args["mimeType"] as? Int ?: 0 // 0: all, 1: image, 2: video
            val maxSelectNum = args["maxSelectNum"] as? Int ?: 1
            var maxSize = args["maxSize"] as? Long ?: 0L
            
            try {
                // 创建选择器（只支持图片和视频，不支持音频）
                val mediaType = when (mimeType) {
                    1 -> SelectMimeType.TYPE_IMAGE
                    2 -> SelectMimeType.TYPE_VIDEO
                    else -> SelectMimeType.TYPE_ALL // 默认全部（图片和视频）
                }
                // 选择模式
                val selectionMode = if (maxSelectNum > 1) SelectModeConfig.MULTIPLE else SelectModeConfig.SINGLE

                // 如果 maxSize 为 0，则默认设置为1GB
                if (maxSize == 0L) {
                    maxSize = 1024 * 1024 * 1024L // 1GB
                }

                PictureSelector.create(activity!!)
                    .openGallery(mediaType)
                    .setMaxSelectNum(maxSelectNum)
                    .setSelectionMode(selectionMode)
                    .setImageEngine(GlideEngine.createGlideEngine())
                    .isOriginalControl(true) //原图选项
                    .isDisplayCamera(false) //不显示相机
                    .setSelectMaxFileSize(maxSize)
                    .setCompressEngine(CompressFileEngine { context, source, compressCallback ->
                        Luban.with(context)
                            .load(source)
                            .setTargetDir(context.cacheDir.path)
                            .setCompressListener(object : OnNewCompressListener {
                                override fun onStart() {}
                                override fun onSuccess(
                                    source: String?,
                                    compressFile: File?
                                ) {
                                    compressCallback?.onCallback(source,compressFile?.absolutePath)
                                }
                                override fun onError(source: String?, e: Throwable?) {
                                    compressCallback?.onCallback(source, null)
                                }
                            }).launch()
                    })
                    .forResult(object : OnResultCallbackListener<LocalMedia> {
                        override fun onResult(result: ArrayList<LocalMedia>) {
                            Log.d("TbchatMediaPickerPlugin", "onResult: $result")
                            handleSelectionResult(result)
                        }
                        
                        override fun onCancel() {
                            pendingResult?.success(JSONArray().toString())
                            pendingResult = null
                        }
                    })
            } catch (e: Exception) {
                pendingResult?.error("PICK_ERROR", "Failed to open media picker: ${e.message}", null)
                pendingResult = null
            }
        } else {
            result.notImplemented()
        }
    }

    private fun handleSelectionResult(result: ArrayList<LocalMedia>) {
        try {
            if (result.isEmpty()) {
                pendingResult?.success(JSONArray().toString())
                pendingResult = null
                return
            }

            val jsonArray = JSONArray()
            for (media in result) {
                if (media.mimeType?.startsWith("video/") == true) {
                    media.videoThumbnailPath = getVideoThumbnail(activity!!, media.realPath ?: "")
                }
                val jsonObject = JSONObject()
                jsonObject.put("id", media.id)
                jsonObject.put("path", media.realPath ?: "")  //直接使用真实路径，不使用path
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

    //获取视频缩略图
    private fun getVideoThumbnail(context: Context, videoPath: String): String {
        val retriever = MediaMetadataRetriever()
        retriever.setDataSource(videoPath)
        val bitmap = retriever.getFrameAtTime(
            0,
            MediaMetadataRetriever.OPTION_CLOSEST_SYNC
        )
        retriever.release()
        if (bitmap != null) {
            val cacheDir = context.cacheDir
            val thumbFile = File(
                cacheDir,
                "video_thumb_${UUID.randomUUID()}.jpg"
            )
            FileOutputStream(thumbFile).use { out: OutputStream ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, 85, out)
            }
            return thumbFile.absolutePath
        }
        return ""
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
}
