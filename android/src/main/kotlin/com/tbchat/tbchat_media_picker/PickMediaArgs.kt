package com.tbchat.tbchat_media_picker

import com.luck.picture.lib.config.SelectMimeType
import com.luck.picture.lib.config.SelectModeConfig

/**
 * pickMedia 方法参数，从 Flutter 传入的 Map 解析.
 *
 * ## 字段说明
 * - mimeType: 0=全部(图+视频)，1=仅图片，2=仅视频
 * - maxSelectNum: 最大可选数量
 * - maxSize: 最大文件大小（字节），0 表示不限制（按 1GB 处理）
 * - gridCount: 相册网格每排显示数量
 * - maxWidth/maxHeight: 图片最大宽高限制，0 表示不限制
 * - language: 0=跟随系统，1=简体中文，2=繁体中文，3=英语
 */
data class PickMediaArgs(
    val mimeType: Int,
    val maxSelectNum: Int,
    val maxSize: Long,
    val gridCount: Int,
    val maxWidth: Int,
    val maxHeight: Int,
    val language: Int
) {
    /** 转换为 PictureSelector 的 SelectMimeType */
    val mediaType: Int
        get() = when (mimeType) {
            1 -> SelectMimeType.TYPE_IMAGE
            2 -> SelectMimeType.TYPE_VIDEO
            else -> SelectMimeType.TYPE_ALL
        }

    /** 单选/多选模式 */
    val selectionMode: Int
        get() = if (maxSelectNum > 1) SelectModeConfig.MULTIPLE else SelectModeConfig.SINGLE

    /** maxSize=0 时使用 1GB 作为上限 */
    val effectiveMaxSize: Long
        get() = if (maxSize > 0) maxSize else MAX_SIZE_UNLIMITED

    /** gridCount≤0 时使用默认 4 */
    val effectiveGridCount: Int
        get() = if (gridCount > 0) gridCount else DEFAULT_GRID_COUNT

    companion object {
        private const val MAX_SIZE_UNLIMITED = 1024L * 1024 * 1024  // 1GB
        private const val DEFAULT_GRID_COUNT = 4

        /** 从 MethodChannel 调用参数 Map 解析 */
        fun from(callArgs: Map<*, *>?): PickMediaArgs {
            val args = callArgs ?: emptyMap<Any, Any>()
            val maxSize = (args["maxSize"] as? Number)?.toLong() ?: 0L
            return PickMediaArgs(
                mimeType = args["mimeType"] as? Int ?: 0,
                maxSelectNum = args["maxSelectNum"] as? Int ?: 1,
                maxSize = maxSize,
                gridCount = args["gridCount"] as? Int ?: 4,
                maxWidth = args["maxWidth"] as? Int ?: 0,
                maxHeight = args["maxHeight"] as? Int ?: 0,
                language = args["language"] as? Int ?: 0
            )
        }
    }
}
