import '../backend/backend.dart';
import '../models.dart';

/// 미리듣기용 소리 파일을 만들어 주고 기억해 둔다.
///
/// 영상의 소리 전체를 한 번만 받아 두고(매우 빠르다), 구간 자르기와 음량 조절은 폰/PC 안에서 한다.
/// 구간 파일은 기억해 두고, 음량 조절은 그 위에 입혀서 돌려준다.
class PreviewRenderer {
  PreviewRenderer(this._backend);

  final Backend _backend;
  final Map<String, Future<String>> _segments = {};

  /// [url] 의 [startSec]~[endSec] 를 [gain] 음량으로 들을 수 있는 파일 경로.
  Future<String> render(
    String url,
    int startSec,
    int endSec,
    AudioGain gain, {
    String? audioUrl,
  }) async {
    final key = '$url|$startSec|$endSec';
    if (_segments.length > 8) _segments.clear();
    final segment = _segments[key] ??= _segment(url, audioUrl, startSec, endSec);
    try {
      return await _backend.previewGain(await segment, gain, ext: 'wav');
    } catch (_) {
      _segments.remove(key);
      rethrow;
    }
  }

  Future<String> _segment(String url, String? audioUrl, int s, int e) =>
      _backend.previewSegment(url, s.toDouble(), e.toDouble(), audioUrl: audioUrl);

  /// 미리 받아 두면 첫 미리듣기가 빨라진다(소리 전체를 한 번 받는다).
  Future<void> prefetch(String url, {String? audioUrl}) async {
    try {
      await _backend.previewFull(url, audioUrl: audioUrl);
    } catch (_) {}
  }
}
