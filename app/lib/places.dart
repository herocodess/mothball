import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Where a project lives on disk, and ways to go and look at it.
class Places {
  /// What the system's file manager is called, for menu labels.
  static String get fileManager {
    if (Platform.isMacOS) return 'Finder';
    if (Platform.isWindows) return 'File Explorer';
    return 'Files';
  }

  /// Opens a folder in the system's file manager.
  static Future<void> open(String path) async {
    if (path.isEmpty) return;
    try {
      if (Platform.isMacOS) {
        await Process.start('open', [path]);
      } else if (Platform.isWindows) {
        await Process.start('explorer', [path]);
      } else {
        await Process.start('xdg-open', [path]);
      }
    } catch (_) {
      // No file manager to hand the folder to; nothing else to do.
    }
  }

  /// A path for people to read: the home folder as ~, and long paths
  /// shortened in the middle so the project's own folders stay visible.
  static String display(String path, {String? home, int keep = 3}) {
    final sep = path.contains('\\') && !path.contains('/') ? '\\' : '/';
    var p = path;
    final h = home ?? _home;
    if (h.isNotEmpty && (p == h || p.startsWith('$h$sep'))) {
      p = '~${p.substring(h.length)}';
    }
    final parts = p.split(sep);
    // Leading part (~, a drive like C:, or empty for /) plus the last few folders.
    if (parts.length <= keep + 2) return p;
    return [parts.first, '…', ...parts.sublist(parts.length - keep)].join(sep);
  }

  static String get _home => Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
}

/// What the project menu can do.
enum ProjectAction { open, copy }

/// The ⋯ button on a project row. Its menu opens when the pointer rests on
/// the button (or on click, or Enter), stays open while the pointer is over
/// it, and fades and scales in from the button.
class ProjectMenu extends StatefulWidget {
  const ProjectMenu({super.key, required this.path});

  final String path;

  /// The same menu, opened where the pointer is (for a right-click).
  static void showAt(BuildContext context, Offset global, String path) {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ContextMenu(at: global, path: path, onDone: () => entry.remove()),
    );
    overlay.insert(entry);
  }

  /// Runs a menu choice.
  static Future<void> run(BuildContext context, ProjectAction a, String path) async {
    final messenger = ScaffoldMessenger.maybeOf(context); // the menu may be gone by the time the copy lands
    switch (a) {
      case ProjectAction.open:
        await Places.open(path);
      case ProjectAction.copy:
        await Clipboard.setData(ClipboardData(text: path));
        messenger?.showSnackBar(
          const SnackBar(content: Text('Path copied'), duration: Duration(seconds: 2), behavior: SnackBarBehavior.floating),
        );
    }
  }

  @override
  State<ProjectMenu> createState() => _ProjectMenuState();
}

class _ProjectMenuState extends State<ProjectMenu> with SingleTickerProviderStateMixin {
  static const openDelay = Duration(milliseconds: 120);
  static const closeDelay = Duration(milliseconds: 200);

  final _portal = OverlayPortalController();
  final _link = LayerLink();
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    reverseDuration: const Duration(milliseconds: 130),
  );
  Timer? _timer;
  bool _pinned = false; // opened by click or keyboard: stays until dismissed

  @override
  void dispose() {
    _timer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  void _later(Duration d, VoidCallback f) {
    _timer?.cancel();
    _timer = Timer(d, f);
  }

  void _open({bool pin = false}) {
    _timer?.cancel();
    _pinned = _pinned || pin;
    if (!_portal.isShowing) _portal.show();
    _anim.forward();
  }

  void _close() {
    _timer?.cancel();
    _pinned = false;
    if (!_portal.isShowing) return;
    _anim.reverse().whenComplete(() {
      if (mounted && _anim.isDismissed && _portal.isShowing) _portal.hide();
    });
  }

  void _hoverIn() => _later(openDelay, _open);
  void _hoverOut() {
    if (!_pinned) _later(closeDelay, _close);
  }

  void _toggle() => _portal.isShowing && _anim.status != AnimationStatus.reverse ? _close() : _open(pin: true);

  void _choose(ProjectAction a) {
    unawaited(ProjectMenu.run(context, a, widget.path));
    _close();
  }

  @override
  Widget build(BuildContext context) {
    return TapRegion(
      groupId: this,
      onTapOutside: (_) => _close(),
      child: CompositedTransformTarget(
        link: _link,
        child: OverlayPortal(
          controller: _portal,
          overlayChildBuilder: (context) => CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, 4),
            child: Align(
              alignment: Alignment.topRight,
              child: TapRegion(
                groupId: this,
                child: MouseRegion(
                  onEnter: (_) => _timer?.cancel(),
                  onExit: (_) => _hoverOut(),
                  child: _Animated(
                    animation: _anim,
                    alignment: Alignment.topRight,
                    child: _MenuPanel(onChoose: _choose, onEscape: _close),
                  ),
                ),
              ),
            ),
          ),
          child: MouseRegion(
            onEnter: (_) => _hoverIn(),
            onExit: (_) => _hoverOut(),
            child: IconButton(
              onPressed: _toggle,
              icon: const Icon(Icons.more_horiz, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fades and scales a menu in from its corner.
class _Animated extends StatelessWidget {
  const _Animated({required this.animation, required this.alignment, required this.child});

  final Animation<double> animation;
  final Alignment alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        alignment: alignment,
        scale: Tween(begin: 0.92, end: 1.0).animate(curved),
        child: SlideTransition(
          position: Tween(begin: const Offset(0, -0.04), end: Offset.zero).animate(curved),
          child: child,
        ),
      ),
    );
  }
}

class _MenuPanel extends StatelessWidget {
  const _MenuPanel({required this.onChoose, required this.onEscape});

  final ValueChanged<ProjectAction> onChoose;
  final VoidCallback onEscape;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): onEscape},
      child: FocusScope(
        autofocus: true,
        child: Material(
          color: MB.cardColor(context),
          elevation: 10,
          shadowColor: Colors.black.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: MB.line(context))),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicWidth(
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _MenuItem(
                  icon: Icons.folder_open_outlined,
                  label: 'Show in ${Places.fileManager}',
                  onTap: () => onChoose(ProjectAction.open),
                ),
                _MenuItem(icon: Icons.copy_outlined, label: 'Copy path', onTap: () => onChoose(ProjectAction.copy)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      hoverColor: MB.accent.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 18, 10),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: MB.quiet(context)),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}

/// The right-click version: opens at the pointer with the same animation,
/// and closes on a click anywhere else or Escape.
class _ContextMenu extends StatefulWidget {
  const _ContextMenu({required this.at, required this.path, required this.onDone});

  final Offset at;
  final String path;
  final VoidCallback onDone;

  @override
  State<_ContextMenu> createState() => _ContextMenuState();
}

class _ContextMenuState extends State<_ContextMenu> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    reverseDuration: const Duration(milliseconds: 130),
  )..forward();
  bool _closing = false;

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    await _anim.reverse();
    widget.onDone();
  }

  void _choose(ProjectAction a) {
    unawaited(ProjectMenu.run(context, a, widget.path));
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Open towards the side with room, so the menu never runs off screen.
    final right = widget.at.dx > size.width - 240;
    final up = widget.at.dy > size.height - 140;
    final alignment = Alignment(right ? 1 : -1, up ? 1 : -1);
    return Stack(children: [
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _close,
          onSecondaryTap: _close,
        ),
      ),
      Positioned(
        left: right ? null : widget.at.dx,
        right: right ? size.width - widget.at.dx : null,
        top: up ? null : widget.at.dy,
        bottom: up ? size.height - widget.at.dy : null,
        child: _Animated(
          animation: _anim,
          alignment: alignment,
          child: _MenuPanel(onChoose: _choose, onEscape: _close),
        ),
      ),
    ]);
  }
}
