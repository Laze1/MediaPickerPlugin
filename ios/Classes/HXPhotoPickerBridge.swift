// MARK: - HXPhotoPickerBridge
//
// 将 HXPhotoPicker 与 Flutter 桥接：弹出相册选择器，将用户选中的图片/视频导出为本地文件，
// 并组装成与 Android PictureSelector 一致的 JSON 结构，通过 Method Channel 返回给 Flutter。
// 字段与 MediaEntity.fromMap 一一对应，保证双端数据结构统一。
//
// 图片处理规则（仅图片，视频不处理）：
// - 未选原图：对图片进行压缩（JPEG 质量 0.6，长边最大 1280），path=原图路径，compressPath=压缩图路径，compressed=true。
// - 选原图且分辨率 > 1000 万像素：缩小到 ≤1000 万像素后写入临时文件，path=缩小后路径，compressPath=""，compressed=false。
// - 选原图且分辨率 ≤ 1000 万：不处理，path=导出路径，compressPath=""，compressed=false。

import Flutter
import UIKit
import Photos
import AVFoundation
import UniformTypeIdentifiers
import MobileCoreServices
import HXPhotoPicker

/// HXPhotoPicker 与 Flutter 的桥接类：负责弹出选择器、导出资源、组装 JSON 并回调 result。
final class HXPhotoPickerBridge: NSObject {
    /// 保存 Flutter 端传入的 result 闭包，在用户完成选择或取消后调用一次并置空。
    private var flutterResult: FlutterResult?
    /// 最大文件大小（字节），用于过滤超出大小的资源；0 表示不限制，此处会转为 1GB。
    private var maxSizeBytes: Int = 0
    /// 当前选择的媒体类型：0=图片+视频，1=仅图片，2=仅视频
    private var currentMimeType: Int = 0
    /// 图片最大宽度限制，0 表示不限制
    private var maxWidthForImage: Int = 0
    /// 图片最大高度限制，0 表示不限制
    private var maxHeightForImage: Int = 0
    /// Loading 遮罩视图，添加到 key window 的 rootViewController.view 上
    private weak var loadingOverlay: UIView?

    /// 入口：打开媒体选择器。
    /// - Parameters:
    ///   - mimeType: 0=图片+视频，1=仅图片，2=仅视频。
    ///   - maxSelectNum: 最大可选数量。
    ///   - maxSize: 最大文件大小（字节），0 表示不限制。
    ///   - gridCount: 选择器每排（每行）显示数量，默认 4。
    ///   - maxWidth: 图片最大宽度限制，0 表示不限制。
    ///   - maxHeight: 图片最大高度限制，0 表示不限制。
    ///   - result: Flutter 回调，成功时传入 JSON 数组字符串，取消传 "[]"，失败传 FlutterError。
    /// Flutter 入口方法：确保在主线程展示系统 UI。
    /// HXPhotoPicker 依赖 UIKit，必须在主线程调用。
    func pickMedia(mimeType: Int, maxSelectNum: Int, maxSize: Int, gridCount: Int, maxWidth: Int = 0, maxHeight: Int = 0, result: @escaping FlutterResult) {
        DispatchQueue.main.async { [weak self] in
            self?.performPick(mimeType: mimeType, maxSelectNum: maxSelectNum, maxSize: maxSize, gridCount: gridCount, maxWidth: maxWidth, maxHeight: maxHeight, result: result)
        }
    }

    /// 真实的选择器初始化与弹出逻辑。
    /// 这里做三件事：
    /// 1) 兜底参数与并发保护
    /// 2) 组装 HXPhotoPicker 配置
    /// 3) 绑定完成/取消回调
    private func performPick(mimeType: Int, maxSelectNum: Int, maxSize: Int, gridCount: Int, maxWidth: Int = 0, maxHeight: Int = 0, result: @escaping FlutterResult) {
        if flutterResult != nil {
            result(FlutterError(code: "PICK_IN_PROGRESS", message: "Another pickMedia call is in progress", details: nil))
            return
        }

        flutterResult = result
        currentMimeType = mimeType
        maxWidthForImage = maxWidth
        maxHeightForImage = maxHeight
        // maxSize=0 表示不限制，这里约定为 1GB 以便与 Android 行为一致
        maxSizeBytes = maxSize > 0 ? maxSize : 1024 * 1024 * 1024

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

        // 弹出选择器：成功回调走资源导出/组装，取消回调直接返回空数组
        Photo.picker(config) { [weak self] result, pickerController in
            self?.pickerController(pickerController, didFinishSelection: result)
        } cancel: { [weak self] pickerController in
            self?.pickerController(didCancel: pickerController)
        }
    }

    /// 选择完成之后调用
    /// - Parameters:
    ///   - pickerController: 对应的 PhotoPickerController
    ///   - result: 选择的结果
    ///     result.photoAssets  选择的资源数组
    ///     result.isOriginal   是否选中原图
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
                    // 图片处理放后台队列，避免阻塞主线程，保证 loading 正常转动
                    group.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        defer { group.leave() }
                        guard let processed = self.processPhotoImage(sourceURL: url, isOriginal: isOriginal) else {
                            return
                        }
                        let mimeType = self.mimeType(for: URL(fileURLWithPath: processed.deliveryPath), mediaType: mediaType)
                        let fileName = (processed.deliveryPath as NSString).lastPathComponent
                        let map: [String: Any] = [
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
                            "mimeType": mimeType,
                            "compressed": processed.compressed,
                            "isOriginal": isOriginal,
                            "fileName": fileName
                        ]
                        syncQueue.async {
                            if index < items.count { items[index] = map }
                        }
                    }
                    return
                }

                // 视频：不做压缩/降分辨率，仅导出路径与缩略图
                group.enter()
                let path = url.path
                let mimeType = self.mimeType(for: url, mediaType: mediaType)
                let fileName = url.lastPathComponent
                let (width, height) = self.mediaDimensions(for: url, mediaType: mediaType)
                let duration = self.videoDuration(for: url)
                let videoThumbPath = self.createVideoThumbnail(for: url) ?? ""
                let map: [String: Any] = [
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
                    "videoThumbnailPath": videoThumbPath,
                    "sandboxPath": path,
                    "duration": duration,
                    "isCut": false,
                    "mimeType": mimeType,
                    "compressed": false,
                    "isOriginal": result.isOriginal,
                    "fileName": fileName
                ]
                syncQueue.async {
                    if index < items.count { items[index] = map }
                    group.leave()
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
    
    /// 点击取消时调用
    /// - Parameter pickerController: 对应的 PhotoPickerController
    func pickerController(didCancel pickerController: PhotoPickerController) {
        finishWithItems([])
    }

    /// 将 Flutter 的 mimeType 数字映射为 HXPhotoPicker 的 PickerAssetOptions。
    private static func selectOptions(from mimeType: Int) -> PickerAssetOptions {
        switch mimeType {
        case 1: return .photo
        case 2: return .video
        default: return [.photo, .video]
        }
    }

    /// 将当前选择模式转成具体的媒体类型过滤规则。
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

    /// 将数组序列化为 JSON 字符串并回调 Flutter。
    /// 注意：该方法只允许调用一次（调用后会清空 flutterResult）。
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

    /// 获取本地文件大小（字节）。非 fileURL 直接返回 0。
    private func fileSize(at url: URL) -> Int {
        guard url.isFileURL else { return 0 }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int ?? 0
        } catch {
            return 0
        }
    }

    /// 由文件扩展名推导 MIMEType；若无法识别则按媒体类型给默认值。
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

    // MARK: - 图片处理（与 Android Luban Engine.computeSize 逻辑一致）

    private static let maxPixelsOriginal: Int = 10_000_000  // 1000 万像素
    private static let compressQuality: CGFloat = 0.6       // 与 Luban JPEG 质量 60 一致

    /// 与 Luban Engine.computeSize() 一致的采样倍数：1=不缩小，2=宽高各减半，4=1/4，或按 1280 基准
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

    /// 根据是否原图对图片做压缩或降分辨率，写入临时文件并返回路径与尺寸信息。
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

    /// 在处理/缩放期间显示 loading，与 Android 一致：透明背景，仅居中 loading 指示器，无边框
    /// 添加到当前 key window 上，不新建 UIWindow。需在主线程同步调用，确保在 getURLs 前立即显示
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

    private func hideLoadingOverlay() {
        DispatchQueue.main.async { [weak self] in
            self?.loadingOverlay?.removeFromSuperview()
            self?.loadingOverlay = nil
        }
    }

    private func resizeImage(_ image: UIImage, targetWidth: Int, targetHeight: Int) -> UIImage? {
        let width = targetWidth
        let height = targetHeight
        let size = CGSize(width: width, height: height)
        UIGraphicsBeginImageContextWithOptions(size, false, 1)
        defer { UIGraphicsEndImageContext() }
        image.draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext()
    }

    /// 当设置了 maxWidth/maxHeight 且交付图超限时，缩放到限制以内
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
