import 'package:flutter/services.dart';

import 'bundled_model_pack.dart';

abstract interface class ModelPackMaterializer {
  Future<Map<String, String>> materialize(BundledModelPack pack);
}

class NativeModelPackMaterializer implements ModelPackMaterializer {
  const NativeModelPackMaterializer([
    this._channel = const MethodChannel(_channelName),
  ]);

  static const String _channelName = 'com.aurisia/model_pack';

  final MethodChannel _channel;

  @override
  Future<Map<String, String>> materialize(BundledModelPack pack) async {
    final result = await _channel.invokeMapMethod<String, String>(
      'materializeBundledPack',
      <String, Object>{
        'packId': pack.packId,
        'version': pack.version,
        'assetRoot': pack.assetRoot,
        'artifacts': pack.artifacts
            .map((artifact) => artifact.toPlatformArguments())
            .toList(growable: false),
      },
    );
    if (result == null) {
      throw StateError('The native model pack installer returned no paths.');
    }
    return Map<String, String>.unmodifiable(result);
  }
}
