import 'dart:async';
import 'dart:isolate';

class RemoteServiceException implements Exception {
  const RemoteServiceException(this.message, [this.remoteStackTrace]);

  final String message;
  final String? remoteStackTrace;

  @override
  String toString() => message;
}

typedef IsolateServiceEntrypoint = Future<void> Function(
  List<Object?> bootstrap,
);

class IsolateRpcClient {
  IsolateRpcClient._({required this._isolate, required this._commands});

  final Isolate _isolate;
  final SendPort _commands;
  bool _closed = false;

  static Future<IsolateRpcClient> spawn({
    required IsolateServiceEntrypoint entrypoint,
    required Map<String, Object?> configuration,
  }) async {
    final handshake = ReceivePort();
    try {
      final isolate = await Isolate.spawn<List<Object?>>(entrypoint, <Object?>[
        handshake.sendPort,
        configuration,
      ], errorsAreFatal: true);
      final response = await handshake.first.timeout(
        const Duration(seconds: 30),
      );
      if (response is SendPort) {
        return IsolateRpcClient._(isolate: isolate, commands: response);
      }
      isolate.kill(priority: Isolate.immediate);
      final error = Map<String, Object?>.from(response as Map);
      throw RemoteServiceException(
        error['error'].toString(),
        error['stackTrace']?.toString(),
      );
    } finally {
      handshake.close();
    }
  }

  Future<Map<String, Object?>> request(
    String method, {
    Map<String, Object?> payload = const {},
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (_closed) {
      throw StateError('The isolate service has already been closed.');
    }

    final replies = ReceivePort();
    try {
      _commands.send(<String, Object?>{
        'method': method,
        'replyTo': replies.sendPort,
        ...payload,
      });
      final raw = await replies.first.timeout(timeout);
      final response = Map<String, Object?>.from(raw as Map);
      final error = response['error'];
      if (error != null) {
        throw RemoteServiceException(
          error.toString(),
          response['stackTrace']?.toString(),
        );
      }
      return response;
    } finally {
      replies.close();
    }
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    try {
      await request('close', timeout: const Duration(seconds: 5));
    } finally {
      _closed = true;
      _isolate.kill(priority: Isolate.immediate);
    }
  }
}
