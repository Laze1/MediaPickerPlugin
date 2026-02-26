import Flutter
import UIKit

public class TbchatMediaPickerPlugin: NSObject, FlutterPlugin {
  /// 强引用桥接对象，避免被 ARC 释放导致选择器不弹出
  private var bridge: HXPhotoPickerBridge?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "tbchat_media_picker", binaryMessenger: registrar.messenger())
    let instance = TbchatMediaPickerPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "pickMedia":
      let args = call.arguments as? [String: Any]
      let mimeType = args?["mimeType"] as? Int ?? 0
      let maxSelectNum = args?["maxSelectNum"] as? Int ?? 1
      let maxSize = args?["maxSize"] as? Int ?? 0
      let gridCount = args?["gridCount"] as? Int ?? 4
      if bridge == nil {
        bridge = HXPhotoPickerBridge()
      }
      bridge?.pickMedia(mimeType: mimeType, maxSelectNum: maxSelectNum, maxSize: maxSize, gridCount: gridCount, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
