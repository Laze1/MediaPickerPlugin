import Flutter
import UIKit

/// Flutter 媒体选择插件（iOS 端）入口.
///
/// 通过 MethodChannel "tbchat_media_picker" 接收 pickMedia 调用，
/// 委托 [HXPhotoPickerBridge] 弹出相册选择器并处理选择结果.
public class TbchatMediaPickerPlugin: NSObject, FlutterPlugin {

  /// 强引用桥接对象，避免被 ARC 释放导致选择器无法弹出
  private var bridge: HXPhotoPickerBridge?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "tbchat_media_picker", binaryMessenger: registrar.messenger())
    let instance = TbchatMediaPickerPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  /// 处理 Flutter 侧方法调用，仅支持 "pickMedia"
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "pickMedia":
      let args = call.arguments as? [String: Any]
      let mimeType = args?["mimeType"] as? Int ?? 0
      let maxSelectNum = args?["maxSelectNum"] as? Int ?? 1
      let maxSize = args?["maxSize"] as? Int ?? 0
      let gridCount = args?["gridCount"] as? Int ?? 4
      let maxWidth = args?["maxWidth"] as? Int ?? 0
      let maxHeight = args?["maxHeight"] as? Int ?? 0
      let language = args?["language"] as? Int ?? 0
      if bridge == nil {
        bridge = HXPhotoPickerBridge()
      }
      bridge?.pickMedia(mimeType: mimeType, maxSelectNum: maxSelectNum, maxSize: maxSize, gridCount: gridCount, maxWidth: maxWidth, maxHeight: maxHeight, language: language, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
