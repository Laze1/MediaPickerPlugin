# tbchat_media_picker

A media picker plugin project.

## Getting Started

This project is a starting point for a Flutter
[plug-in package](https://flutter.dev/to/develop-plugins),
a specialized package that includes platform-specific implementation code for
Android and/or iOS.

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## API

```
.setSelectorUIStyle(); 设置相册主题
.setLanguage(); 设置相册语言
.setImageEngine(); 设置相册图片加载引擎
.setCompressEngine(); 设置相册压缩引擎
.setCropEngine(); 设置相册裁剪引擎
.setVideoPlayerEngine(); 创建自定义播放器
.setSandboxFileEngine(); 设置相册沙盒目录拷贝引擎
.setOriginalFileEngine(); 设置相册图片原图处理引擎
.setExtendLoaderEngine(); 设置相册数据源加载引擎
.setLoaderFactoryEngine(); 设置自定义相册数据源加载器
.setCameraInterceptListener(); 拦截相机事件，实现自定义相机
.setRecordAudioInterceptListener(); 拦截录音事件，实现自定义录音组件
.setEditMediaInterceptListener(); 拦截资源编辑事件，实现自定义编辑
.setPermissionDeniedListener(); 自定义权限被拒处理回调
.setPermissionDescriptionListener(); 自定义权限描述说明
.setPermissionsInterceptListener(); 拦截相册权限处理事件，实现自定义权限
.setSelectLimitTipsListener(); 拦截选择限制事件，可实现自定义提示
.setInjectLayoutResourceListener(); 注入自定义布局回调
.setQueryFilterListener(); 自定义查询拦截条件
.setCustomLoadingListener(); 自定义loading样式
.setSelectFilterListener(); 拦截不支持的选择项
.setAttachViewLifecycle(); 监听选择器页面生命周期
.setGridItemSelectAnimListener(); 设置Item列表选中/取消动画
.setSelectAnimListener(); 设置选中Item动画
.setInjectActivityPreviewFragment(); 自定义外部预览
.setVideoThumbnailListener(); 自定义获取视频缩略图
.setAddBitmapWatermarkListener(); 自定义添加水印
.isCameraForegroundService(); 拍照时是否开启一个前台服务 
.setRequestedOrientation(); 设置屏幕旋转方向
.setSelectedData(); 相册已选数据
.setRecyclerAnimationMode(); 相册列表动画效果
.setImageSpanCount(); 相册列表每行显示个数
.isDisplayCamera(); 是否显示相机入口
.isPageStrategy(); 是否开启分页模式
.selectionMode(); 单选或是多选
.setMaxSelectNum(); 图片最大选择数量
.setMinSelectNum(); 图片最小选择数量
.setMaxVideoSelectNum(); 视频最大选择数量
.setMinVideoSelectNum(); 视频最小选择数量
.setRecordVideoMaxSecond(); 视频录制最大时长
.setRecordVideoMinSecond(); 视频录制最小时长
.setFilterVideoMaxSecond(); 过滤视频最大时长
.setFilterVideoMinSecond(); 过滤视频最小时长
.setSelectMaxDurationSecond(); 选择最大时长视频或音频
.setSelectMinDurationSecond(); 选择最小时长视频或音频
.setVideoQuality(); 系统相机录制视频质量
.isVideoPauseResumePlay(); 视频支持暂停与播放
.isQuickCapture(); 使用系统摄像机录制后，是否支持使用系统播放器立即播放视频
.isPreviewAudio(); 是否支持音频预览
.isPreviewImage(); 是否支持预览图片
.isPreviewVideo(); 是否支持预览视频
.isPreviewFullScreenMode(); 预览点击全屏效果
.isEmptyResultReturn(); 支持未选择返回
.isWithSelectVideoImage(); 是否支持视频图片同选
.isSelectZoomAnim(); 选择缩略图缩放效果
.isOpenClickSound(); 是否开启点击音效
.isCameraAroundState(); 是否开启前置摄像头；系统相机 只支持部分机型
.isCameraRotateImage(); 拍照是否纠正旋转图片
.isGif(); 是否显示gif文件
.isWebp(); 是否显示webp文件
.isBmp(); 是否显示bmp文件
.isHidePreviewDownload(); 是否隐藏预览下载功能
.isAutoScalePreviewImage(); 预览图片自动放大充满屏幕
.setOfAllCameraType(); isWithSelectVideoImage模式下相机优先使用权
.isMaxSelectEnabledMask(); 达到最大选择数是否开启禁选蒙层
.isSyncCover(); isPageModel模式下是否强制同步封面，默认false
.isAutomaticTitleRecyclerTop(); 点击相册标题是否快速回到第一项
.isAutoVideoPlay(); 预览视频是否自动播放
.isLoopAutoVideoPlay(); 预览视频是否循环播放
.isFilterSizeDuration(); 是否过滤图片或音视频大小时长为0的资源
.isFastSlidingSelect(); 快速滑动选择
.isDirectReturnSingle(); 单选时是否立即返回
.setCameraImageFormat(); 拍照图片输出格式
.setCameraImageFormatForQ(); 拍照图片输出格式，Android Q以上 
.setCameraVideoFormat(); 拍照视频输出格式
.setCameraVideoFormatForQ(); 拍照视频输出格式，Android Q以上
.setOutputCameraDir(); 使用相机输出路径
.setOutputAudioDir();使用录音输出路径
.setOutputCameraImageFileName(); 图片输出文件名
.setOutputCameraVideoFileName(); 视频输出文件名
.setOutputAudioFileName(); 录音输出文件名
.setQuerySandboxDir(); 查询指定目录下的资源
.isOnlyObtainSandboxDir(); 是否只查询指定目录下的资源
.setFilterMaxFileSize(); 过滤最大文件
.setFilterMinFileSize(); 过滤最小文件
.setSelectMaxFileSize(); 最大可选文件大小
.setSelectMinFileSize(); 最小可选文件大小
.setQueryOnlyMimeType(); 查询指定文件类型
.setSkipCropMimeType(); 跳过不需要裁剪的类型
.setMagicalEffectInterpolator(); 设置预览缩放模式插值器效果
.isPageSyncAlbumCount(); 分页模式下设置过滤条件后是否同步专辑下资源的数量
.isAllFilesAccessOf11(); Android 11下未申请权限时，进入系统设置所有权限界面
.isFilterSizeDuration(); 过滤视频小于1秒和文件小于1kb
.isUseSystemVideoPlayer(); 使用系统播放器
```