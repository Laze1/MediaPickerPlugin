// MARK: - HXPhotoPickerBridge
//
// 将 HXPhotoPicker 与 Flutter 桥接：弹出相册选择器，导出选中资源并组装 JSON，
// 字段与 Dart 端 MediaEntity.fromMap 一一对应，保证双端数据结构统一。
//
// ## 图片处理规则
// - 未选原图：JPEG 质量 0.6 压缩，长边最大 1280，与 Luban 逻辑一致
// - 选原图且 >1000 万像素：缩放到 ≤1000 万，写入临时文件
// - 选原图且 ≤1000 万：不处理，直接使用原图

import Flutter
import UIKit
import Photos
import AVFoundation
import UniformTypeIdentifiers
import MobileCoreServices
import HXPhotoPicker

/// HXPhotoPicker 与 Flutter 的桥接类：负责弹出选择器、导出资源、组装 JSON 并回调 result。
final class HXPhotoPickerBridge: NSObject {

    // MARK: - State

    /// Flutter 回调，选择完成或取消后调用一次并置空
    private var flutterResult: FlutterResult?
    /// 最大文件大小（字节），用于过滤超出大小的资源；0 表示不限制，转为 1GB
    private var maxSizeBytes: Int = 0
    /// 当前媒体类型：0=图片+视频，1=仅图片，2=仅视频
    private var currentMimeType: Int = 0
    /// 图片最大宽度限制，0 表示不限制
    private var maxWidthForImage: Int = 0
    /// 图片最大高度限制，0 表示不限制
    private var maxHeightForImage: Int = 0
    /// Loading 遮罩视图，添加到 key window
    private weak var loadingOverlay: UIView?

    // MARK: - Constants

    private static let maxSizeUnlimited = 1024 * 1024 * 1024   // 1GB
    private static let maxPixelsOriginal = 10_000_000          // 1000 万像素
    private static let compressQuality: CGFloat = 0.6          // 与 Luban JPEG 质量 60 一致

    // MARK: - Public Entry

    /// 入口：打开媒体选择器。
    /// - Parameters:
    ///   - mimeType: 0=图片+视频，1=仅图片，2=仅视频。
    ///   - maxSelectNum: 最大可选数量。
    ///   - maxSize: 最大文件大小（字节），0 表示不限制。
    ///   - gridCount: 选择器每排（每行）显示数量，默认 4。
    ///   - maxWidth: 图片最大宽度限制，0 表示不限制。
    ///   - maxHeight: 图片最大高度限制，0 表示不限制。
    ///   - language: 0=跟随系统，1=简体中文，2=繁体中文，3=英语。
    ///   - result: Flutter 回调，成功时传入 JSON 数组字符串，取消传 "[]"，失败传 FlutterError。
    func pickMedia(mimeType: Int, maxSelectNum: Int, maxSize: Int, gridCount: Int, maxWidth: Int = 0, maxHeight: Int = 0, language: Int = 0, result: @escaping FlutterResult) {
        DispatchQueue.main.async { [weak self] in
            self?.performPick(mimeType: mimeType, maxSelectNum: maxSelectNum, maxSize: maxSize, gridCount: gridCount, maxWidth: maxWidth, maxHeight: maxHeight, language: language, result: result)
        }
    }

    // MARK: - Picker Lifecycle

    /// 选择器初始化与弹出：参数校验、并发保护、配置 HXPhotoPicker、绑定回调
    private func performPick(mimeType: Int, maxSelectNum: Int, maxSize: Int, gridCount: Int, maxWidth: Int = 0, maxHeight: Int = 0, language: Int = 0, result: @escaping FlutterResult) {
        if flutterResult != nil {
            result(FlutterError(code: "PICK_IN_PROGRESS", message: "Another pickMedia call is in progress", details: nil))
            return
        }

        flutterResult = result
        currentMimeType = mimeType
        maxWidthForImage = maxWidth
        maxHeightForImage = maxHeight
        maxSizeBytes = maxSize > 0 ? maxSize : Self.maxSizeUnlimited

        // HXPhotoPicker 基础配置：选择模式、可选资源类型与数量限制
        var config = PickerConfiguration.default
        config.selectOptions = HXPhotoPickerBridge.selectOptions(from: mimeType)
        config.selectMode = maxSelectNum > 1 ? .multiple : .single
        config.maximumSelectedCount = maxSelectNum
        config.maximumSelectedPhotoCount = maxSelectNum
        config.maximumSelectedVideoCount = maxSelectNum
        config.allowSelectedTogether = (mimeType == 0)

        // 每排显示数量：photoList.rowNumber 为每行个数，限制在 2~8 之间
        let count = min(8, max(2, gridCount))
        config.photoList.rowNumber = count
        config.photoList.landscapeRowNumber = max(count, 7) // 横屏可略多

        // 相册内不展示拍照按钮（仅从相册选择）
        config.photoList.allowAddCamera = false

        // 语言设置：0=跟随系统，1=简体中文，2=繁体中文，3=英语
        config.languageType = HXPhotoPickerBridge.languageType(from: language)

        // 弹出选择器：成功回调走资源导出/组装，取消回调直接返回空数组
        Photo.picker(config) { [weak self] result, pickerController in
            self?.pickerController(pickerController, didFinishSelection: result)
        } cancel: { [weak self] pickerController in
            self?.pickerController(didCancel: pickerController)
        }
    }

    /// 选择完成：显示 loading → getURLs 导出资源 → 后台处理图片 → 过滤空项 → 回调 Flutter
    func pickerController(
        _ pickerController: PhotoPickerController, 
        didFinishSelection result: PickerResult
    ) {
        // HXPhotoPicker 已将用户选择封装在 result.photoAssets
        let assets = result.photoAssets
        if assets.isEmpty {
            finishWithItems([])
            return
        }

        // 缩放/处理期间显示 loading（与 Android 一致：仅居中 loading，无边框）
        // 需在 getURLs 前同步显示，覆盖整个处理期间；图片处理放后台以保证 loading 正常转动
        if Thread.isMainThread {
            showLoadingOverlay(in: pickerController)
        } else {
            DispatchQueue.main.sync { showLoadingOverlay(in: pickerController) }
        }

        let isOriginal = result.isOriginal
        let syncQueue = DispatchQueue(label: "tbchat_media_picker.hxphoto.result")
        var items = Array(repeating: [String: Any](), count: assets.count)
        let group = DispatchGroup()

        result.getURLs(
            options: .any,
            toFileConfigHandler: nil,
            urlReceivedHandler: { [weak self] (urlResult, photoAsset, index) in
            guard let self else { return }
            switch urlResult {
            case .success(let assetURLResult):
                let mediaType = assetURLResult.mediaType
                if !self.isAllowed(mediaType: mediaType) {
                    return
                }
                let url = assetURLResult.url
                let size = self.fileSize(at: url)
                if self.maxSizeBytes > 0 && size > self.maxSizeBytes {
                    return
                }

                if mediaType == .photo {
                    handlePhotoAsset(url: url, index: index, isOriginal: isOriginal, group: group, syncQueue: syncQueue) { i, m in
                        if i < items.count { items[i] = m }
                    }
                    return
                }
                handleVideoAsset(url: url, index: index, size: size, isOriginal: result.isOriginal, group: group, syncQueue: syncQueue) { i, m in
                    if i < items.count { items[i] = m }
                }
            case .failure:
                break
            }
        },
            completionHandler: { [weak self] _ in
            guard let self else { return }
            // 等待所有图片/视频处理完成后再隐藏 loading 并回调 Flutter
            group.notify(queue: syncQueue) {
                let filtered = items.filter { !$0.isEmpty }
                DispatchQueue.main.async {
                    self.hideLoadingOverlay()
                    self.finishWithItems(filtered)
                }
            }
        }
        )
    }
    
    /// 用户取消选择：直接返回空数组 "[]"
    func pickerController(didCancel pickerController: PhotoPickerController) {
        finishWithItems([])
    }

    // MARK: - Media Handlers

    /// 处理图片资源：后台线程压缩/缩放，通过 writeItem 写入 items
    private func handlePhotoAsset(url: URL, index: Int, isOriginal: Bool, group: DispatchGroup, syncQueue: DispatchQueue, writeItem: @escaping (Int, [String: Any]) -> Void) {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer { group.leave() }
            guard let self else { return }
            guard let processed = self.processPhotoImage(sourceURL: url, isOriginal: isOriginal) else { return }
            let map = self.buildPhotoMediaMap(processed: processed, index: index, isOriginal: isOriginal)
            syncQueue.async { writeItem(index, map) }
        }
    }

    /// 处理视频资源：不压缩，仅导出路径、尺寸、时长、缩略图
    private func handleVideoAsset(url: URL, index: Int, size: Int, isOriginal: Bool, group: DispatchGroup, syncQueue: DispatchQueue, writeItem: @escaping (Int, [String: Any]) -> Void) {
        group.enter()
        let path = url.path
        let mimeStr = mimeType(for: url, mediaType: .video)
        let fileName = url.lastPathComponent
        let (width, height) = mediaDimensions(for: url, mediaType: .video)
        let duration = videoDuration(for: url)
        let videoThumbPath = createVideoThumbnail(for: url) ?? ""
        let map = buildVideoMediaMap(path: path, size: size, width: width, height: height, duration: duration, videoThumbnailPath: videoThumbPath, mimeType: mimeStr, fileName: fileName, index: index, isOriginal: isOriginal)
        syncQueue.async {
            writeItem(index, map)
            group.leave()
        }
    }

    /// 构建图片 MediaEntity map，字段与 Dart MediaEntity.fromMap 对应
    private func buildPhotoMediaMap(processed: ProcessedPhoto, index: Int, isOriginal: Bool) -> [String: Any] {
        let mime = mimeType(for: URL(fileURLWithPath: processed.deliveryPath), mediaType: .photo)
        let fileName = (processed.deliveryPath as NSString).lastPathComponent
        return [
            "id": index + 1,
            "originalPath": processed.originalPath,
            "originalSize": processed.originalSize,
            "originalWidth": processed.originalWidth,
            "originalHeight": processed.originalHeight,
            "path": processed.deliveryPath,
            "size": processed.size,
            "width": processed.width,
            "height": processed.height,
            "cutPath": "",
            "watermarkPath": "",
            "videoThumbnailPath": "",
            "sandboxPath": processed.deliveryPath,
            "duration": 0,
            "isCut": false,
            "mimeType": mime,
            "compressed": processed.compressed,
            "isOriginal": isOriginal,
            "fileName": fileName
        ]
    }

    /// 构建视频 MediaEntity map，字段与 Dart MediaEntity.fromMap 对应
    private func buildVideoMediaMap(path: String, size: Int, width: Int, height: Int, duration: Int, videoThumbnailPath: String, mimeType: String, fileName: String, index: Int, isOriginal: Bool) -> [String: Any] {
        [
            "id": index + 1,
            "originalPath": path,
            "originalSize": size,
            "originalWidth": width,
            "originalHeight": height,
            "path": path,
            "size": size,
            "width": width,
            "height": height,
            "cutPath": "",
            "watermarkPath": "",
            "videoThumbnailPath": videoThumbnailPath,
            "sandboxPath": path,
            "duration": duration,
            "isCut": false,
            "mimeType": mimeType,
            "compressed": false,
            "isOriginal": isOriginal,
            "fileName": fileName
        ]
    }

    // MARK: - Config Helpers

    /// Flutter language 参数映射为 HXPhotoPicker LanguageType：0=系统，1=简体，2=繁体，3=英语
    private static func languageType(from language: Int) -> LanguageType {
        switch language {
        case 1: return .simplifiedChinese
        case 2: return .traditionalChinese
        case 3: return .english
        default: return .system
        }
    }

    /// Flutter mimeType 映射为 HXPhotoPicker PickerAssetOptions：0=全部，1=仅图片，2=仅视频
    private static func selectOptions(from mimeType: Int) -> PickerAssetOptions {
        switch mimeType {
        case 1: return .photo
        case 2: return .video
        default: return [.photo, .video]
        }
    }

    /// 根据 currentMimeType 过滤媒体类型：1=仅图片，2=仅视频，0=全部
    private func isAllowed(mediaType: PhotoAsset.MediaType) -> Bool {
        switch currentMimeType {
        case 1:
            return mediaType == .photo
        case 2:
            return mediaType == .video
        default:
            return true
        }
    }

    // MARK: - Result & Utils

    /// 将 items 序列化为 JSON 字符串并回调 Flutter；调用后清空 flutterResult 防止重复回调
    private func finishWithItems(_ items: [[String: Any]]) {
        guard let flutterResult else { return }
        self.flutterResult = nil
        do {
            let data = try JSONSerialization.data(withJSONObject: items, options: [])
            let json = String(data: data, encoding: .utf8) ?? "[]"
            flutterResult(json)
        } catch {
            flutterResult(FlutterError(code: "RESULT_ERROR", message: "Failed to encode result: \(error.localizedDescription)", details: nil))
        }
    }

    /// 获取本地文件大小（字节）；非 fileURL 返回 0
    private func fileSize(at url: URL) -> Int {
        guard url.isFileURL else { return 0 }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int ?? 0
        } catch {
            return 0
        }
    }

    /// 由文件扩展名推导 MIME 类型；无法识别时按 mediaType 给默认 image/jpeg 或 video/mp4
    private func mimeType(for url: URL, mediaType: PhotoAsset.MediaType) -> String {
        let ext = url.pathExtension.lowercased()
        if !ext.isEmpty {
            if #available(iOS 14.0, *) {
                if let type = UTType(filenameExtension: ext), let mime = type.preferredMIMEType {
                    return mime
                }
            } else {
                if let uti = UTTypeCreatePreferredIdentifierForTag(
                    kUTTagClassFilenameExtension,
                    ext as CFString,
                    nil
                )?.takeRetainedValue(),
                let mime = UTTypeCopyPreferredTagWithClass(
                    uti,
                    kUTTagClassMIMEType
                )?.takeRetainedValue() {
                    return mime as String
                }
            }
        }
        switch mediaType {
        case .photo:
            return "image/jpeg"
        case .video:
            return "video/mp4"
        }
    }

    /// 获取媒体尺寸：图片从 UIImage，视频从 AVAsset 轨道（考虑旋转）
    private func mediaDimensions(for url: URL, mediaType: PhotoAsset.MediaType) -> (Int, Int) {
        switch mediaType {
        case .photo:
            // 图片直接读取像素尺寸
            if let image = UIImage(contentsOfFile: url.path) {
                let width = Int(image.size.width * image.scale)
                let height = Int(image.size.height * image.scale)
                return (width, height)
            }
            return (0, 0)
        case .video:
            // 视频从轨道中获取尺寸，并考虑旋转矩阵
            let asset = AVAsset(url: url)
            guard let track = asset.tracks(withMediaType: .video).first else {
                return (0, 0)
            }
            let size = track.naturalSize.applying(track.preferredTransform)
            return (Int(abs(size.width)), Int(abs(size.height)))
        }
    }

    /// 获取视频时长（秒），向最近整数取整。
    private func videoDuration(for url: URL) -> Int {
        let asset = AVAsset(url: url)
        return Int(CMTimeGetSeconds(asset.duration).rounded())
    }

    /// 生成视频首帧缩略图并写入临时目录，返回缩略图路径。
    /// 失败时返回 nil，交由 Flutter 端自行处理。
    private func createVideoThumbnail(for url: URL) -> String? {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let time = CMTime(seconds: 0.1, preferredTimescale: 600)
        do {
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            let image = UIImage(cgImage: cgImage)
            guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
            let fileName = "hx_thumb_\(UUID().uuidString).jpg"
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try data.write(to: fileURL, options: .atomic)
            return fileURL.path
        } catch {
            return nil
        }
    }

    // MARK: - Image Processing (Luban-aligned)

    /// 与 Luban Engine.computeSize() 一致的采样倍数：1=不缩小，2=宽高减半，4=1/4，或按长边 1280 基准
    private func computeSampleSize(srcW: Int, srcH: Int) -> Int {
        let w = srcW % 2 == 1 ? srcW + 1 : srcW
        let h = srcH % 2 == 1 ? srcH + 1 : srcH
        let longSide = max(w, h)
        let shortSide = min(w, h)
        let scale = CGFloat(shortSide) / CGFloat(longSide)

        if scale <= 1 && scale > 0.5625 {
            if longSide < 1664 { return 1 }
            if longSide < 4990 { return 2 }
            if longSide > 4990 && longSide < 10240 { return 4 }
            return longSide / 1280
        } else if scale <= 0.5625 && scale > 0.5 {
            let n = longSide / 1280
            return n == 0 ? 1 : n
        } else {
            return Int(ceil(CGFloat(longSide) / (1280.0 / scale)))
        }
    }

    /// 图片处理结果：原图路径、交付路径（压缩/缩放/原图）、尺寸信息
    private struct ProcessedPhoto {
        /// 原图路径（始终为导出源路径或复制后的原图路径）
        var originalPath: String
        /// 原图文件大小（字节）
        var originalSize: Int
        /// 原图宽高
        var originalWidth: Int
        var originalHeight: Int
        /// 交付路径（压缩图/缩放图/原图，供 path 使用）
        var deliveryPath: String
        /// 交付宽高、大小
        var width: Int
        var height: Int
        var size: Int
        var compressed: Bool
    }

    /// 根据是否原图做压缩或降分辨率：未选原图→Luban 逻辑压缩；选原图且>1000万像素→缩放；否则不处理
    private func processPhotoImage(sourceURL: URL, isOriginal: Bool) -> ProcessedPhoto? {
        guard let image = UIImage(contentsOfFile: sourceURL.path) else { return nil }
        let srcW = Int(image.size.width * image.scale)
        let srcH = Int(image.size.height * image.scale)
        let pixelCount = srcW * srcH
        let originalPath = sourceURL.path

        if !isOriginal {
            // 未选原图：先复制原图到持久位置（path 返回原图路径），再压缩（compressPath 返回压缩路径）
            let ext = sourceURL.pathExtension.isEmpty ? "jpg" : sourceURL.pathExtension
            let originalFileName = "hx_original_\(UUID().uuidString).\(ext)"
            let originalFileURL = FileManager.default.temporaryDirectory.appendingPathComponent(originalFileName)
            let pathForOriginal: String
            do {
                try FileManager.default.copyItem(at: sourceURL, to: originalFileURL)
                pathForOriginal = originalFileURL.path
            } catch {
                pathForOriginal = originalPath
            }

            // 使用与 Luban 一致的 computeSampleSize 逻辑压缩
            let sampleSize = computeSampleSize(srcW: srcW, srcH: srcH)
            let newW = max(1, srcW / sampleSize)
            let newH = max(1, srcH / sampleSize)
            let imageToCompress: UIImage
            if sampleSize > 1, let resized = resizeImage(image, targetWidth: newW, targetHeight: newH) {
                imageToCompress = resized
            } else {
                imageToCompress = image
            }
            guard let data = imageToCompress.jpegData(compressionQuality: Self.compressQuality) else {
                let origSize = fileSize(at: sourceURL)
                return applyMaxDimensions(to: ProcessedPhoto(originalPath: pathForOriginal, originalSize: origSize, originalWidth: srcW, originalHeight: srcH, deliveryPath: pathForOriginal, width: srcW, height: srcH, size: origSize, compressed: false))
            }
            let compressFileName = "hx_compressed_\(UUID().uuidString).jpg"
            let compressFileURL = FileManager.default.temporaryDirectory.appendingPathComponent(compressFileName)
            do {
                try data.write(to: compressFileURL, options: .atomic)
                let size = fileSize(at: compressFileURL)
                let w = Int(imageToCompress.size.width * imageToCompress.scale)
                let h = Int(imageToCompress.size.height * imageToCompress.scale)
                let origSize = fileSize(at: sourceURL)
                return applyMaxDimensions(to: ProcessedPhoto(
                    originalPath: pathForOriginal,
                    originalSize: origSize,
                    originalWidth: srcW,
                    originalHeight: srcH,
                    deliveryPath: compressFileURL.path,
                    width: w,
                    height: h,
                    size: size,
                    compressed: true
                ))
            } catch {
                let origSize = fileSize(at: sourceURL)
                return applyMaxDimensions(to: ProcessedPhoto(originalPath: pathForOriginal, originalSize: origSize, originalWidth: srcW, originalHeight: srcH, deliveryPath: pathForOriginal, width: srcW, height: srcH, size: origSize, compressed: false))
            }
        }

        if pixelCount <= Self.maxPixelsOriginal {
            // 选原图且 ≤1000 万像素：不缩放、不压缩，直接使用原图
            let origSize = fileSize(at: sourceURL)
            return applyMaxDimensions(to: ProcessedPhoto(
                originalPath: originalPath,
                originalSize: origSize,
                originalWidth: srcW,
                originalHeight: srcH,
                deliveryPath: originalPath,
                width: srcW,
                height: srcH,
                size: origSize,
                compressed: false
            ))
        }

        // 选原图且 >1000 万像素：仅像素缩放到 ≤1000 万；交付 path 为缩放后路径
        let originalSize = fileSize(at: sourceURL)
        let scale = sqrt(CGFloat(Self.maxPixelsOriginal) / CGFloat(pixelCount))
        let newW = max(1, Int(CGFloat(srcW) * scale))
        let newH = max(1, Int(CGFloat(srcH) * scale))
        guard let resized = resizeImage(image, targetWidth: newW, targetHeight: newH),
              let data = resized.jpegData(compressionQuality: 0.9) else {
            return applyMaxDimensions(to: ProcessedPhoto(originalPath: originalPath, originalSize: originalSize, originalWidth: srcW, originalHeight: srcH, deliveryPath: originalPath, width: srcW, height: srcH, size: originalSize, compressed: false))
        }
        let fileName = "hx_resized_\(UUID().uuidString).jpg"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: fileURL, options: .atomic)
            let scaledSize = fileSize(at: fileURL)
            return applyMaxDimensions(to: ProcessedPhoto(
                originalPath: originalPath,
                originalSize: originalSize,
                originalWidth: srcW,
                originalHeight: srcH,
                deliveryPath: fileURL.path,
                width: newW,
                height: newH,
                size: scaledSize,
                compressed: false
            ))
        } catch {
            return applyMaxDimensions(to: ProcessedPhoto(originalPath: originalPath, originalSize: originalSize, originalWidth: srcW, originalHeight: srcH, deliveryPath: originalPath, width: srcW, height: srcH, size: originalSize, compressed: false))
        }
    }

    // MARK: - Loading Overlay

    /// 在处理/缩放期间显示 loading：透明背景，居中 spinner
    /// 添加到 present 了 picker 的 window，需在主线程同步调用
    private func showLoadingOverlay(in pickerController: PhotoPickerController) {
        self.loadingOverlay?.removeFromSuperview()
        self.loadingOverlay = nil
        let windows = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
        // 优先用 present 了 picker 的 window（Flutter 主窗口），picker dismiss 后 overlay 仍可见
        let targetWindow = windows.first { w in
            guard let root = w.rootViewController, !w.isHidden else { return false }
            return root.presentedViewController === pickerController
        } ?? windows.first(where: { $0.isKeyWindow })
            ?? windows.first(where: { !$0.isHidden })
            ?? windows.first
        guard let window = targetWindow else { return }

        let overlay = UIView()
        overlay.backgroundColor = .clear
        overlay.translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: window.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: window.bottomAnchor),
        ])
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        overlay.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
        ])
        self.loadingOverlay = overlay
    }

    /// 隐藏 loading 遮罩，主线程安全
    private func hideLoadingOverlay() {
        DispatchQueue.main.async { [weak self] in
            self?.loadingOverlay?.removeFromSuperview()
            self?.loadingOverlay = nil
        }
    }

    /// 缩放图片到目标宽高
    private func resizeImage(_ image: UIImage, targetWidth: Int, targetHeight: Int) -> UIImage? {
        let width = targetWidth
        let height = targetHeight
        let size = CGSize(width: width, height: height)
        UIGraphicsBeginImageContextWithOptions(size, false, 1)
        defer { UIGraphicsEndImageContext() }
        image.draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }

    /// 当设置了 maxWidth/maxHeight 且交付图宽高超限时，缩放到限制以内
    private func applyMaxDimensions(to processed: ProcessedPhoto) -> ProcessedPhoto {
        guard maxWidthForImage > 0, maxHeightForImage > 0,
              processed.width > maxWidthForImage || processed.height > maxHeightForImage else {
            return processed
        }
        guard let img = UIImage(contentsOfFile: processed.deliveryPath) else { return processed }
        let scale = min(CGFloat(maxWidthForImage) / CGFloat(processed.width),
                        CGFloat(maxHeightForImage) / CGFloat(processed.height),
                        1.0)
        let newW = max(1, Int(CGFloat(processed.width) * scale))
        let newH = max(1, Int(CGFloat(processed.height) * scale))
        guard let resized = resizeImage(img, targetWidth: newW, targetHeight: newH),
              let data = resized.jpegData(compressionQuality: 0.9) else { return processed }
        let fileName = "hx_maxdim_\(UUID().uuidString).jpg"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: fileURL, options: .atomic)
            let newSize = fileSize(at: fileURL)
            return ProcessedPhoto(
                originalPath: processed.originalPath,
                originalSize: processed.originalSize,
                originalWidth: processed.originalWidth,
                originalHeight: processed.originalHeight,
                deliveryPath: fileURL.path,
                width: newW,
                height: newH,
                size: newSize,
                compressed: processed.compressed
            )
        } catch {
            return processed
        }
    }
}
