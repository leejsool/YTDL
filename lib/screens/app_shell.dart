import 'package:flutter/material.dart';

import '../backend/backend.dart';
import '../state/app_state.dart';
import 'edit_page.dart';
import 'home_page.dart';

/// 앱 뼈대: 아래쪽 탭으로 [다운로드] / [편집] 을 오간다. 두 탭의 상태는 계속 유지된다.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.backend});

  final Backend backend;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final RecentStore _recent = RecentStore();
  final EditController _edit = EditController();
  int _index = 0;
  int _seenRequests = 0;

  @override
  void initState() {
    super.initState();
    _recent.load();
    _edit.addListener(_onEdit);
  }

  @override
  void dispose() {
    _edit.removeListener(_onEdit);
    _edit.dispose();
    _recent.dispose();
    super.dispose();
  }

  /// 다운로드 탭의 "편집하기" 등이 파일을 넘기면 편집 탭으로 이동한다.
  void _onEdit() {
    if (_edit.openRequests != _seenRequests) {
      _seenRequests = _edit.openRequests;
      if (mounted) setState(() => _index = 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          HomePage(backend: widget.backend, recent: _recent, editController: _edit),
          EditPage(
            backend: widget.backend,
            controller: _edit,
            recent: _recent,
            active: _index == 1,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.download_outlined), selectedIcon: Icon(Icons.download), label: '다운로드'),
          NavigationDestination(icon: Icon(Icons.content_cut), selectedIcon: Icon(Icons.content_cut), label: '편집'),
        ],
      ),
    );
  }
}
