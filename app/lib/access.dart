import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'language.dart';
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
      Appear(child: Builder(builder: (context) {
        final (text, spacing) = MB.caps(context, context.t.oneThingFirst, 1.6);
        return Text(text, style: TextStyle(fontSize: 12, letterSpacing: spacing, fontWeight: FontWeight.w600, color: MB.accentOn(context)));
      })),
      const SizedBox(height: 14),
      Appear(
        delay: const Duration(milliseconds: 80),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: context.t.accessHeadlineStart),
            TextSpan(
              text: context.t.accessHeadlineEmphasis,
              // Only Latin letters have a true italic; others get the colour alone.
              style: TextStyle(fontStyle: latinScript(context) ? FontStyle.italic : null, color: MB.accentOn(context)),
            ),
            TextSpan(text: context.t.accessHeadlineEnd),
          ]),
          style: MB.display(context, 50),
        ),
      ),
      const SizedBox(height: 18),
      Appear(
        delay: const Duration(milliseconds: 160),
        child: Text(
          context.t.accessBody(folderList(context, access.skipped)),
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
              context.t.accessPromise,
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
            label: Text(context.t.openSystemSettings),
          ),
          if (access.executable.isNotEmpty)
            OutlinedButton(onPressed: () => revealInFinder(access.executable), child: Text(context.t.showMothballInFinder)),
          OutlinedButton(onPressed: onCheck, child: Text(context.t.turnedItOn)),
        ]),
      ),
      const SizedBox(height: 14),
      Appear(
        delay: const Duration(milliseconds: 360),
        child: TextButton(
          onPressed: onSkip,
          style: TextButton.styleFrom(foregroundColor: quiet, padding: EdgeInsets.zero),
          child: Text(context.t.notNowSkip(folderList(context, access.skipped))),
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
                alignment: _on ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
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
                alignment: AlignmentDirectional.centerStart,
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
              Container(margin: const EdgeInsetsDirectional.only(end: 7), width: 11, height: 11, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Text(context.t.previewPrivacy, style: TextStyle(fontSize: 12, color: quiet)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.t.previewFullDiskAccess, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(context.t.previewAllow, style: TextStyle(fontSize: 12, color: quiet)),
          ]),
        ),
        row(Icon(Icons.terminal_rounded, size: 20, color: quiet), 'Terminal'),
        row(const MothLogo(size: 24), 'Mothball', mothball: true),
        row(Icon(Icons.backup_outlined, size: 20, color: quiet), context.t.previewBackup),
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
      padding: const EdgeInsetsDirectional.fromSTEB(18, 12, 10, 12),
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
            TextSpan(
              text: '${context.t.reminderNotScanned(folderCount(access.skipped), folderList(context, access.skipped))} ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: context.t.reminderGiveAccess),
          ])),
        ),
        TextButton(onPressed: openFullDiskSettings, child: Text(context.t.openSettings)),
        TextButton(onPressed: onCheck, child: Text(context.t.checkAgain)),
      ]),
    );
  }
}
