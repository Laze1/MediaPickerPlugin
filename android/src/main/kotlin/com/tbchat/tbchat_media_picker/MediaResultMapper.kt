package com.tbchat.tbchat_media_picker

import android.content.Context
import com.luck.picture.lib.entity.LocalMedia
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * 将 PictureSelector 返回的 [LocalMedia] 列表映射为 MediaEntity JSON 数组字符串.
 *
 * ## 处理逻辑
 * 1. **选原图且 >1000 万像素**：缩放到 ≤1000 万，path 为缩放后路径
 * 2. **未选原图**：使用压缩后路径及尺寸（path=compressPath）
 * 3. **maxWidth/maxHeight**：若交付图超限，再缩放到限制以内
 *
 * 字段与 Dart 端 [MediaEntity.fromMap] 一一对应，保证双端数据结构统一.
 */
object MediaResultMapper {

    /**
     * 将 LocalMedia 列表转为 JSON 数组字符串.
     * @param ctx 用于读取文件尺寸/打开 content://；null 时跳过需 Context 的处理
     * @param cacheDir 缩放/压缩输出目录；null 时跳过需目录的处理
     */
    fun toJsonArray(
        mediaList: List<LocalMedia>,
        ctx: Context?,
        cacheDir: File?,
        maxWidth: Int,
        maxHeight: Int
    ): String {
        val jsonArray = JSONArray()
        for (media in mediaList) {
            jsonArray.put(toJsonObject(media, ctx, cacheDir, maxWidth, maxHeight))
        }
        return jsonArray.toString()
    }

    /** 单条 LocalMedia 转为 JSONObject */
    private fun toJsonObject(
        media: LocalMedia,
        ctx: Context?,
        cacheDir: File?,
        maxWidth: Int,
        maxHeight: Int
    ): JSONObject {
        val originalPath = media.realPath ?: ""
        var path = originalPath
        var sandboxPath = media.sandboxPath ?: path
        var width = media.width
        var height = media.height
        var size = media.size
        var originalSize = media.size
        var originalWidth = media.width
        var originalHeight = media.height

        if (media.isOriginal && media.isImage && ctx != null && cacheDir != null) {
            resolveOriginalImage(media, originalPath, ctx, cacheDir)?.let { (p, w, h, s) ->
                path = p
                width = w
                height = h
                size = s
            }
        } else if (!media.isOriginal && media.isImage) {
            resolveCompressedImage(media, originalPath, ctx)?.let { (p, w, h, s, oW, oH, oS) ->
                path = p
                width = w
                height = h
                size = s
                originalWidth = oW
                originalHeight = oH
                originalSize = oS
            }
        }

        if (maxWidth > 0 && maxHeight > 0 && media.isImage && ctx != null && cacheDir != null) {
            applyMaxDimensions(ctx, cacheDir, path, maxWidth, maxHeight)?.let { (p, w, h, s) ->
                path = p
                sandboxPath = p
                width = w
                height = h
                size = s
            }
        }

        return buildMediaJson(
            media = media,
            path = path,
            sandboxPath = sandboxPath,
            width = width,
            height = height,
            size = size,
            originalPath = originalPath,
            originalWidth = originalWidth,
            originalHeight = originalHeight,
            originalSize = originalSize
        )
    }

    /** 扩展：判断是否为图片类型 */
    private val LocalMedia.isImage: Boolean
        get() = (mimeType ?: "").startsWith("image/")

    /**
     * 选原图且 >1000 万像素：缩放到 ≤1000 万.
     * @return (path, width, height, size) 或 null（无需缩放）
     */
    private fun resolveOriginalImage(
        media: LocalMedia,
        originalPath: String,
        ctx: Context,
        cacheDir: File
    ): Quadruple<String, Int, Int, Long>? {
        val pixels = media.width.toLong() * media.height
        if (pixels <= SafeImageCompressor.MAX_PIXELS_ORIGINAL) return null
        val resizedPath = SafeImageCompressor.resizeToMaxPixels(
            ctx, originalPath, cacheDir, SafeImageCompressor.MAX_PIXELS_ORIGINAL
        ) ?: return null
        val scale = kotlin.math.sqrt(SafeImageCompressor.MAX_PIXELS_ORIGINAL.toDouble() / pixels)
        val w = maxOf(1, (media.width * scale).toInt())
        val h = maxOf(1, (media.height * scale).toInt())
        val s = File(resizedPath).length().coerceAtLeast(0)
        return Quadruple(resizedPath, w, h, s)
    }

    /**
     * 未选原图：使用压缩后路径及尺寸.
     * 从 compressPath 读取实际尺寸和大小，从 originalPath 读取原图尺寸.
     * @return (path, width, height, size, originalWidth, originalHeight, originalSize) 或 null
     */
    private fun resolveCompressedImage(
        media: LocalMedia,
        originalPath: String,
        ctx: Context?
    ): Septuple<String, Int, Int, Long, Int, Int, Long>? {
        val compressPath = media.compressPath ?: return null
        var width = media.width
        var height = media.height
        var size = media.size
        var originalWidth = media.width
        var originalHeight = media.height
        var originalSize = media.size
        if (ctx != null) {
            val compressedSize = SafeImageCompressor.getSourceSize(ctx, compressPath)
            if (compressedSize > 0 && compressedSize != SafeImageCompressor.LARGE_IMAGE_THRESHOLD_BYTES + 1) {
                size = compressedSize
            }
            SafeImageCompressor.getSourceDimensions(ctx, compressPath)?.let { (w, h) ->
                width = w
                height = h
            }
            if (originalPath.isNotEmpty()) {
                val srcSize = SafeImageCompressor.getSourceSize(ctx, originalPath)
                if (srcSize > 0 && srcSize != SafeImageCompressor.LARGE_IMAGE_THRESHOLD_BYTES + 1) {
                    originalSize = srcSize
                }
                SafeImageCompressor.getSourceDimensions(ctx, originalPath)?.let { (w, h) ->
                    originalWidth = w
                    originalHeight = h
                }
            }
        }
        if (size == 0L) size = File(compressPath).length().coerceAtLeast(0)
        return Septuple(compressPath, width, height, size, originalWidth, originalHeight, originalSize)
    }

    /**
     * maxWidth/maxHeight 限制下缩放.
     * 仅当宽或高超出限制时缩放；否则返回 null.
     * @return (path, width, height, size) 或 null
     */
    private fun applyMaxDimensions(
        ctx: Context,
        cacheDir: File,
        path: String,
        maxWidth: Int,
        maxHeight: Int
    ): Quadruple<String, Int, Int, Long>? {
        val dims = SafeImageCompressor.getSourceDimensions(ctx, path) ?: return null
        val (w, h) = dims
        if (w <= maxWidth && h <= maxHeight) return null
        val limitedPath = SafeImageCompressor.resizeToMaxDimensions(ctx, path, cacheDir, maxWidth, maxHeight)
            ?: return null
        val newDims = SafeImageCompressor.getSourceDimensions(ctx, limitedPath) ?: return null
        val size = File(limitedPath).length().coerceAtLeast(0)
        return Quadruple(limitedPath, newDims.first, newDims.second, size)
    }

    /** 组装单条 MediaEntity 的 JSON 对象，包含 PictureSelector 扩展字段 */
    private fun buildMediaJson(
        media: LocalMedia,
        path: String,
        sandboxPath: String,
        width: Int,
        height: Int,
        size: Long,
        originalPath: String,
        originalWidth: Int,
        originalHeight: Int,
        originalSize: Long
    ): JSONObject {
        return JSONObject().apply {
            put("id", media.id)
            put("originalPath", originalPath)
            put("originalSize", originalSize)
            put("originalWidth", originalWidth)
            put("originalHeight", originalHeight)
            put("path", path)
            put("size", size)
            put("width", width)
            put("height", height)
            put("cutPath", media.cutPath ?: "")
            put("watermarkPath", media.watermarkPath ?: "")
            put("videoThumbnailPath", media.videoThumbnailPath ?: "")
            put("duration", media.duration / 1000)
            put("isChecked", media.isChecked)
            put("isCut", media.isCut)
            put("position", media.position)
            put("num", media.num)
            put("mimeType", media.mimeType ?: "")
            put("chooseModel", media.chooseModel)
            put("isCameraSource", media.isCameraSource)
            put("compressed", media.isCompressed)
            put("isOriginal", media.isOriginal)
            put("fileName", media.fileName ?: "")
            put("parentFolderName", media.parentFolderName ?: "")
            put("bucketId", media.bucketId)
            put("dateAddedTime", media.dateAddedTime)
            put("customData", media.customData ?: "")
            put("isMaxSelectEnabledMask", media.isMaxSelectEnabledMask)
            put("isGalleryEnabledMask", media.isGalleryEnabledMask)
            put("isEditorImage", media.isEditorImage)
        }
    }

    private data class Quadruple<A, B, C, D>(val first: A, val second: B, val third: C, val fourth: D)
    private data class Septuple<A, B, C, D, E, F, G>(
        val first: A, val second: B, val third: C, val fourth: D,
        val fifth: E, val sixth: F, val seventh: G
    )
}
