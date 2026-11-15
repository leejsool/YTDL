/// 구간 자르기 미리보기에 쓰는 자료를 yt-dlp 가 준 포맷 목록에서 뽑는다.
///  - 스토리보드: 유튜브가 영상 전체를 일정 간격(약 5초)으로 찍어 놓은 작은 장면 모음 그림.
///  - 소리 주소: 영상 전체를 받지 않고 원하는 위치부터 바로 들어 볼 수 있는 소리 전용 스트림.
library;

import 'dart:math' as math;

/// 스토리보드 그림 한 장(여러 장면이 격자로 모여 있다) 안에서 장면 하나의 위치.
class StoryboardFrame {
  const StoryboardFrame({
    required this.url,
    required this.column,
    required this.row,
    required this.columns,
    required this.rows,
  });

  final String url;

  /// 이 장면의 칸 위치(0부터).
  final int column;
  final int row;

  /// 이 그림 한 장에 실제로 들어 있는 칸 수. 마지막 그림은 잘려 있어서 위쪽 설정값보다 작을 수 있다.
  final int columns;
  final int rows;
}

class Storyboard {
  const Storyboard({
    required this.urls,
    required this.frameWidth,
    required this.frameHeight,
    required this.columns,
    required this.rows,
    required this.fps,
    required this.totalFrames,
  });

  /// 그림 한 장씩의 주소(시간 순서).
  final List<String> urls;
  final int frameWidth;
  final int frameHeight;
  final int columns;
  final int rows;

  /// 초당 장면 수(약 0.2 = 5초마다 한 장면).
  final double fps;
  final int totalFrames;

  int get framesPerSheet => columns * rows;
  double get aspectRatio => frameWidth / frameHeight;

  /// 장면 사이 간격(초).
  double get intervalSeconds => fps > 0 ? 1 / fps : 0;

  /// [seconds] 시각의 장면.
  StoryboardFrame frameAt(double seconds) {
    final k = (seconds * fps).floor().clamp(0, totalFrames - 1);
    final sheet = math.min(k ~/ framesPerSheet, urls.length - 1);
    final within = k - sheet * framesPerSheet;
    final inSheet = math.min(framesPerSheet, totalFrames - sheet * framesPerSheet);
    return StoryboardFrame(
      url: urls[sheet],
      column: within % columns,
      row: within ~/ columns,
      columns: math.min(columns, inSheet),
      rows: (inSheet / columns).ceil(),
    );
  }

  /// yt-dlp 의 `formats` 에서 스토리보드(프로토콜 mhtml)를 찾는다. 없으면 null.
  /// 화면에 크게 보여도 흐리지 않도록 가로 320 이상 중 가장 작은 것을 고른다. 없으면 가장 큰 것.
  /// (그림은 보이는 장면의 것만 그때그때 내려받는다.)
  static Storyboard? fromFormats(List<dynamic>? formats, int durationSeconds) {
    if (formats == null) return null;
    final boards = <Map<String, dynamic>>[
      for (final f in formats)
        if (f is Map<String, dynamic> &&
            f['protocol'] == 'mhtml' &&
            f['fragments'] is List &&
            (f['fragments'] as List).isNotEmpty &&
            (f['columns'] as num? ?? 0) > 0 &&
            (f['rows'] as num? ?? 0) > 0 &&
            (f['fps'] as num? ?? 0) > 0 &&
            (f['width'] as num? ?? 0) > 0 &&
            (f['height'] as num? ?? 0) > 0)
          f,
    ]..sort((a, b) => (a['width'] as num).compareTo(b['width'] as num));
    if (boards.isEmpty) return null;
    final f = boards.firstWhere(
      (b) => (b['width'] as num) >= 320,
      orElse: () => boards.last,
    );

    final fragments = (f['fragments'] as List).whereType<Map<String, dynamic>>().toList();
    final urls = [for (final x in fragments) (x['url'] ?? '').toString()];
    if (urls.isEmpty || urls.any((u) => u.isEmpty)) return null;
    final fps = (f['fps'] as num).toDouble();
    final seconds = fragments.fold<double>(
      0,
      (sum, x) => sum + ((x['duration'] as num?)?.toDouble() ?? 0),
    );
    final total = ((seconds > 0 ? seconds : durationSeconds) * fps).round();
    if (total <= 0) return null;
    return Storyboard(
      urls: urls,
      frameWidth: (f['width'] as num).round(),
      frameHeight: (f['height'] as num).round(),
      columns: (f['columns'] as num).round(),
      rows: (f['rows'] as num).round(),
      fps: fps,
      totalFrames: total,
    );
  }
}

/// 미리듣기에 쓸 소리 전용 스트림 주소. 없으면 null.
/// 어느 기기에서나 재생되는 AAC(m4a)를 먼저 고르고, 없으면 다른 소리 전용 스트림을 쓴다.
/// 조각 목록(m3u8/dash)이나 자동 음량 보정(-drc) 버전은 쓰지 않는다.
String? pickPreviewAudioUrl(List<dynamic>? formats) {
  if (formats == null) return null;
  final candidates = <Map<String, dynamic>>[
    for (final f in formats)
      if (f is Map<String, dynamic> &&
          f['protocol'] == 'https' &&
          (f['url'] ?? '').toString().isNotEmpty &&
          (f['vcodec'] == null || f['vcodec'] == 'none') &&
          f['acodec'] != null &&
          f['acodec'] != 'none' &&
          !(f['format_id'] ?? '').toString().contains('drc'))
        f,
  ];
  if (candidates.isEmpty) return null;
  int rank(Map<String, dynamic> f) {
    final codec = (f['acodec'] ?? '').toString();
    if (codec == 'mp4a.40.2') return 0;
    if (codec.startsWith('mp4a')) return 1;
    return 2;
  }

  candidates.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    // 같은 종류면 가벼운 쪽(비트레이트가 낮은 쪽)이 먼저 열린다.
    return ((a['abr'] as num?) ?? 1e9).compareTo((b['abr'] as num?) ?? 1e9);
  });
  return candidates.first['url'].toString();
}
