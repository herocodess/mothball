import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'logo.dart';
import 'models.dart';
import 'motion.dart';
import 'theme.dart';

const _fdaSettings = 'x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles';

/// Opens System Settings at Privacy & Security > Full Disk Access.
Future<void> openFullDiskSettings() => Process.run('open', [_fdaSettings]);

/// Shows the program that needs access in Finder, ready to drag into the list.
/// Inside an app bundle that is the bundle, so the list shows Mothball's icon.
Future<void> revealInFinder(String path) {
  final i = path.indexOf('.app/Contents/');
  return Process.run('open', ['-R', i > 0 ? path.substring(0, i + 4) : path]);
}

String _folderNames(List<String> paths) {
  final names = paths.take(3).map((p) => p.split('/').where((s) => s.isNotEmpty).last).toList();
  if (names.isEmpty) return 'Desktop, Documents and Downloads';
  if (names.length == 1) return names.single;
  return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
}

/// First-run screen: explains why Mothball asks for Full Disk Access once,
/// instead of a string of separate prompts.
class AccessOnboarding extends StatelessWidget {
  const AccessOnboarding({super.key, required this.access, required this.onCheck, required this.onSkip});

  final AccessInfo access;
  final VoidCallback onCheck;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final quiet = MB.quiet(context);
    final copy = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Appear(child: Text('ONE THING FIRST', style: TextStyle(fontSize: 12, letterSpacing: 1.6, fontWeight: FontWeight.w600, color: MB.accentOn(context)))),
      const SizedBox(height: 14),
      Appear(
        delay: const Duration(milliseconds: 80),
        child: Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'Let Mothball see '),
            TextSpan(text: 'all', style: TextStyle(fontStyle: FontStyle.italic, color: MB.accentOn(context))),
            const TextSpan(text: ' your projects'),
          ]),
          style: MB.display(context, 50),
        ),
      ),
      const SizedBox(height: 18),
      Appear(
        delay: const Duration(milliseconds: 160),
        child: Text(
          'macOS keeps ${_folderNames(access.skipped)} private. Plenty of projects live there, so Mothball asks once for '
          'Full Disk Access rather than interrupting you with a prompt for every folder.',
          style: const TextStyle(fontSize: 17, height: 1.55),
        ),
      ),
      const SizedBox(height: 14),
      Appear(
        delay: const Duration(milliseconds: 220),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.verified_user_outlined, size: 18, color: quiet),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'It only reads folder names and sizes. It never opens your documents, never sends anything off your Mac, '
              'and never touches files tracked by git.',
              style: TextStyle(color: quiet, height: 1.5),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 28),
      Appear(
        delay: const Duration(milliseconds: 300),
        child: Wrap(spacing: 10, runSpacing: 10, children: [
          FilledButton.icon(
            onPressed: openFullDiskSettings,
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Open System Settings'),
          ),
          if (access.executable.isNotEmpty)
            OutlinedButton(onPressed: () => revealInFinder(access.executable), child: const Text('Show Mothball in Finder')),
          OutlinedButton(onPressed: onCheck, child: const Text("I've turned it on")),
        ]),
      ),
      const SizedBox(height: 14),
      Appear(
        delay: const Duration(milliseconds: 360),
        child: TextButton(
          onPressed: onSkip,
          style: TextButton.styleFrom(foregroundColor: quiet, padding: EdgeInsets.zero),
          child: Text('Not now, skip ${_folderNames(access.skipped)}'),
        ),
      ),
    ]);

    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth > 920;
      return SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: wide ? 56 : 28, vertical: 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1060),
            child: wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    Expanded(flex: 11, child: copy),
                    const SizedBox(width: 56),
                    const Expanded(flex: 9, child: Appear(delay: Duration(milliseconds: 260), child: _SettingsPreview())),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    copy,
                    const SizedBox(height: 36),
                    const Appear(delay: Duration(milliseconds: 260), child: _SettingsPreview()),
                  ]),
          ),
        ),
      );
    });
  }
}

/// A small, animated picture of the Full Disk Access list with Mothball's
/// switch flipping on, so the user knows exactly what they are looking for.
class _SettingsPreview extends StatefulWidget {
  const _SettingsPreview();

  @override
  State<_SettingsPreview> createState() => _SettingsPreviewState();
}

class _SettingsPreviewState extends State<_SettingsPreview> {
  bool _on = false;
  Timer? _t;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (calm(context)) {
      _t?.cancel();
      _on = true;
    } else {
      _t ??= Timer.periodic(const Duration(milliseconds: 1700), (_) => setState(() => _on = !_on));
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final win = dark ? const Color(0xFF1E232A) : Colors.white;
    final bar = dark ? const Color(0xFF262C34) : const Color(0xFFF1F0EB);
    final quiet = MB.quiet(context);
    Widget row(Widget icon, String name, {bool mothball = false}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: MB.line(context)))),
          child: Row(children: [
            SizedBox.square(dimension: 28, child: Center(child: icon)),
            const SizedBox(width: 12),
            Expanded(child: Text(name, style: TextStyle(fontWeight: mothball ? FontWeight.w600 : FontWeight.w400))),
            if (mothball)
              AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: ease,
                width: 38,
                height: 22,
                padding: const EdgeInsets.all(2),
                alignment: _on ? Alignment.centerRight : Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: _on ? MB.accent : MB.line(context),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 3)],
                  ),
                ),
              )
            else
              Container(
                width: 38,
                height: 22,
                padding: const EdgeInsets.all(2),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(color: MB.line(context), borderRadius: BorderRadius.circular(11)),
                child: Container(width: 18, height: 18, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
              ),
          ]),
        );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.35 : 0.07), blurRadius: 36, offset: const Offset(0, 14)),
        ],
      ),
      child: Container(
      decoration: BoxDecoration(
        color: win,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: MB.line(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: bar,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            for (final c in const [Color(0xFFFF5F57), Color(0xFFFEBC2E), Color(0xFF28C840)])
              Container(margin: const EdgeInsets.only(right: 7), width: 11, height: 11, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Text('Privacy & Security', style: TextStyle(fontSize: 12, color: quiet)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Full Disk Access', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Allow the applications below to access all your files.', style: TextStyle(fontSize: 12, color: quiet)),
          ]),
        ),
        row(Icon(Icons.terminal_rounded, size: 20, color: quiet), 'Terminal'),
        row(const MothLogo(size: 24), 'Mothball', mothball: true),
        row(Icon(Icons.backup_outlined, size: 20, color: quiet), 'Backup Utility'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: MB.line(context)))),
          child: Row(children: [
            Icon(Icons.add, size: 16, color: quiet),
            const SizedBox(width: 14),
            Icon(Icons.remove, size: 16, color: quiet),
          ]),
        ),
      ]),
      ),
    );
  }
}

/// A slim reminder on the home screen while access is still missing.
class AccessReminder extends StatelessWidget {
  const AccessReminder({super.key, required this.access, required this.onCheck});

  final AccessInfo access;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 10, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF2B33D).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF2B33D).withValues(alpha: 0.45)),
      ),
      child: Row(children: [
        const Icon(Icons.lock_outline_rounded, size: 20, color: Color(0xFFB7791F)),
        const SizedBox(width: 12),
        Expanded(
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '${_folderNames(access.skipped)} are not being scanned. ', style: const TextStyle(fontWeight: FontWeight.w600)),
            const TextSpan(text: 'Give Mothball Full Disk Access to include them.'),
          ])),
        ),
        const TextButton(onPressed: openFullDiskSettings, child: Text('Open Settings')),
        TextButton(onPressed: onCheck, child: const Text('Check again')),
      ]),
    );
  }
}
