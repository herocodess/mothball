import 'package:flutter/material.dart';

import 'api.dart';
import 'logo.dart';
import 'models.dart';
import 'motion.dart';
import 'theme.dart';

/// The thin strip under the top bar that says a new version is out, then
/// shows the download, then "Restart to update".
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({
    super.key,
    required this.update,
    required this.onUpdate,
    required this.onNotes,
    required this.onLater,
  });

  final UpdateInfo update;
  final VoidCallback onUpdate;
  final VoidCallback onNotes;
  final VoidCallback onLater;

  @override
  Widget build(BuildContext context) {
    final u = update;
    final accent = MB.accentOn(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final String title;
    final String detail;
    if (u.ready) {
      title = 'Mothball ${u.latest} is ready';
      detail = 'Restart to finish. It takes a couple of seconds.';
    } else if (u.downloading) {
      title = 'Downloading Mothball ${u.latest}';
      detail = '${(u.progress * 100).round()}%';
    } else if (u.installing) {
      title = 'Installing Mothball ${u.latest}';
      detail = 'Mothball will reopen on its own.';
    } else {
      title = 'Mothball ${u.latest} is out';
      detail = u.error.isNotEmpty ? u.error : 'You have ${u.current}.';
    }
    final busy = u.downloading || u.installing;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF14261E) : const Color(0xFFEAF6EF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accent.withValues(alpha: 0.35)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
                child: Row(children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
                    child: busy
                        ? Padding(padding: const EdgeInsets.all(9), child: CircularProgressIndicator(strokeWidth: 2, color: accent))
                        : Icon(u.ready ? Icons.restart_alt_rounded : Icons.arrow_circle_up_rounded, size: 20, color: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                      const SizedBox(height: 1),
                      Text(detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: u.error.isNotEmpty && !busy ? Theme.of(context).colorScheme.error : MB.quiet(context))),
                    ]),
                  ),
                  if (!busy) ...[
                    TextButton(onPressed: onNotes, child: const Text("What's new")),
                    if (!u.ready) TextButton(onPressed: onLater, child: const Text('Later')),
                    const SizedBox(width: 4),
                    FilledButton(
                      onPressed: onUpdate,
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                      child: Text(u.ready
                          ? 'Restart to update'
                          : u.canInstall
                              ? 'Update'
                              : 'Download'),
                    ),
                  ],
                ]),
              ),
              if (u.downloading)
                TweenAnimationBuilder<double>(
                  tween: Tween(end: u.progress),
                  duration: const Duration(milliseconds: 500),
                  curve: ease,
                  builder: (context, v, child) => LinearProgressIndicator(
                    value: v,
                    minHeight: 3,
                    color: accent,
                    backgroundColor: Colors.transparent,
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Shown instead of the dashboard when a release says this version must not
/// move files any more. Waking projects and the Trash still work outside it.
class UpdateRequired extends StatelessWidget {
  const UpdateRequired({super.key, required this.update, required this.onUpdate, required this.onNotes});

  final UpdateInfo update;
  final VoidCallback onUpdate;
  final VoidCallback onNotes;

  @override
  Widget build(BuildContext context) {
    final u = update;
    final busy = u.downloading || u.installing;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Appear(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              MothLogo(size: 64, alive: true, busy: busy),
              const SizedBox(height: 24),
              Text('Please update Mothball', textAlign: TextAlign.center, style: MB.display(context, 34)),
              const SizedBox(height: 12),
              Text(
                u.message.isNotEmpty
                    ? u.message
                    : 'Version ${u.latest} fixes a problem in the version you have.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, height: 1.5, color: MB.quiet(context)),
              ),
              const SizedBox(height: 8),
              Text(
                'Until you update, Mothball won\'t put anything away. Your projects and anything already in the $trashName are fine.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, height: 1.5, color: MB.quiet(context)),
              ),
              const SizedBox(height: 28),
              if (u.downloading) ...[
                SizedBox(
                  width: 260,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: u.progress, minHeight: 6),
                  ),
                ),
                const SizedBox(height: 10),
                Text('Downloading ${(u.progress * 100).round()}%', style: TextStyle(color: MB.quiet(context))),
              ] else if (u.installing)
                Text('Installing. Mothball will reopen on its own.', style: TextStyle(color: MB.quiet(context)))
              else
                Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
                  FilledButton(
                    onPressed: onUpdate,
                    child: Text(u.ready
                        ? 'Restart to update'
                        : u.canInstall
                            ? 'Update to ${u.latest}'
                            : 'Download ${u.latest}'),
                  ),
                  OutlinedButton(onPressed: onNotes, child: const Text("What's new")),
                ]),
              if (u.error.isNotEmpty && !busy) ...[
                const SizedBox(height: 14),
                Text(u.error, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// Shows the release notes of the new version in a sheet, with the update
/// button at hand.
Future<void> showWhatsNew(BuildContext context, UpdateInfo u,
    {required VoidCallback onUpdate, required VoidCallback onGitHub}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final quiet = MB.quiet(ctx);
      final date = u.publishedAt;
      const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
      return Dialog(
        insetPadding: const EdgeInsets.all(32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 26, 16, 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const MothLogo(size: 40, alive: true),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text("What's new in ${u.latest}", style: MB.display(ctx, 26)),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (date != null) 'Released ${date.day} ${months[date.month - 1]} ${date.year}',
                        'You have ${u.current}',
                      ].join(' · '),
                      style: TextStyle(color: quiet, fontSize: 13.5),
                    ),
                  ]),
                ),
                IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
              ]),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 14, 28, 8),
                child: u.notes.trim().isEmpty
                    ? Text('This release has no notes.', style: TextStyle(color: quiet))
                    : ReleaseNotes(u.notes),
              ),
            ),
            Divider(height: 1, color: MB.line(ctx)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              child: Row(children: [
                TextButton.icon(
                  onPressed: onGitHub,
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('View on GitHub'),
                ),
                const Spacer(),
                if (!u.downloading && !u.installing)
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      onUpdate();
                    },
                    child: Text(u.ready
                        ? 'Restart to update'
                        : u.canInstall
                            ? 'Update now'
                            : 'Download ${u.latest}'),
                  ),
              ]),
            ),
          ]),
        ),
      );
    },
  );
}

/// A small Markdown renderer for release notes: headings, bullet lists,
/// code blocks, and **bold**, `code` and [links](url) inside lines. Enough
/// for GitHub release notes without pulling in a package.
class ReleaseNotes extends StatelessWidget {
  const ReleaseNotes(this.markdown, {super.key});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    final quiet = MB.quiet(context);
    final ink = Theme.of(context).colorScheme.onSurface;
    final codeBg = ink.withValues(alpha: 0.06);
    final body = TextStyle(fontSize: 15, height: 1.55, color: ink);
    final out = <Widget>[];
    final lines = markdown.replaceAll('\r\n', '\n').split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final t = line.trim();
      if (t.startsWith('```')) {
        final code = <String>[];
        for (i++; i < lines.length && !lines[i].trim().startsWith('```'); i++) {
          code.add(lines[i]);
        }
        out.add(Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: codeBg, borderRadius: BorderRadius.circular(10)),
          child: SelectableText(code.join('\n'), style: const TextStyle(fontFamily: 'Menlo', fontSize: 13, height: 1.5)),
        ));
      } else if (t.isEmpty) {
        continue;
      } else if (t.startsWith('#')) {
        final text = t.replaceFirst(RegExp(r'^#+\s*'), '');
        out.add(Padding(
          padding: EdgeInsets.only(top: out.isEmpty ? 0 : 10, bottom: 8),
          child: Text(text, style: MB.display(context, t.startsWith('# ') ? 22 : 18)),
        ));
      } else if (RegExp(r'^[-*]\s').hasMatch(t)) {
        out.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 9, right: 12, left: 2),
              child: Container(width: 5, height: 5, decoration: BoxDecoration(color: MB.accentOn(context), shape: BoxShape.circle)),
            ),
            Expanded(child: Text.rich(_inline(t.substring(2), body, codeBg))),
          ]),
        ));
      } else {
        out.add(Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text.rich(_inline(t, body.copyWith(color: t.startsWith('>') ? quiet : ink), codeBg)),
        ));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: out);
  }

  static TextSpan _inline(String s, TextStyle base, Color codeBg) {
    s = s.replaceFirst(RegExp(r'^>\s*'), '');
    final spans = <InlineSpan>[];
    final re = RegExp(r'\*\*(.+?)\*\*|`([^`]+)`|\[([^\]]+)\]\([^)]+\)');
    var at = 0;
    for (final m in re.allMatches(s)) {
      if (m.start > at) spans.add(TextSpan(text: s.substring(at, m.start)));
      if (m.group(1) != null) {
        spans.add(TextSpan(text: m.group(1), style: const TextStyle(fontWeight: FontWeight.w600)));
      } else if (m.group(2) != null) {
        spans.add(TextSpan(
          text: m.group(2),
          style: TextStyle(fontFamily: 'Menlo', fontSize: base.fontSize! - 1.5, backgroundColor: codeBg),
        ));
      } else {
        spans.add(TextSpan(text: m.group(3), style: const TextStyle(fontWeight: FontWeight.w500)));
      }
      at = m.end;
    }
    if (at < s.length) spans.add(TextSpan(text: s.substring(at)));
    return TextSpan(style: base, children: spans);
  }
}
