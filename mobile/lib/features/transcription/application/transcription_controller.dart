import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/ports/transcription_session.dart';
import '../domain/transcript_segment.dart';

enum TranscriptionStatus { idle, listening, stopping, failed }

class TranscriptionController extends ChangeNotifier {
  TranscriptionController({required this.session});

  final TranscriptionSession session;
  final List<TranscriptSegment> _segments = [];
  StreamSubscription<TranscriptSegment>? _subscription;
  TranscriptionStatus _status = TranscriptionStatus.idle;
  Object? _error;
  bool _disposed = false;

  List<TranscriptSegment> get segments => List.unmodifiable(_segments);
  TranscriptionStatus get status => _status;
  Object? get error => _error;
  bool get isListening => _status == TranscriptionStatus.listening;

  Future<void> toggle() => isListening ? stop() : start();

  Future<void> start() async {
    if (_status == TranscriptionStatus.listening ||
        _status == TranscriptionStatus.stopping) {
      return;
    }

    _error = null;
    _setStatus(TranscriptionStatus.listening);
    _subscription = session.start().listen(
      _upsert,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
  }

  Future<void> stop() async {
    if (_status != TranscriptionStatus.listening) {
      return;
    }

    _setStatus(TranscriptionStatus.stopping);
    await session.stop();
    await _subscription?.cancel();
    _subscription = null;
    _setStatus(TranscriptionStatus.idle);
  }

  void clear() {
    _segments.clear();
    _notify();
  }

  void _upsert(TranscriptSegment segment) {
    final index = _segments.indexWhere(
      (item) => item.eventId == segment.eventId,
    );
    if (index == -1) {
      _segments.add(segment);
    } else {
      _segments[index] = segment;
    }
    _notify();
  }

  void _onError(Object error, StackTrace stackTrace) {
    _error = error;
    _subscription = null;
    _setStatus(TranscriptionStatus.failed);
  }

  void _onDone() {
    _subscription = null;
    if (_status == TranscriptionStatus.listening) {
      _setStatus(TranscriptionStatus.idle);
    }
  }

  void _setStatus(TranscriptionStatus value) {
    _status = value;
    _notify();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    // The composition root owns the session lifetime. The controller only
    // releases its active recording when its screen goes away.
    unawaited(session.stop());
    super.dispose();
  }
}
