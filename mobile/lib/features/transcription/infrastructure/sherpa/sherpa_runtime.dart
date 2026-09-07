import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

abstract final class SherpaRuntime {
  static Future<void>? _initialization;

  static Future<void> ensureInitialized() {
    return _initialization ??= sherpa.initBindingsAsync();
  }
}
