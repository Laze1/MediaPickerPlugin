// MARK: - HXPhotoPickerBridge
//
// 将 HXPhotoPicker 与 Flutter 桥接：弹出相册选择器，将用户选中的图片/视频导出为本地文件，
// 并组装成与 Android PictureSelector 一致的 JSON 结构，通过 Method Channel 返回给 Flutter。
// 字段与 MediaEntity.fromMap 一一对应，保证双端数据结构统一。

import Flutter
import UIKit
import Photos
import AVFoundation
import HXPhotoPicker

/// HXPhotoPicker 与 Flutter 的桥接类：负责弹出选择器、导出资源、组装 JSON 并回调 result。
final class HXPhotoPickerBridge: NSObject {
    /// 保存 Flutter 端传入的 result 闭包，在用户完成选择或取消后调用一次并置空。
    private var flutterResult: FlutterResult?
    /// 最大文件大小（字节），用于过滤超出大小的资源；0 表示不限制，此处会转为 1GB。
    private var maxSizeBytes: Int = 0

    /// 入口：打开媒体选择器。
    /// - Parameters:
    ///   - mimeType: 0=图片+视频，1=仅图片，2=仅视频。
    ///   - maxSelectNum: 最大可选数量。
    ///   - maxSize: 最大文件大小（字节），0 表示不限制。
    ///   - result: Flutter 回调，成功时传入 JSON 数组字符串，取消传 "[]"，失败传 FlutterError。
    func pickMedia(mimeType: Int, maxSelectNum: Int, maxSize: Int, result: @escaping FlutterResult) {
        DispatchQueue.main.async { [weak self] in
            self?.performPick(mimeType: mimeType, maxSelectNum: maxSelectNum, maxSize: maxSize, result: result)
        }
    }

    func presentPickerController() {
        // 设置与微信主题一致的配置
        let config = PickerConfiguration.default
        Photo.picker(
            config
        ) { result, pickerController in
            // 选择完成的回调
            // result 选择结果
            // photoPickerController 对应的照片选择控制器
            self.pickerController(pickerController, didFinishSelection: result)
        } cancel: { pickerController in
            // 取消的回调
            // photoPickerController 对应的照片选择控制器 
            self.pickerController(didCancel: pickerController)
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
        // async/await
        let images: [UIImage] = try await result.objects()
        let urls: [URL] = try await result.objects()
        let urlResults: [AssetURLResult] = try await result.objects()
        let assetResults: [AssetResult] = try await result.objects()
        
        result.getImage { (image, photoAsset, index) in
            if let image = image {
                print("success", image)
            }else {
                print("failed")
            }
        } completionHandler: { (images) in
            print(images)
        }
    }
    
    /// 点击取消时调用
    /// - Parameter pickerController: 对应的 PhotoPickerController
    func pickerController(didCancel pickerController: PhotoPickerController) {
        
    }

    /// 将 Flutter 的 mimeType 数字映射为 HXPhotoPicker 的 PickerAssetOptions。
    private static func selectOptions(from mimeType: Int) -> PickerAssetOptions {
        switch mimeType {
        case 1: return .photo
        case 2: return .video
        default: return [.photo, .video]
        }
    }

}
