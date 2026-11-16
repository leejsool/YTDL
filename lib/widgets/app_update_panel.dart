import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../backend/backend.dart';
import '../util/app_update.dart';
import 'pill_button.dart';

/// 옵션 탭의 "앱 정보": 현재 버전을 보여 주고, 새 버전을 확인해 받아서 설치한다.
class AppUpdatePanel extends StatefulWidget {
  const AppUpdatePanel({super.key, required this.backend, this.updater});

  final Backend backend;

  /// 테스트에서 가짜를 넣는다. 비우면 GitHub 릴리스를 본다.
  final AppUpdater? updater;

  @override
  State<AppUpdatePanel> createState() => _AppUpdatePanelState();
}

enum _Phase { idle, checking, upToDate, available, downloading, done, error }

class _AppUpdatePanelState extends State<AppUpdatePanel> {
  late final AppUpdater _updater = widget.updater ?? AppUpdater();

  String? _current;
  _Phase _phase = _Phase.idle;
  UpdateInfo? _info;
  double? _progress; // 0~1, 모르면 null
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _current = info.version);
    } catch (_) {
      // 버전을 못 읽어도 화면은 떠야 한다.
    }
  }

  Future<void> _check() async {
    final current = _current;
    if (current == null) return;
    setState(() {
      _phase = _Phase.checking;
      _message = null;
    });
    try {
      final android = Platform.isAndroid;
      final abi = android ? await widget.backend.deviceAbi() : null;
      final info = await _updater.checkLatest(
        currentVersion: current,
        android: android,
        abi: abi,
      );
      if (!mounted) return;
      setState(() {
        _info = info;
        _phase = info == null ? _Phase.upToDate : _Phase.available;
      });
    } on UpdateException catch (e) {
      _fail(e.message);
    } catch (_) {
      _fail('업데이트를 확인하지 못했어요.');
    }
  }

  Future<void> _install() async {
    final info = _info;
    if (info == null) return;
    setState(() {
      _phase = _Phase.downloading;
      _progress = null;
      _message = null;
    });
    try {
      final path = await _updater.download(info, (got, total) {
        if (!mounted) return;
        setState(() => _progress = total > 0 ? got / total : null);
      });
      final note = await widget.backend.installUpdate(path);
      if (!mounted) return;
      setState(() {
        _phase = _Phase.done;
        _message = note;
      });
    } on UpdateException catch (e) {
      _fail(e.message);
    } catch (_) {
      _fail('업데이트하지 못했어요.');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.error;
      _message = message;
    });
  }

  static String _mb(int bytes) => '${(bytes / 1048576).toStringAsFixed(1)}MB';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final small = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final busy = _phase == _Phase.checking || _phase == _Phase.downloading;
    final info = _info;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _current == null ? '버전 확인 중…' : 'v$_current',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text('현재 설치된 버전', style: small)),
          ],
        ),
        const SizedBox(height: 12),
        if (_phase == _Phase.available && info != null) ...[
          Text(
            '새 버전 v${info.version} 이(가) 있어요 (${_mb(info.asset.size)})',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (info.notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              info.notes,
              style: small,
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 6),
          Text(
            Platform.isAndroid
                ? '받은 뒤 설치 화면이 열려요.'
                : '받은 뒤 앱이 닫히고 설치가 진행돼요. 받고 있는 파일이 있으면 끝난 뒤에 눌러 주세요.',
            style: small,
          ),
          const SizedBox(height: 10),
        ],
        if (_phase == _Phase.downloading) ...[
          LinearProgressIndicator(value: _progress),
          const SizedBox(height: 6),
          Text(
            _progress == null
                ? '내려받는 중…'
                : '내려받는 중… ${(_progress! * 100).round()}%',
            style: small,
          ),
          const SizedBox(height: 10),
        ],
        if (_phase == _Phase.upToDate)
          _status(theme, Icons.check_circle_outline, '최신 버전이에요.', colors.primary),
        if (_phase == _Phase.done && _message != null)
          _status(theme, Icons.info_outline, _message!, colors.primary),
        if (_phase == _Phase.error && _message != null)
          _status(theme, Icons.error_outline, _message!, colors.error),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            PillButton(
              onPressed: busy || _current == null || !widget.backend.canSelfUpdate
                  ? null
                  : _check,
              icon: _phase == _Phase.checking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.system_update_alt, size: 18),
              label: Text(_phase == _Phase.checking ? '확인 중…' : '업데이트 확인'),
            ),
            if (_phase == _Phase.available ||
                (_phase == _Phase.error && info != null))
              PillButton(
                onPressed: busy ? null : _install,
                selected: true,
                icon: const Icon(Icons.download, size: 18),
                label: Text(_phase == _Phase.error ? '다시 받기' : '업데이트'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _status(ThemeData theme, IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
