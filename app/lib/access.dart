import 'dart:io';

import 'package:flutter/material.dart';

import 'logo.dart';
import 'models.dart';

const _fdaSettings = 'x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles';

/// Opens System Settings at Privacy & Security > Full Disk Access.
Future<void> openFullDiskSettings() => Process.run('open', [_fdaSettings]);

/// Shows the program that needs access in Finder, ready to drag into the list.
Future<void> revealInFinder(String path) => Process.run('open', ['-R', path]);

String _folderNames(List<String> paths) {
  final names = paths.map((p) => p.split('/').where((s) => s.isNotEmpty).last).toList();
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
    final t = Theme.of(context).textTheme;
    final quiet = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const MothLogo(size: 56),
            const SizedBox(height: 24),
            Text('Let Mothball see all your projects', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Text(
              'macOS keeps ${_folderNames(access.skipped)} private until you allow access. '
              'Many projects live there, so Mothball asks once for Full Disk Access instead of '
              'interrupting you with a prompt for each folder.',
              style: t.bodyLarge,
            ),
            const SizedBox(height: 12),
            Text(
              'Mothball only reads folder names and sizes to find build output. It never opens your '
              'documents, never sends anything off your Mac, and never touches files tracked by git.',
              style: t.bodyMedium?.copyWith(color: quiet),
            ),
            const SizedBox(height: 24),
            const _Step(n: 1, text: 'Open Full Disk Access in System Settings.'),
            const _Step(n: 2, text: 'Click +, or drag Mothball into the list from the Finder window.'),
            const _Step(n: 3, text: 'Turn it on, then come back and check again.'),
            const SizedBox(height: 24),
            Wrap(spacing: 12, runSpacing: 12, children: [
              const FilledButton(onPressed: openFullDiskSettings, child: Text('Open System Settings')),
              if (access.executable.isNotEmpty)
                OutlinedButton(onPressed: () => revealInFinder(access.executable), child: const Text('Show Mothball in Finder')),
              OutlinedButton(onPressed: onCheck, child: const Text('Check again')),
            ]),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onSkip,
              child: Text('Not now: scan everything except ${_folderNames(access.skipped)}'),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text});

  final int n;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: scheme.primary.withValues(alpha: 0.15),
          child: Text('$n', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.primary)),
        ),
        const SizedBox(width: 12),
        Expanded(child: Padding(padding: const EdgeInsets.only(top: 2), child: Text(text))),
      ]),
    );
  }
}

/// A small reminder on the home screen while access is still missing.
class AccessReminder extends StatelessWidget {
  const AccessReminder({super.key, required this.access, required this.onCheck});

  final AccessInfo access;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
        child: Row(children: [
          const Icon(Icons.lock_outline, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text('${_folderNames(access.skipped)} are not being scanned. Give Mothball Full Disk Access to include them.'),
          ),
          const TextButton(onPressed: openFullDiskSettings, child: Text('Open Settings')),
          TextButton(onPressed: onCheck, child: const Text('Check again')),
        ]),
      ),
    );
  }
}
