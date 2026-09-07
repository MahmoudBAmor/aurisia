import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../application/transcription_controller.dart';
import '../domain/ports/transcription_session.dart';
import '../domain/transcription_profile.dart';
import 'speaker_transcript_card.dart';

class TranscriptionScreen extends StatefulWidget {
  const TranscriptionScreen({
    required this.session,
    this.profile = TranscriptionProfile.tunisianConversation,
    this.onProfileSelected,
    this.isDemo = false,
    super.key,
  });

  final TranscriptionSession session;
  final TranscriptionProfile profile;
  final ValueChanged<TranscriptionProfile>? onProfileSelected;
  final bool isDemo;

  @override
  State<TranscriptionScreen> createState() => _TranscriptionScreenState();
}

class _TranscriptionScreenState extends State<TranscriptionScreen> {
  late final TranscriptionController _controller;
  late final ScrollController _transcriptScrollController;
  bool _autoScrollScheduled = false;

  @override
  void initState() {
    super.initState();
    _controller = TranscriptionController(session: widget.session);
    _transcriptScrollController = ScrollController();
    _controller.addListener(_scheduleAutoScroll);
  }

  void _scheduleAutoScroll() {
    if (_controller.segments.isEmpty || _autoScrollScheduled || !mounted) {
      return;
    }
    _autoScrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_scrollToLatest());
    });
  }

  Future<void> _scrollToLatest() async {
    try {
      if (!mounted || !_transcriptScrollController.hasClients) {
        return;
      }
      await _transcriptScrollController.animateTo(
        _transcriptScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );

      // A lazily built list can discover a larger extent during the animation.
      // Reconcile for a few frames so batched transcript updates reach the true
      // bottom without starting overlapping animations.
      for (var attempt = 0; attempt < 3; attempt += 1) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || !_transcriptScrollController.hasClients) {
          return;
        }
        final position = _transcriptScrollController.position;
        final distanceToBottom = position.maxScrollExtent - position.pixels;
        if (distanceToBottom.abs() <= 0.5) {
          return;
        }
        position.jumpTo(position.maxScrollExtent);
      }
    } finally {
      _autoScrollScheduled = false;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_scheduleAutoScroll);
    _controller.dispose();
    _transcriptScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Scaffold(
            body: SafeArea(
              child: Column(
                children: [
                  _Header(
                    controller: _controller,
                    profile: widget.profile,
                    onProfileSelected: widget.onProfileSelected,
                    isDemo: widget.isDemo,
                  ),
                  Expanded(
                    child: _TranscriptBody(
                      controller: _controller,
                      scrollController: _transcriptScrollController,
                    ),
                  ),
                  _RecordingControls(controller: _controller),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.controller,
    required this.profile,
    required this.onProfileSelected,
    required this.isDemo,
  });

  final TranscriptionController controller;
  final TranscriptionProfile profile;
  final ValueChanged<TranscriptionProfile>? onProfileSelected;
  final bool isDemo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'النسخ المباشر',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 3),
                Text(
                  '${_profileName(profile)} • دون إنترنت',
                  key: const Key('active-transcription-profile'),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (isDemo) ...[
            _DemoBadge(isListening: controller.isListening),
            const SizedBox(width: 6),
          ],
          PopupMenuButton<TranscriptionProfile>(
            key: const Key('transcription-profile-selector'),
            enabled: !controller.isListening && onProfileSelected != null,
            initialValue: profile,
            tooltip: controller.isListening
                ? 'أوقف التسجيل لتغيير اللغة'
                : 'اختيار نوع النسخ',
            onSelected: onProfileSelected,
            itemBuilder: (context) => TranscriptionProfile.values
                .map(
                  (item) => PopupMenuItem<TranscriptionProfile>(
                    value: item,
                    child: Text(_profileName(item)),
                  ),
                )
                .toList(growable: false),
            icon: const Icon(Icons.translate_rounded),
            iconSize: 30,
            padding: const EdgeInsets.all(12),
          ),
          IconButton(
            key: const Key('clear-transcript-button'),
            tooltip: 'مسح النص',
            onPressed: controller.segments.isEmpty ? null : controller.clear,
            iconSize: 30,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }
}

String _profileName(TranscriptionProfile profile) {
  return switch (profile) {
    TranscriptionProfile.tunisianConversation => 'تونسي',
    TranscriptionProfile.formalArabicSermon => 'عربية فصحى • خطبة',
  };
}

class _DemoBadge extends StatelessWidget {
  const _DemoBadge({required this.isListening});

  final bool isListening;

  @override
  Widget build(BuildContext context) {
    final color = isListening ? AppColors.primary : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        'عرض تجريبي',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TranscriptBody extends StatelessWidget {
  const _TranscriptBody({
    required this.controller,
    required this.scrollController,
  });

  final TranscriptionController controller;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    if (controller.status == TranscriptionStatus.failed) {
      return _ErrorState(message: controller.error.toString());
    }
    if (controller.segments.isEmpty) {
      return const _EmptyState();
    }

    return ListView.builder(
      key: const Key('transcript-list'),
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      itemCount: controller.segments.length,
      itemBuilder: (context, index) {
        return SpeakerTranscriptCard(segment: controller.segments[index]);
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: const BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.graphic_eq_rounded,
                color: AppColors.primary,
                size: 38,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'إضغط على الزر وابدأ أحكي',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'كل متحدث يظهر باسمه ولونه الخاص',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: AppColors.error,
              size: 42,
            ),
            const SizedBox(height: 12),
            const Text('صار مشكل في النسخ'),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordingControls extends StatelessWidget {
  const _RecordingControls({required this.controller});

  final TranscriptionController controller;

  @override
  Widget build(BuildContext context) {
    final listening = controller.isListening;
    final busy = controller.status == TranscriptionStatus.stopping;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.outline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  listening ? 'نسمع فيك...' : 'جاهز للنسخ',
                  key: const Key('recording-status'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  listening ? 'المعالجة تتم محلياً' : 'إضغط للبدء',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Semantics(
            button: true,
            label: listening ? 'إيقاف التسجيل' : 'بدء التسجيل',
            child: FilledButton(
              key: const Key('record-button'),
              onPressed: busy ? null : controller.toggle,
              style: FilledButton.styleFrom(
                backgroundColor: listening
                    ? AppColors.error
                    : AppColors.primary,
                foregroundColor: AppColors.onAccent,
                minimumSize: const Size(72, 72),
                shape: const CircleBorder(),
                padding: EdgeInsets.zero,
              ),
              child: Icon(
                listening ? Icons.stop_rounded : Icons.mic_rounded,
                size: 34,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
