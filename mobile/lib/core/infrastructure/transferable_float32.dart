import 'dart:isolate';
import 'dart:typed_data';

TransferableTypedData float32ToTransferable(Float32List samples) {
  final bytes = samples.buffer.asUint8List(
    samples.offsetInBytes,
    samples.lengthInBytes,
  );
  return TransferableTypedData.fromList([bytes]);
}

Float32List transferableToFloat32(TransferableTypedData data) {
  return data.materialize().asFloat32List();
}
