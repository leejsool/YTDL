import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../backend/gain_args.dart';

/// 옵션 탭에서 고르는 기본값들. 앱을 껐다 켜도 유지된다.
/// (저장 폴더는 플랫폼마다 달라서 각 백엔드가 따로 기억한다.)
class AppSettings extends ChangeNotifier {
  static const _kAudio = 'set_audioFormat';
  static const _kHeight = 'set_maxHeight';
  static const _kLufs = 'set_lufs';
  static const _kReencode = 'set_videoReencode';

  /// 자동 음량의 목표 범위(LUFS). 숫자가 클수록(0에 가까울수록) 소리가 크다.
  static const minLufs = -24;
  static const maxLufs = -8;
  static const defaultLufs = -14;

  static const audioFormats = ['mp3', 'm4a', 'opus'];

  /// null = 최고 화질.
  static const videoHeights = <int?>[null, 1080, 720, 480, 360];

  String _audioFormat = 'mp3';
  int? _maxHeight = 1080;
  int _lufs = defaultLufs;

  /// 영상 편집의 기본 저장 방식. false = 빠르게(복사), true = 정확하게(다시 인코딩).
  bool _videoReencode = false;

  bool get videoReencode => _videoReencode;
  String get audioFormat => _audioFormat;
  int? get maxHeight => _maxHeight;
  int get targetLufs => _lufs;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final a = prefs.getString(_kAudio);
      if (a != null && audioFormats.contains(a)) _audioFormat = a;
      if (prefs.containsKey(_kHeight)) {
        final h = prefs.getInt(_kHeight) ?? 0;
        _maxHeight = h == 0 ? null : h;
      }
      _lufs = (prefs.getInt(_kLufs) ?? defaultLufs).clamp(minLufs, maxLufs);
      _videoReencode = prefs.getBool(_kReencode) ?? false;
    } catch (_) {}
    gainTargetLufs = _lufs;
    notifyListeners();
  }

  Future<void> setAudioFormat(String v) async {
    if (!audioFormats.contains(v) || v == _audioFormat) return;
    _audioFormat = v;
    notifyListeners();
    await _save((p) => p.setString(_kAudio, v));
  }

  Future<void> setMaxHeight(int? v) async {
    if (v == _maxHeight) return;
    _maxHeight = v;
    notifyListeners();
    await _save((p) => p.setInt(_kHeight, v ?? 0));
  }

  Future<void> setVideoReencode(bool v) async {
    if (v == _videoReencode) return;
    _videoReencode = v;
    notifyListeners();
    await _save((p) => p.setBool(_kReencode, v));
  }

  Future<void> setTargetLufs(int v) async {
    v = v.clamp(minLufs, maxLufs);
    if (v == _lufs) return;
    _lufs = v;
    gainTargetLufs = v;
    notifyListeners();
    await _save((p) => p.setInt(_kLufs, v));
  }

  Future<void> _save(Future<bool> Function(SharedPreferences p) write) async {
    try {
      await write(await SharedPreferences.getInstance());
    } catch (_) {}
  }
}
