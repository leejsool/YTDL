import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 새 버전 확인과 설치 파일 내려받기. GitHub 릴리스(공개 저장소)를 쓴다.
///
/// 릴리스 파일 이름 규칙(지키지 않으면 못 찾는다):
///  - Windows : `YTDL-<버전>-windows-setup.exe`
///  - Android : `YTDL-<버전>-android-arm64.apk`, `YTDL-<버전>-android-armv7.apk`
class UpdateException implements Exception {
  UpdateException(this.message);
  final String message;

  @override
  String toString() => message;
}

class UpdateAsset {
  const UpdateAsset({required this.name, required this.url, required this.size});

  final String name;
  final String url;
  final int size;
}

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.notes,
    required this.asset,
  });

  /// "1.0.1" (앞의 v 는 뗀 값)
  final String version;
  final String notes;
  final UpdateAsset asset;
}

/// "v1.2.3", "1.2.3+4", "1.2.3-beta" 모두 [1, 2, 3] 으로 읽는다. 숫자가 아닌 칸은 0.
List<int> parseVersion(String v) {
  var s = v.trim();
  if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
  s = s.split('+').first.split('-').first;
  return s.split('.').map((p) => int.tryParse(p) ?? 0).toList();
}

/// a 가 더 새로우면 양수, 같으면 0, 오래됐으면 음수.
int compareVersions(String a, String b) {
  final x = parseVersion(a), y = parseVersion(b);
  final n = x.length > y.length ? x.length : y.length;
  for (var i = 0; i < n; i++) {
    final p = i < x.length ? x[i] : 0;
    final q = i < y.length ? y[i] : 0;
    if (p != q) return p.compareTo(q);
  }
  return 0;
}

class AppUpdater {
  AppUpdater({
    this.repo = defaultRepo,
    Future<Map<String, dynamic>> Function(Uri uri)? fetchJson,
  }) : _fetchJson = fetchJson ?? _httpJson;

  /// 릴리스를 올리는 GitHub 저장소(공개여야 한다).
  static const defaultRepo = 'leejsool/YTDL';

  final String repo;
  final Future<Map<String, dynamic>> Function(Uri uri) _fetchJson;

  /// Android 의 `Build.SUPPORTED_ABIS` 값을 릴리스 파일 이름의 조각으로 바꾼다.
  static String? androidAbiKey(String? abi) => switch (abi) {
    'arm64-v8a' => 'arm64',
    'armeabi-v7a' => 'armv7',
    'x86_64' => 'x86_64',
    _ => null,
  };

  /// 이 기기에 맞는 설치 파일. 없으면 null.
  static UpdateAsset? pickAsset(
    List<UpdateAsset> assets, {
    required bool android,
    String? abi,
  }) {
    for (final a in assets) {
      final n = a.name.toLowerCase();
      if (android) {
        final key = androidAbiKey(abi);
        if (key != null && n.endsWith('.apk') && n.contains('android-$key')) {
          return a;
        }
      } else if (n.endsWith('-windows-setup.exe')) {
        return a;
      }
    }
    return null;
  }

  /// 현재 버전보다 새 릴리스가 있으면 그 정보를, 없으면 null.
  Future<UpdateInfo?> checkLatest({
    required String currentVersion,
    required bool android,
    String? abi,
  }) async {
    final json = await _fetchJson(
      Uri.https('api.github.com', '/repos/$repo/releases/latest'),
    );
    final tag = (json['tag_name'] as String?) ?? '';
    if (tag.isEmpty) throw UpdateException('릴리스 정보를 읽지 못했어요.');
    if (compareVersions(tag, currentVersion) <= 0) return null;

    final assets = [
      for (final a in (json['assets'] as List? ?? const []))
        UpdateAsset(
          name: (a['name'] as String?) ?? '',
          url: (a['browser_download_url'] as String?) ?? '',
          size: (a['size'] as num?)?.toInt() ?? 0,
        ),
    ];
    final asset = pickAsset(assets, android: android, abi: abi);
    if (asset == null || asset.url.isEmpty) {
      throw UpdateException('새 버전($tag)은 있지만 이 기기에 맞는 설치 파일을 찾지 못했어요.');
    }
    return UpdateInfo(
      version: tag.startsWith('v') ? tag.substring(1) : tag,
      notes: ((json['body'] as String?) ?? '').trim(),
      asset: asset,
    );
  }

  /// 설치 파일을 임시 폴더에 내려받고 그 경로를 돌려준다.
  Future<String> download(
    UpdateInfo info,
    void Function(int received, int total) onProgress,
  ) async {
    final dir = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}ytdl_update',
    );
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    final target = File('${dir.path}${Platform.pathSeparator}${info.asset.name}');
    final part = File('${target.path}.part');

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(Uri.parse(info.asset.url));
      req.headers.set(HttpHeaders.userAgentHeader, 'YTDL-updater');
      final res = await req.close();
      if (res.statusCode != 200) {
        throw UpdateException('내려받지 못했어요 (HTTP ${res.statusCode}).');
      }
      final total = res.contentLength > 0 ? res.contentLength : info.asset.size;
      var got = 0;
      final sink = part.openWrite();
      try {
        await for (final chunk in res) {
          sink.add(chunk);
          got += chunk.length;
          onProgress(got, total);
        }
      } finally {
        await sink.close();
      }
      if (info.asset.size > 0 && got != info.asset.size) {
        throw UpdateException('파일이 다 받아지지 않았어요. 다시 시도해 주세요.');
      }
      await part.rename(target.path);
      return target.path;
    } on SocketException {
      throw UpdateException('인터넷에 연결하지 못했어요.');
    } finally {
      client.close(force: true);
    }
  }

  static Future<Map<String, dynamic>> _httpJson(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.getUrl(uri);
      req.headers
        ..set(HttpHeaders.userAgentHeader, 'YTDL-updater')
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final res = await req.close().timeout(const Duration(seconds: 20));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 404) {
        throw UpdateException('릴리스를 찾지 못했어요. (저장소가 비공개이거나 릴리스가 없어요)');
      }
      if (res.statusCode == 403 || res.statusCode == 429) {
        throw UpdateException('요청이 너무 많아요. 잠시 뒤에 다시 확인해 주세요.');
      }
      if (res.statusCode != 200) {
        throw UpdateException('업데이트 정보를 받지 못했어요 (HTTP ${res.statusCode}).');
      }
      return jsonDecode(body) as Map<String, dynamic>;
    } on SocketException {
      throw UpdateException('인터넷에 연결하지 못했어요.');
    } on TimeoutException {
      throw UpdateException('서버 응답이 없어요. 잠시 뒤에 다시 시도해 주세요.');
    } finally {
      client.close(force: true);
    }
  }
}
