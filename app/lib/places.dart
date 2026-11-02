import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

/// A small menu button for a project row: show it in the file manager, or
/// copy its path.
class ProjectMenu extends StatelessWidget {
  const ProjectMenu({super.key, required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ProjectAction>(
      tooltip: 'More',
      icon: const Icon(Icons.more_horiz, size: 20),
      position: PopupMenuPosition.under,
      onSelected: (a) => run(context, a, path),
      itemBuilder: (_) => items,
    );
  }

  static List<PopupMenuEntry<ProjectAction>> get items => [
        PopupMenuItem(
          value: ProjectAction.open,
          child: Row(children: [
            const Icon(Icons.folder_open_outlined, size: 18),
            const SizedBox(width: 12),
            Text('Show in ${Places.fileManager}'),
          ]),
        ),
        const PopupMenuItem(
          value: ProjectAction.copy,
          child: Row(children: [
            Icon(Icons.copy_outlined, size: 18),
            SizedBox(width: 12),
            Text('Copy path'),
          ]),
        ),
      ];

  /// The same menu, opened where the pointer is (for a right-click).
  static Future<void> showAt(BuildContext context, Offset global, String path) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final a = await showMenu<ProjectAction>(
      context: context,
      position: RelativeRect.fromRect(global & const Size(1, 1), Offset.zero & overlay.size),
      items: items,
    );
    if (a != null && context.mounted) await run(context, a, path);
  }

  static Future<void> run(BuildContext context, ProjectAction a, String path) async {
    switch (a) {
      case ProjectAction.open:
        await Places.open(path);
      case ProjectAction.copy:
        await Clipboard.setData(ClipboardData(text: path));
        if (context.mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(content: Text('Path copied'), duration: Duration(seconds: 2), behavior: SnackBarBehavior.floating),
          );
        }
    }
  }
}

/// What the project menu can do.
enum ProjectAction { open, copy }
