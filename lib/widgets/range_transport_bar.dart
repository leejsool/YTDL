import 'package:flutter/material.dart';

import 'pill_button.dart';

/// 재생 슬라이더 아래에 놓는 5개 버튼: 여기부터 · 시작 부분 · 재생 · 끝 부분 · 여기까지.
/// (음원 편집과 영상 편집이 같이 쓴다. 글자 없이 아이콘만, 길게 누르면 설명이 뜬다.)
class RangeTransportBar extends StatelessWidget {
  const RangeTransportBar({
    super.key,
    required this.enabled,
    required this.playing,
    required this.onSetStart,
    required this.onPlayStartPart,
    required this.onPlayPause,
    required this.onPlayEndPart,
    required this.onSetEnd,
  });

  final bool enabled;
  final bool playing;

  /// 지금 재생 위치를 구간의 시작으로 잡는다.
  final VoidCallback onSetStart;

  /// 구간 시작 부분만 짧게 들어 본다.
  final VoidCallback onPlayStartPart;

  /// 선택 구간을 재생하거나 멈춘다.
  final VoidCallback onPlayPause;
  final VoidCallback onPlayEndPart;

  /// 지금 재생 위치를 구간의 끝으로 잡는다.
  final VoidCallback onSetEnd;

  @override
  Widget build(BuildContext context) {
    VoidCallback? on(VoidCallback f) => enabled ? f : null;
    const gap = SizedBox(width: 8);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        PillButton(
          tooltip: '여기부터 (지금 위치를 시작으로)',
          onPressed: on(onSetStart),
          icon: const Icon(Icons.start, size: 22),
        ),
        gap,
        PillButton(
          tooltip: '시작 부분 듣기',
          onPressed: on(onPlayStartPart),
          icon: const Icon(Icons.skip_previous, size: 24),
        ),
        gap,
        PillButton(
          tooltip: playing ? '정지' : '선택 구간 재생',
          selected: playing,
          onPressed: on(onPlayPause),
          icon: Icon(playing ? Icons.pause : Icons.play_arrow, size: 28),
        ),
        gap,
        PillButton(
          tooltip: '끝 부분 듣기',
          onPressed: on(onPlayEndPart),
          icon: const Icon(Icons.skip_next, size: 24),
        ),
        gap,
        PillButton(
          tooltip: '여기까지 (지금 위치를 끝으로)',
          onPressed: on(onSetEnd),
          icon: const Icon(Icons.keyboard_tab, size: 22),
        ),
      ],
    );
  }
}
