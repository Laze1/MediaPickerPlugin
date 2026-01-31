package com.tbchat.tbchat_media_picker

import android.content.Context
import android.widget.ImageView
import com.bumptech.glide.Glide
import com.bumptech.glide.load.engine.DiskCacheStrategy
import com.bumptech.glide.request.RequestOptions
import com.luck.picture.lib.engine.ImageEngine

/**
 * Glide 图片加载引擎实现
 * 用于 PictureSelector 的图片加载
 */
class GlideEngine private constructor() : ImageEngine {
    
    companion object {
        @JvmStatic
        fun createGlideEngine(): GlideEngine {
            return GlideEngine()
        }
    }

    override fun loadImage(context: Context, url: String, imageView: ImageView) {
        Glide.with(context)
            .load(url)
            .into(imageView)
    }

    override fun loadImage(context: Context, imageView: ImageView, url: String, maxWidth: Int, maxHeight: Int) {
        Glide.with(context)
            .load(url)
            .override(maxWidth, maxHeight)
            .into(imageView)
    }

    override fun loadAlbumCover(context: Context, url: String, imageView: ImageView) {
        Glide.with(context)
            .asBitmap()
            .load(url)
            .override(180, 180)
            .centerCrop()
            .sizeMultiplier(0.5f)
            .placeholder(android.R.drawable.ic_menu_report_image)
            .diskCacheStrategy(DiskCacheStrategy.ALL)
            .into(imageView)
    }

    override fun loadGridImage(context: Context, url: String, imageView: ImageView) {
        Glide.with(context)
            .load(url)
            .override(200, 200)
            .centerCrop()
            .diskCacheStrategy(DiskCacheStrategy.ALL)
            .into(imageView)
    }

    override fun pauseRequests(context: Context) {
        Glide.with(context).pauseRequests()
    }

    override fun resumeRequests(context: Context) {
        Glide.with(context).resumeRequests()
    }
}
