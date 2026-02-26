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

    /// 入口：打开媒体选择器。
    /// - Parameters:
    ///   - mimeType: 0=图片+视频，1=仅图片，2=仅视频。
    ///   - maxSelectNum: 最大可选数量。
    ///   - maxSize: 最大文件大小（字节），0 表示不限制。
    ///   - gridCount: 选择器每排（每行）显示数量，默认 4。
    ///   - result: Flutter 回调，成功时传入 JSON 数组字符串，取消传 "[]"，失败传 FlutterError。
    /// Flutter 入口方法：确保在主线程展示系统 UI。
    /// HXPhotoPicker 依赖 UIKit，必须在主线程调用。
    func pickMedia(mimeType: Int, maxSelectNum: Int, maxSize: Int, gridCount: Int, result: @escaping FlutterResult) {
        DispatchQueue.main.async { [weak self] in
            self?.performPick(mimeType: mimeType, maxSelectNum: maxSelectNum, maxSize: maxSize, gridCount: gridCount, result: result)
        }
    }

    /// 真实的选择器初始化与弹出逻辑。
    /// 这里做三件事：
    /// 1) 兜底参数与并发保护
    /// 2) 组装 HXPhotoPicker 配置
    /// 3) 绑定完成/取消回调
    private func performPick(mimeType: Int, maxSelectNum: Int, maxSize: Int, gridCount: Int, result: @escaping FlutterResult) {
        if flutterResult != nil {
            result(FlutterError(code: "PICK_IN_PROGRESS", message: "Another pickMedia call is in progress", details: nil))
            return
        }

        flutterResult = result
        currentMimeType = mimeType
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

        // isOriginal 表示是否选择原图（与 Android isOriginal 字段对齐）
        let isOriginal = result.isOriginal
        // HXPhotoPicker 的 URL 导出是异步回调形式，这里用串行队列收集结果，避免并发写数组
        let syncQueue = DispatchQueue(label: "tbchat_media_picker.hxphoto.result")
        var items = Array(repeating: [String: Any](), count: assets.count)

        // 通过 URL 导出资源，保证可读文件路径与尺寸/时长等信息可计算
        result.getURLs(
            options: .any,
            toFileConfigHandler: nil,
            urlReceivedHandler: { [weak self] (urlResult, photoAsset, index) in
            guard let self else { return }
            switch urlResult {
            case .success(let assetURLResult):
                let mediaType = assetURLResult.mediaType
                // 再次按 mimeType 过滤（双保险）
                if !self.isAllowed(mediaType: mediaType) {
                    return
                }

                let url = assetURLResult.url
                let size = self.fileSize(at: url)
                // 过滤掉超过 maxSize 的资源
                if self.maxSizeBytes > 0 && size > self.maxSizeBytes {
                    return
                }

                if mediaType == .photo {
                    // 图片：按是否原图做压缩或降分辨率
                    let isOriginal = result.isOriginal
                    guard let processed = self.processPhotoImage(sourceURL: url, isOriginal: isOriginal) else {
                        return
                    }
                    let mimeType = self.mimeType(for: URL(fileURLWithPath: processed.deliveryPath), mediaType: mediaType)
                    let fileName = (processed.deliveryPath as NSString).lastPathComponent
                    // path：与 Android 一致，非原图时为原图路径，原图>10MP 时为缩小后路径；sandboxPath 为实际使用的文件路径
                    let map: [String: Any] = [
                        "id": index + 1,
                        "path": processed.pathField,
                        "compressPath": processed.compressPath,
                        "cutPath": "",
                        "watermarkPath": "",
                        "videoThumbnailPath": "",
                        "sandboxPath": processed.deliveryPath,
                        "duration": 0,
                        "isCut": false,
                        "mimeType": mimeType,
                        "compressed": processed.compressed,
                        "width": processed.width,
                        "height": processed.height,
                        "cropImageWidth": 0,
                        "cropImageHeight": 0,
                        "cropOffsetX": 0,
                        "cropOffsetY": 0,
                        "cropResultAspectRatio": 0.0,
                        "size": processed.size,
                        "isOriginal": isOriginal,
                        "fileName": fileName
                    ]
                    syncQueue.async {
                        if index < items.count {
                            items[index] = map
                        }
                    }
                    return
                }

                // 视频：不做压缩/降分辨率，仅导出路径与缩略图
                let path = url.path
                let mimeType = self.mimeType(for: url, mediaType: mediaType)
                let fileName = url.lastPathComponent
                let (width, height) = self.mediaDimensions(for: url, mediaType: mediaType)
                let duration = self.videoDuration(for: url)
                let videoThumbPath = self.createVideoThumbnail(for: url) ?? ""

                let map: [String: Any] = [
                    "id": index + 1,
                    "path": path,
                    "compressPath": "",
                    "cutPath": "",
                    "watermarkPath": "",
                    "videoThumbnailPath": videoThumbPath,
                    "sandboxPath": path,
                    "duration": duration,
                    "isCut": false,
                    "mimeType": mimeType,
                    "compressed": false,
                    "width": width,
                    "height": height,
                    "cropImageWidth": 0,
                    "cropImageHeight": 0,
                    "cropOffsetX": 0,
                    "cropOffsetY": 0,
                    "cropResultAspectRatio": 0.0,
                    "size": size,
                    "isOriginal": result.isOriginal,
                    "fileName": fileName
                ]

                syncQueue.async {
                    if index < items.count {
                        items[index] = map
                    }
                }
            case .failure:
                break
            }
        },
            completionHandler: { [weak self] _ in
            guard let self else { return }
            // 回调触发后，统一在主线程返回结果
            syncQueue.async {
                let filtered = items.filter { !$0.isEmpty }
                DispatchQueue.main.async {
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
        /// 与 Android 一致：非原图时为原图路径，原图且>10MP 时为缩小后路径，否则为原图路径
        var pathField: String
        /// 实际使用的文件路径（压缩图或缩小图或原图）
        var deliveryPath: String
        /// 压缩图路径，仅当未选原图时有值
        var compressPath: String
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
                return ProcessedPhoto(pathField: pathForOriginal, deliveryPath: pathForOriginal, compressPath: "", width: srcW, height: srcH, size: fileSize(at: sourceURL), compressed: false)
            }
            let compressFileName = "hx_compressed_\(UUID().uuidString).jpg"
            let compressFileURL = FileManager.default.temporaryDirectory.appendingPathComponent(compressFileName)
            do {
                try data.write(to: compressFileURL, options: .atomic)
                let size = fileSize(at: compressFileURL)
                let w = Int(imageToCompress.size.width * imageToCompress.scale)
                let h = Int(imageToCompress.size.height * imageToCompress.scale)
                return ProcessedPhoto(
                    pathField: pathForOriginal,
                    deliveryPath: compressFileURL.path,
                    compressPath: compressFileURL.path,
                    width: w,
                    height: h,
                    size: size,
                    compressed: true
                )
            } catch {
                return ProcessedPhoto(pathField: pathForOriginal, deliveryPath: pathForOriginal, compressPath: "", width: srcW, height: srcH, size: fileSize(at: sourceURL), compressed: false)
            }
        }

        if pixelCount <= Self.maxPixelsOriginal {
            // 选原图且 ≤1000 万像素：不处理
            return ProcessedPhoto(
                pathField: originalPath,
                deliveryPath: originalPath,
                compressPath: "",
                width: srcW,
                height: srcH,
                size: fileSize(at: sourceURL),
                compressed: false
            )
        }

        // 选原图且 >1000 万像素：缩小到 ≤1000 万像素
        let scale = sqrt(CGFloat(Self.maxPixelsOriginal) / CGFloat(pixelCount))
        let newW = max(1, Int(CGFloat(srcW) * scale))
        let newH = max(1, Int(CGFloat(srcH) * scale))
        guard let resized = resizeImage(image, targetWidth: newW, targetHeight: newH),
              let data = resized.jpegData(compressionQuality: 0.9) else {
            return ProcessedPhoto(pathField: originalPath, deliveryPath: originalPath, compressPath: "", width: srcW, height: srcH, size: fileSize(at: sourceURL), compressed: false)
        }
        let fileName = "hx_resized_\(UUID().uuidString).jpg"
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: fileURL, options: .atomic)
            let size = fileSize(at: fileURL)
            return ProcessedPhoto(
                pathField: fileURL.path,
                deliveryPath: fileURL.path,
                compressPath: "",
                width: newW,
                height: newH,
                size: size,
                compressed: false
            )
        } catch {
            return ProcessedPhoto(pathField: originalPath, deliveryPath: originalPath, compressPath: "", width: srcW, height: srcH, size: fileSize(at: sourceURL), compressed: false)
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
}
