package com.tbchat.tbchat_media_picker

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream

/**
 * 大图安全压缩：仅使用原生 API，通过 inSampleSize 采样后解码并保存为 JPEG，避免 OOM。
 * 流程：获取尺寸 → 计算采样率 → 解码采样 → 压缩保存 → 回收资源。
 */
object SafeImageCompressor {

    private const val TAG = "SafeImageCompressor"

    /** 大于此阈值（字节）时走安全压缩，否则交给 Luban */
    const val LARGE_IMAGE_THRESHOLD_BYTES = 10 * 1024 * 1024L  // 10MB

    /** 默认最大边像素（采样后不超过此值） */
    const val DEFAULT_MAX_SIDE_PX = 1080

    /** 默认 JPEG 压缩质量 (0-100) */
    const val DEFAULT_QUALITY = 80

    /** 原图像素上限（仅做像素缩放时使用） */
    const val MAX_PIXELS_ORIGINAL = 10_000_000

    /**
     * 仅做像素缩放到不超过 maxPixels 像素，高质量 JPEG（质量 95），不做强压缩。
     * 用于选择原图且 >1000 万像素时，缩放到 ≤1000 万后返回路径。
     *
     * @param context Context
     * @param sourcePath 源路径（文件或 content://）
     * @param targetDir 输出目录
     * @param maxPixels 最大像素数，默认 1000 万
     * @return 缩放后文件路径，失败或无需缩放时返回 null（调用方应继续使用原 path）
     */
    @JvmStatic
    fun resizeToMaxPixels(
        context: Context,
        sourcePath: String?,
        targetDir: File,
        maxPixels: Int = MAX_PIXELS_ORIGINAL
    ): String? {
        if (sourcePath.isNullOrBlank() || maxPixels <= 0) return null
        var inputStream: InputStream? = null
        try {
            inputStream = openSourceStream(context, sourcePath) ?: return null
            val options = BitmapFactory.Options().apply {
                inJustDecodeBounds = true
                inSampleSize = 1
            }
            BitmapFactory.decodeStream(inputStream, null, options)
            inputStream.close()
            inputStream = null

            val srcW = options.outWidth
            val srcH = options.outHeight
            if (srcW <= 0 || srcH <= 0) return null

            val pixelCount = srcW.toLong() * srcH
            if (pixelCount <= maxPixels) return null

            val inSampleSize = maxOf(1, kotlin.math.ceil(kotlin.math.sqrt((pixelCount / maxPixels).toDouble())).toInt())

            inputStream = openSourceStream(context, sourcePath) ?: return null
            val decodeOptions = BitmapFactory.Options().apply {
                inJustDecodeBounds = false
                this.inSampleSize = inSampleSize
                inPreferredConfig = Bitmap.Config.RGB_565
                inDither = false
                inScaled = true
            }
            var bitmap: Bitmap? = BitmapFactory.decodeStream(inputStream, null, decodeOptions)
            inputStream.close()
            inputStream = null

            if (bitmap == null) return null

            val outFile = File(targetDir, "original_resized_${System.currentTimeMillis()}_${bitmap.hashCode()}.jpg")
            FileOutputStream(outFile).use { fos ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, 95, fos)
                fos.flush()
            }
            val path = outFile.absolutePath
            if (!bitmap.isRecycled) bitmap.recycle()
            bitmap = null
            return path
        } catch (e: OutOfMemoryError) {
            Log.e(TAG, "OOM during resizeToMaxPixels", e)
            return null
        } catch (e: Exception) {
            Log.e(TAG, "resizeToMaxPixels failed: ${e.message}", e)
            return null
        } finally {
            try { inputStream?.close() } catch (_: Exception) { }
        }
    }

    /**
     * 安全压缩大图并保存为 JPEG。
     *
     * @param context Context，用于 content:// 的 InputStream
     * @param sourcePath 源路径：文件路径或 content:// URI 字符串
     * @param targetDir 输出目录（如 context.cacheDir）
     * @param maxSidePx 采样后最大边像素，默认 1080
     * @param quality JPEG 质量 0-100，默认 80
     * @return 压缩后文件路径，失败返回 null
     */
    @JvmStatic
    fun compress(
        context: Context,
        sourcePath: String?,
        targetDir: File,
        maxSidePx: Int = DEFAULT_MAX_SIDE_PX,
        quality: Int = DEFAULT_QUALITY
    ): String? {
        if (sourcePath.isNullOrBlank()) return null
        var inputStream: InputStream? = null
        try {
            // 1) 获取尺寸（仅读头，不分配像素内存）
            inputStream = openSourceStream(context, sourcePath) ?: return null
            val options = BitmapFactory.Options().apply {
                inJustDecodeBounds = true
                inSampleSize = 1
            }
            BitmapFactory.decodeStream(inputStream, null, options)
            inputStream.close()
            inputStream = null

            val srcW = options.outWidth
            val srcH = options.outHeight
            if (srcW <= 0 || srcH <= 0) {
                Log.w(TAG, "Invalid bounds: ${options.outWidth}x${options.outHeight}")
                return null
            }

            // 2) 计算采样率，使 max(w,h)/inSampleSize <= maxSidePx
            val inSampleSize = computeInSampleSize(srcW, srcH, maxSidePx)

            // 3) 解码采样（只分配采样后尺寸的内存）
            inputStream = openSourceStream(context, sourcePath) ?: return null
            val decodeOptions = BitmapFactory.Options().apply {
                inJustDecodeBounds = false
                this.inSampleSize = inSampleSize
                inPreferredConfig = Bitmap.Config.RGB_565  // 无透明通道时减半内存
                inDither = false
                inScaled = true
            }
            var bitmap: Bitmap? = BitmapFactory.decodeStream(inputStream, null, decodeOptions)
            inputStream.close()
            inputStream = null

            if (bitmap == null) {
                Log.w(TAG, "decodeStream returned null")
                return null
            }

            // 4) 压缩保存为 JPEG
            val outFile = File(targetDir, "safe_compress_${System.currentTimeMillis()}_${bitmap.hashCode()}.jpg")
            FileOutputStream(outFile).use { fos ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, quality.coerceIn(0, 100), fos)
                fos.flush()
            }

            val path = outFile.absolutePath
            // 5) 回收资源
            if (!bitmap.isRecycled) {
                bitmap.recycle()
            }
            bitmap = null
            return path
        } catch (e: OutOfMemoryError) {
            Log.e(TAG, "OOM during safe compress", e)
            return null
        } catch (e: Exception) {
            Log.e(TAG, "Safe compress failed: ${e.message}", e)
            return null
        } finally {
            try {
                inputStream?.close()
            } catch (_: Exception) { }
        }
    }

    /**
     * 计算 inSampleSize，使采样后长边不超过 maxSidePx。
     * inSampleSize >= 1，且优先为 2 的幂以兼容旧设备（可选）。
     */
    @JvmStatic
    fun computeInSampleSize(srcW: Int, srcH: Int, maxSidePx: Int): Int {
        if (maxSidePx <= 0) return 1
        val longSide = maxOf(srcW, srcH)
        if (longSide <= maxSidePx) return 1
        val size = (longSide + maxSidePx - 1) / maxSidePx
        return maxOf(1, size)
    }

    /**
     * 获取源文件大小（字节）。支持 file 路径与 content://；content 时通过 openFileDescriptor 取长度，不将文件读入内存。
     * 无法取得大小时（如 API &lt; 21 的 content）返回 &gt; 阈值，以走安全压缩避免 OOM。
     */
    @JvmStatic
    fun getSourceSize(context: Context, sourcePath: String?): Long {
        if (sourcePath.isNullOrBlank()) return 0L
        return when {
            sourcePath.startsWith("content://") -> {
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                        context.contentResolver.openFileDescriptor(Uri.parse(sourcePath), "r")?.use { it.statSize } ?: (LARGE_IMAGE_THRESHOLD_BYTES + 1)
                    } else {
                        LARGE_IMAGE_THRESHOLD_BYTES + 1
                    }
                } catch (_: Exception) {
                    LARGE_IMAGE_THRESHOLD_BYTES + 1
                }
            }
            else -> {
                try {
                    File(sourcePath).length()
                } catch (_: Exception) {
                    0L
                }
            }
        }
    }

    /**
     * 仅读取图片宽高（inJustDecodeBounds），不解码像素。用于未选原图时从原图路径取原图尺寸。
     * @return Pair(width, height)，失败返回 null
     */
    @JvmStatic
    fun getSourceDimensions(context: Context, sourcePath: String?): Pair<Int, Int>? {
        if (sourcePath.isNullOrBlank()) return null
        var inputStream: InputStream? = null
        try {
            inputStream = openSourceStream(context, sourcePath) ?: return null
            val options = BitmapFactory.Options().apply {
                inJustDecodeBounds = true
                inSampleSize = 1
            }
            BitmapFactory.decodeStream(inputStream, null, options)
            val w = options.outWidth
            val h = options.outHeight
            return if (w > 0 && h > 0) Pair(w, h) else null
        } catch (e: Exception) {
            Log.e(TAG, "getSourceDimensions failed: ${e.message}")
            return null
        } finally {
            try { inputStream?.close() } catch (_: Exception) { }
        }
    }

    private fun openSourceStream(context: Context, sourcePath: String): InputStream? {
        return try {
            if (sourcePath.startsWith("content://")) {
                context.contentResolver.openInputStream(Uri.parse(sourcePath))
            } else {
                java.io.FileInputStream(File(sourcePath))
            }
        } catch (e: Exception) {
            Log.e(TAG, "openSourceStream failed: ${e.message}")
            null
        }
    }
}
