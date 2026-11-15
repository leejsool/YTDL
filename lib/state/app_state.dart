import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import '../util/names.dart';

/// 최근 편집한 음원 목록(받은 것 + 자른 결과 + 연 파일). 앱을 껐다 켜도 유지된다.
class RecentStore extends ChangeNotifier {
  RecentStore({String key = 'recentAudio'}) : _key = key;

  /// 영상 편집용은 'recentVideo' 로 따로 둔다.
  final String _key;
  static const maxItems = 20;

  final List<SavedAudio> _items = [];
  List<SavedAudio> get items => List.unmodifiable(_items);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_key) ?? const [];
      _items.clear();
      for (final s in raw) {
        try {
          final a = SavedAudio.fromJson(jsonDecode(s) as Map<String, dynamic>);
          // 지워진 파일은 목록에서 뺀다.
          if (File(a.path).existsSync()) _items.add(a);
        } catch (_) {}
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> add(SavedAudio a) async {
    _items.removeWhere((x) => x.path == a.path);
    _items.insert(0, a);
    if (_items.length > maxItems) _items.removeRange(maxItems, _items.length);
    notifyListeners();
    await _save();
  }

  Future<void> remove(SavedAudio a) async {
    _items.removeWhere((x) => x.path == a.path);
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, [for (final a in _items) jsonEncode(a.toJson())]);
    } catch (_) {}
  }
}

/// 편집 탭에서 지금 열어 둔 파일. 다운로드 탭의 "편집하기" 버튼도 여기에 파일을 넘긴다.
class EditController extends ChangeNotifier {
  SavedAudio? _current;
  SavedAudio? get current => _current;

  /// 편집 탭으로 이동해 달라는 요청(앱 뼈대가 듣고 탭을 바꾼다).
  int openRequests = 0;

  void open(SavedAudio a) {
    _current = a;
    openRequests++;
    notifyListeners();
  }

  /// 같은 탭 안에서 편집 대상만 바꾼다(자른 결과가 새 편집 대상이 될 때).
  void replace(SavedAudio a) {
    _current = a;
    notifyListeners();
  }

  void close() {
    _current = null;
    notifyListeners();
  }

  /// 로컬 파일을 열어 편집 대상으로 삼고 최근 목록에도 올린다(파일 선택창·테스트 공용).
  SavedAudio openLocal(String path, {String? displayName, RecentStore? recent}) {
    final a = fromLocalFile(path, displayName: displayName);
    recent?.add(a);
    open(a);
    return a;
  }

  /// 컴퓨터/폰에 있는 아무 음원 파일을 편집 대상으로 만든다.
  /// 이 앱이 만든 "(cut …)" 이름이면 원본 기준 구간을 이어 받는다.
  static SavedAudio fromLocalFile(String path, {String? displayName}) {
    final name = displayName ?? path;
    final base = baseNameOf(name);
    final tag = parseCutTag(base);
    return SavedAudio(
      title: tag == null ? base : stripCut(base),
      path: path,
      location: displayName ?? path,
      srcStart: tag?.start ?? 0,
      srcEnd: tag?.end ?? 0,
      sourceLabel: tag == null ? null : '원본',
    );
  }
}
