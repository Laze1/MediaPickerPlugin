package com.tbchat.tbchat_media_picker

import android.app.Activity
import android.app.Dialog
import android.graphics.Color
import android.view.Gravity
import android.widget.FrameLayout
import android.widget.ProgressBar

/**
 * Loading 弹窗工具.
 *
 * 创建透明背景、无边框、居中 ProgressBar 的 loading 弹窗，
 * 与 iOS 端 loading 样式一致，用于媒体处理（缩放/压缩）期间的提示.
 */
object LoadingHelper {

    /**
     * 创建 loading Dialog.
     * @param activity 宿主 Activity
     * @return 不可取消的透明 loading Dialog，调用方负责 show/dismiss
     */
    fun createDialog(activity: Activity): Dialog {
        return Dialog(activity, android.R.style.Theme_Translucent_NoTitleBar).apply {
            setCancelable(false)
            setContentView(FrameLayout(activity).apply {
                setBackgroundColor(Color.TRANSPARENT)
                addView(ProgressBar(activity).apply {
                    layoutParams = FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.WRAP_CONTENT,
                        FrameLayout.LayoutParams.WRAP_CONTENT,
                        Gravity.CENTER
                    )
                })
            })
        }
    }
}
