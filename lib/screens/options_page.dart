import 'package:flutter/material.dart';

import '../backend/backend.dart';
import '../state/settings.dart';
import '../widgets/pill_button.dart';
import '../widgets/rocker_switch.dart';

/// 옵션 탭: 저장 폴더, 기본 음원 형식, 기본 영상 화질, 자동 음량 수준.
class OptionsPage extends StatefulWidget {
  const OptionsPage({super.key, required this.backend, required this.settings});

  final Backend backend;
  final AppSettings settings;

  @override
  State<OptionsPage> createState() => _OptionsPageState();
}

class _OptionsPageState extends State<OptionsPage> {
  late final TextEditingController _folderCtl = TextEditingController(
    text: widget.backend.folderName,
  );
  String? _folderNote;

  @override
  void initState() {
    super.initState();
    widget.settings.addListener(_changed);
  }

  @override
  void dispose() {
    widget.settings.removeListener(_changed);
    _folderCtl.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _chooseFolder() async {
    await widget.backend.chooseFolder();
    if (mounted) setState(() {});
  }

  Future<void> _applyFolderName() async {
    await widget.backend.setFolderName(_folderCtl.text);
    if (!mounted) return;
    setState(() {
      _folderCtl.text = widget.backend.folderName;
      _folderNote = '저장 폴더를 바꿨어요. 이미 저장한 파일은 그대로 이전 폴더에 있어요.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = widget.settings;
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 590;
        final gutter = wide ? 30.0 : 16.0;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: ListView(
              padding: EdgeInsets.fromLTRB(gutter, wide ? 26 : 16, gutter, 24),
              children: [
                Text(
                  '옵션',
                  style:
                      (wide
                              ? theme.textTheme.headlineLarge
                              : theme.textTheme.headlineSmall)
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                          ),
                ),
                const SizedBox(height: 4),
                Text(
                  '자주 쓰는 기본값을 정해 두세요.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                _section(
                  theme,
                  icon: Icons.folder_outlined,
                  title: '저장 폴더',
                  child: _folderBody(theme),
                ),
                _section(
                  theme,
                  icon: Icons.headphones,
                  title: '기본 음원 형식',
                  hint: '다운로드 탭에서 음원을 받을 때 처음 선택되어 있는 형식이에요.',
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: [
                      for (final f in AppSettings.audioFormats)
                        ButtonSegment(value: f, label: Text(f.toUpperCase())),
                    ],
                    selected: {settings.audioFormat},
                    onSelectionChanged: (s) => settings.setAudioFormat(s.first),
                  ),
                ),
                _section(
                  theme,
                  icon: Icons.movie_outlined,
                  title: '기본 영상 화질',
                  hint: '영상으로 받을 때 처음 선택되어 있는 화질이에요(그 화질이 없으면 가장 가까운 낮은 화질).',
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final h in AppSettings.videoHeights)
                        ChoiceChip(
                          label: Text(h == null ? '최고' : '${h}p'),
                          selected: settings.maxHeight == h,
                          onSelected: (_) => settings.setMaxHeight(h),
                        ),
                    ],
                  ),
                ),
                _section(
                  theme,
                  icon: Icons.content_cut,
                  title: '영상 자르기 기본 저장 방식',
                  hint: '영상 편집 탭에서 처음 선택되어 있는 방식이에요. 편집할 때마다 바꿀 수도 있어요.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RockerSwitch<bool>(
                        left: const RockerOption(
                          value: false,
                          label: '빠르게',
                          icon: Icons.bolt,
                        ),
                        right: const RockerOption(
                          value: true,
                          label: '정확하게',
                          icon: Icons.gps_fixed,
                        ),
                        value: settings.videoReencode,
                        onChanged: settings.setVideoReencode,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        settings.videoReencode
                            ? '정한 시각에서 정확히 시작해요. 다시 인코딩해서 시간이 더 걸리고 MP4로 저장돼요.'
                            : '그대로 복사해서 빠르고 화질 손실이 없어요. 대신 시작 지점이 바로 앞 장면으로 조금 당겨질 수 있어요.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                _section(
                  theme,
                  icon: Icons.volume_up_outlined,
                  title: '자동 음량 조절 수준',
                  hint: '음량 조절의 "자동" 버튼이 맞추는 목표 음량이에요. 클수록 소리가 커져요.',
                  child: _lufsBody(theme),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _section(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required Widget child,
    String? hint,
  }) {
    final colors = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 19, color: colors.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(
                hint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _folderBody(ThemeData theme) {
    final backend = widget.backend;
    final small = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    if (backend.canChooseFolder) {
      // Windows: 폴더를 직접 고른다.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(backend.saveLocationLabel, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 10),
          PillButton(
            onPressed: _chooseFolder,
            icon: const Icon(Icons.folder_open, size: 18),
            label: const Text('폴더 변경'),
          ),
        ],
      );
    }
    if (backend.canRenameFolder) {
      // Android: 음악/영화 폴더 안의 폴더 이름만 바꿀 수 있다.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(backend.saveLocationLabel, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(
            '안드로이드는 Music 과 Movies 폴더 안에만 저장할 수 있어서, 그 안의 폴더 이름만 바꿀 수 있어요.',
            style: small,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _folderCtl,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: '폴더 이름',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _applyFolderName(),
                ),
              ),
              const SizedBox(width: 8),
              PillButton(
                onPressed: _applyFolderName,
                icon: const Icon(Icons.check, size: 18),
                label: const Text('적용'),
              ),
            ],
          ),
          if (_folderNote != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_folderNote!, style: small),
            ),
        ],
      );
    }
    return Text(backend.saveLocationLabel, style: theme.textTheme.bodyMedium);
  }

  Widget _lufsBody(ThemeData theme) {
    final settings = widget.settings;
    final v = settings.targetLufs;
    final colors = theme.colorScheme;
    final small = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    String feel() {
      if (v >= -11) return '크게 (음악 앱 느낌)';
      if (v >= -15) return '보통 (유튜브 기준)';
      if (v >= -19) return '조금 작게';
      return '작게 (조용한 환경)';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$v LUFS',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(feel(), style: small)),
            if (v != AppSettings.defaultLufs)
              PillButton(
                onPressed: () =>
                    settings.setTargetLufs(AppSettings.defaultLufs),
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('기본값 −14'),
              ),
          ],
        ),
        Slider(
          min: AppSettings.minLufs.toDouble(),
          max: AppSettings.maxLufs.toDouble(),
          divisions: AppSettings.maxLufs - AppSettings.minLufs,
          value: v.toDouble(),
          label: '$v',
          onChanged: (x) => settings.setTargetLufs(x.round()),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${AppSettings.minLufs} (작게)', style: small),
            Text('${AppSettings.maxLufs} (크게)', style: small),
          ],
        ),
        const SizedBox(height: 8),
        Text('너무 크게 하면 소리가 찌그러지지 않도록 자동으로 최대치를 막아요.', style: small),
      ],
    );
  }
}
