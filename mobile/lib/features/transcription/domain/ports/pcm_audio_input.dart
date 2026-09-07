import '../pcm_audio_frame.dart';

abstract interface class PcmAudioInput {
  Stream<PcmAudioFrame> start();

  Future<void> stop();

  Future<void> close();
}
