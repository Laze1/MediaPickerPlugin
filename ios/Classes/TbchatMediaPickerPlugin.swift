import Flutter
import UIKit

public class TbchatMediaPickerPlugin: NSObject, FlutterPlugin {
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
      let bridge = HXPhotoPickerBridge()
      bridge.pickMedia(mimeType: mimeType, maxSelectNum: maxSelectNum, maxSize: maxSize, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
