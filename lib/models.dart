/// 앱 전체에서 쓰는 데이터 모델.
library;

import 'util/preview_media.dart';

enum MediaKind { audio, video }

/// yt-dlp 가 알려 주는 스트림(포맷) 하나. 예상 용량 계산에만 쓴다.
class FormatInfo {
  const FormatInfo({
    this.id = '',
    this.height,
    this.vcodec = 'none',
    this.acodec = 'none',
    this.tbr,
    this.filesize,
    this.audioChannels,
  });

  final String id;
  final int? height;
  final String vcodec;
  final String acodec;

  /// 총 비트레이트(kbps)
  final double? tbr;

  /// 바이트. filesize 가 없으면 filesize_approx.
  final int? filesize;
  final int? audioChannels;

  bool get hasVideo => vcodec != 'none' && vcodec.isNotEmpty;
  bool get hasAudio => acodec != 'none' && acodec.isNotEmpty;

  factory FormatInfo.fromJson(Map<String, dynamic> j) {
    String codec(Object? v) => (v == null || v == '') ? 'none' : v.toString();
    return FormatInfo(
      id: (j['format_id'] ?? '').toString(),
      height: (j['height'] as num?)?.round(),
      vcodec: codec(j['vcodec']),
      acodec: codec(j['acodec']),
      tbr: (j['tbr'] as num?)?.toDouble(),
      filesize: ((j['filesize'] ?? j['filesize_approx']) as num?)?.round(),
      audioChannels: (j['audio_channels'] as num?)?.round(),
    );
  }
}

class MediaInfo {
  MediaInfo({
    required this.id,
    required this.title,
    required this.uploader,
    required this.url,
    required this.durationSeconds,
    this.thumbnail,
    this.formats = const [],
    this.storyboard,
    this.previewAudioUrl,
  });

  final String id;
  final String title;
  final String uploader;
  final String url;
  final int durationSeconds;
  final String? thumbnail;
  final List<FormatInfo> formats;

  /// 구간 자르기 미리보기용 장면 모음(없으면 장면 미리보기를 숨긴다).
  final Storyboard? storyboard;

  /// 구간 미리듣기용 소리 전용 스트림 주소(없으면 미리듣기를 숨긴다). 몇 시간 뒤에는 만료된다.
  final String? previewAudioUrl;

  factory MediaInfo.fromJson(Map<String, dynamic> j, String url) {
    final rawFormats = j['formats'] as List?;
    final duration = (j['duration'] as num?)?.round() ?? 0;
    return MediaInfo(
      storyboard: Storyboard.fromFormats(rawFormats, duration),
      previewAudioUrl: pickPreviewAudioUrl(rawFormats, j['requested_formats'] as List?),
      id: (j['id'] ?? '').toString(),
      title: (j['title'] ?? '(제목 없음)').toString(),
      uploader: (j['uploader'] ?? j['channel'] ?? '').toString(),
      url: url,
      durationSeconds: (j['duration'] as num?)?.round() ?? 0,
      thumbnail: j['thumbnail'] as String?,
      formats: [
        for (final f in (j['formats'] as List? ?? const []))
          if (f is Map<String, dynamic> && f['protocol'] != 'mhtml') FormatInfo.fromJson(f),
      ],
    );
  }
}

enum GainMode { none, manual, auto }

/// 음량 조절. 소리가 작은 음원을 키우는 데 주로 쓴다.
/// 음량을 바꾸려면 소리를 다시 인코딩해야 하므로(복사 불가) 약간의 음질 변화와 시간이 든다.
class AudioGain {
  const AudioGain.none()
      : mode = GainMode.none,
        db = 0;

  /// [db] 만큼 키운다(음수면 줄인다). 0 이면 조절 없음.
  const AudioGain.manual(this.db) : mode = GainMode.manual;

  /// 유튜브 표준 음량(-14 LUFS)에 맞춰 자동으로 키우거나 줄인다.
  const AudioGain.auto()
      : mode = GainMode.auto,
        db = 0;

  final GainMode mode;
  final double db;

  bool get isActive => switch (mode) {
        GainMode.none => false,
        GainMode.manual => db != 0,
        GainMode.auto => true,
      };

  /// 파일 이름에 붙일 표시. " (vol +6dB)" / " (vol auto)" / 조절 없으면 "".
  /// 원본 파일과 이름이 겹치지 않게 하고, 어떻게 만든 파일인지 알아보게 한다.
  String get nameTag {
    if (!isActive) return '';
    if (mode == GainMode.auto) return ' (vol auto)';
    return ' (vol ${db > 0 ? '+' : ''}${db.toStringAsFixed(0)}dB)';
  }

  @override
  bool operator ==(Object other) =>
      other is AudioGain && other.mode == mode && other.db == db;

  @override
  int get hashCode => Object.hash(mode, db);
}

class DownloadOptions {
  const DownloadOptions({
    required this.kind,
    this.audioFormat = 'mp3',
    this.maxHeight,
    this.trimStart,
    this.trimEnd,
    this.gain = const AudioGain.none(),
  });

  final MediaKind kind;

  /// 음원일 때만 쓴다(영상은 무시).
  final AudioGain gain;

  /// mp3 | m4a | opus
  final String audioFormat;

  /// 영상 최대 세로 해상도. null이면 최고 화질.
  final int? maxHeight;

  /// 잘라내기 구간(초). 둘 다 null이면 전체를 받는다.
  final int? trimStart;
  final int? trimEnd;

  bool get hasTrim => trimStart != null && trimEnd != null;
}

class DownloadProgress {
  const DownloadProgress({this.percent, required this.stage});

  /// 0.0 ~ 1.0, 알 수 없으면 null(진행바 무한 표시).
  final double? percent;
  final String stage;
}

class DownloadResult {
  const DownloadResult({required this.location, this.filePath});

  /// 사용자에게 보여줄 저장 위치 문자열.
  final String location;

  /// 실제 파일 경로(데스크톱에서만 의미 있음).
  final String? filePath;
}

/// 편집 대상 음원 파일(방금 받은 것, 이전에 자른 것, 컴퓨터/폰에서 연 것).
class SavedAudio {
  const SavedAudio({
    required this.title,
    required this.path,
    required this.location,
    required this.srcStart,
    required this.srcEnd,
    this.sourceLabel,
  });

  /// 잘린 구간 표기를 뺀 기본 이름. 다시 자를 때 이름 앞부분으로 쓴다.
  final String title;

  /// 재생·재편집에 쓰는 실제 파일 경로.
  final String path;

  /// 사용자에게 보여 줄 저장 위치.
  final String location;

  /// 이 파일의 0초가 "원본"의 몇 초인지, 끝이 몇 초인지. (원본 = 유튜브 영상, 또는 처음 연 파일)
  final double srcStart;
  final double srcEnd;

  /// "원본 영상" / "원본 파일". null 이면 원본과의 대응을 따로 보여 주지 않는다(처음 연 일반 파일).
  final String? sourceLabel;

  Map<String, Object?> toJson() => {
        'title': title,
        'path': path,
        'location': location,
        'srcStart': srcStart,
        'srcEnd': srcEnd,
        'sourceLabel': sourceLabel,
      };

  factory SavedAudio.fromJson(Map<String, dynamic> j) => SavedAudio(
        title: j['title'] as String,
        path: j['path'] as String,
        location: (j['location'] as String?) ?? (j['path'] as String),
        srcStart: (j['srcStart'] as num?)?.toDouble() ?? 0,
        srcEnd: (j['srcEnd'] as num?)?.toDouble() ?? 0,
        sourceLabel: j['sourceLabel'] as String?,
      );
}

class CancelledException implements Exception {
  @override
  String toString() => '취소되었습니다.';
}

class CancelToken {
  bool cancelled = false;
  void Function()? onCancel;

  void cancel() {
    cancelled = true;
    onCancel?.call();
  }
}
