/// 앱 전체에서 쓰는 데이터 모델.
library;

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
  });

  final String id;
  final String title;
  final String uploader;
  final String url;
  final int durationSeconds;
  final String? thumbnail;
  final List<FormatInfo> formats;

  factory MediaInfo.fromJson(Map<String, dynamic> j, String url) {
    return MediaInfo(
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

class DownloadOptions {
  const DownloadOptions({
    required this.kind,
    this.audioFormat = 'mp3',
    this.maxHeight,
    this.trimStart,
    this.trimEnd,
  });

  final MediaKind kind;

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
