import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'access.dart';
import 'api.dart';
import 'logo.dart';
import 'models.dart';
import 'settings.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api});

  final MothballApi api;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Status? _status;
  String? _offline; // why the service cannot be reached
  bool _busy = false;
  String _busyLabel = '';
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refresh(scanIfNeeded: true);
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool scanIfNeeded = false}) async {
    try {
      var st = await widget.api.status();
      final justGranted = _status != null && !_status!.access.fullDisk && st.access.fullDisk;
      if (st.access.fullDisk && !st.config.onboarded) {
        await widget.api.saveConfig(st.config.copyWith(onboarded: true));
        st = await widget.api.status();
      }
      if (justGranted || (scanIfNeeded && st.lastScan == null)) {
        await _run('Scanning your projects', () => widget.api.scan());
        st = await widget.api.status();
      }
      if (mounted) {
        setState(() {
          _status = st;
          _offline = null;
        });
      }
    } on ServiceUnavailable catch (e) {
      if (mounted) setState(() => _offline = e.reason);
    } catch (e) {
      _toast('$e');
    }
  }

  Future<T?> _run<T>(String label, Future<T> Function() job) async {
    setState(() {
      _busy = true;
      _busyLabel = label;
    });
    try {
      return await job();
    } on ServiceUnavailable catch (e) {
      setState(() => _offline = e.reason);
      return null;
    } catch (e) {
      _toast('$e');
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _scan() async {
    await _run('Scanning your projects', () => widget.api.scan());
    await _refresh();
  }

  Future<void> _putAway(List<Candidate> items) async {
    final total = items.fold<int>(0, (s, c) => s + c.bytes);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Put away ${items.length == 1 ? '1 folder' : '${items.length} folders'}?'),
        content: Text(
          '${humanBytes(total)} of build output moves to the Trash. Your code is not touched, '
          'and each project can be woken with its usual install command.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Put away')),
        ],
      ),
    );
    if (ok != true) return;
    final res = await _run('Putting away', () => widget.api.clean(items.map((c) => c.path).toList()));
    if (res == null) return;
    final moved = res.where((r) => r.moved).toList();
    final freed = moved.fold<int>(0, (s, r) => s + r.bytes);
    final left = res.length - moved.length;
    _toast('Put away ${humanBytes(freed)}${left > 0 ? ', left $left alone' : ''}. Empty the Trash to free it.');
    await _refresh();
  }

  Future<void> _wake(MothballedProject p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wake this project?'),
        content: Text(p.commands.isEmpty
            ? 'This project rebuilds its output on its own the next time you open it.'
            : 'Mothball will run, in ${_name(p.path)}:\n\n${p.commands.join('\n')}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Wake')),
        ],
      ),
    );
    if (ok != true) return;
    await _run('Waking ${_name(p.path)}', () => widget.api.wake(p.path));
    await _refresh();
  }

  Future<void> _saveConfig(MothballConfig c) async {
    await _run('Saving', () => widget.api.saveConfig(c));
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final st = _status;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        titleSpacing: 20,
        title: const Row(children: [
          MothLogo(size: 28),
          SizedBox(width: 10),
          Text('mothball', style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.5)),
        ]),
        actions: [
          if (st != null)
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.tune),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => SettingsScreen(config: st.config, onSave: _saveConfig)),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(children: [
        if (_offline != null)
          _Offline(reason: _offline!, onRetry: () => _refresh(scanIfNeeded: true))
        else if (st == null)
          const Center(child: CircularProgressIndicator())
        else if (Platform.isMacOS && !st.access.fullDisk && !st.config.onboarded)
          AccessOnboarding(
            access: st.access,
            onCheck: () => _refresh(),
            onSkip: () => _saveConfig(st.config.copyWith(onboarded: true)),
          )
        else
          RefreshIndicator(
            onRefresh: _scan,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (Platform.isMacOS && !st.access.fullDisk) ...[
                        AccessReminder(access: st.access, onCheck: _scan),
                        const SizedBox(height: 16),
                      ],
                      _SpaceCard(status: st, onAutopilot: (v) => _saveConfig(st.config.copyWith(autopilot: v))),
                      const SizedBox(height: 16),
                      _IdleCard(scan: st.lastScan, idleDays: st.config.idleDays, onScan: _scan, onPutAway: _putAway),
                      if (st.mothballed.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _MothballedCard(projects: st.mothballed, onWake: _wake),
                      ],
                      if (st.events.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _EventsCard(events: st.events),
                      ],
                    ]),
                  ),
                ),
              ],
            ),
          ),
        if (_busy)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Material(
              color: Theme.of(context).colorScheme.inverseSurface,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 12),
                  Text('$_busyLabel…', style: TextStyle(color: Theme.of(context).colorScheme.onInverseSurface)),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

String _name(String path) => path.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).lastOrNull ?? path;

String _shortPath(String path, String project) {
  final parts = project.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).toList();
  final name = parts.isEmpty ? project : parts.last;
  final out = path.length > project.length ? path.substring(project.length + 1) : _name(path);
  return '$name / $out';
}

class _Section extends StatelessWidget {
  const _Section({required this.title, this.trailing, required this.child});

  final String title;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
            if (trailing != null) trailing!,
          ]),
          const SizedBox(height: 12),
          child,
        ]),
      ),
    );
  }
}

class _SpaceCard extends StatelessWidget {
  const _SpaceCard({required this.status, required this.onAutopilot});

  final Status status;
  final ValueChanged<bool> onAutopilot;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final quiet = Theme.of(context).colorScheme.onSurfaceVariant;
    final below = status.config.autopilot && status.freeBytes < status.targetBytes;
    return _Section(
      title: 'Free space',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(humanBytes(status.freeBytes), style: t.displaySmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          status.config.autopilot
              ? (below ? 'Below your ${status.config.targetFreeGB} GB target' : 'Keeping at least ${status.config.targetFreeGB} GB free')
              : 'Autopilot is off',
          style: t.bodyMedium?.copyWith(color: quiet),
        ),
        if (status.waitingBytes > 0) ...[
          const SizedBox(height: 4),
          Text('${humanBytes(status.waitingBytes)} from Mothball is waiting in the Trash',
              style: t.bodyMedium?.copyWith(color: quiet)),
        ],
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Autopilot'),
          subtitle: const Text('Put away output from idle projects when space runs low'),
          value: status.config.autopilot,
          onChanged: onAutopilot,
        ),
      ]),
    );
  }
}

class _IdleCard extends StatelessWidget {
  const _IdleCard({required this.scan, required this.idleDays, required this.onScan, required this.onPutAway});

  final ScanSummary? scan;
  final int idleDays;
  final VoidCallback onScan;
  final ValueChanged<List<Candidate>> onPutAway;

  @override
  Widget build(BuildContext context) {
    final quiet = Theme.of(context).colorScheme.onSurfaceVariant;
    final s = scan;
    return _Section(
      title: 'Idle $idleDays+ days',
      trailing: TextButton.icon(onPressed: onScan, icon: const Icon(Icons.refresh, size: 18), label: const Text('Scan')),
      child: s == null
          ? Text('Not scanned yet.', style: TextStyle(color: quiet))
          : s.idle.isEmpty
              ? Text('Nothing to put away. ${s.projects} projects checked.', style: TextStyle(color: quiet))
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('${humanBytes(s.idleBytes)} of build output in ${s.idle.length} folders',
                      style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 8),
                  for (final c in s.idle.take(50))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(_shortPath(c.path, c.project), overflow: TextOverflow.ellipsis),
                      subtitle: Text('${c.pack} · idle ${c.idleDays} days'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(humanBytes(c.bytes)),
                        IconButton(
                          tooltip: 'Put away',
                          icon: const Icon(Icons.inventory_2_outlined, size: 20),
                          onPressed: () => onPutAway([c]),
                        ),
                      ]),
                    ),
                  if (s.idle.length > 50)
                    Text('and ${s.idle.length - 50} more', style: TextStyle(color: quiet)),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton(onPressed: () => onPutAway(s.idle), child: Text('Put away all ${humanBytes(s.idleBytes)}')),
                  ),
                ]),
    );
  }
}

class _MothballedCard extends StatelessWidget {
  const _MothballedCard({required this.projects, required this.onWake});

  final List<MothballedProject> projects;
  final ValueChanged<MothballedProject> onWake;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Mothballed',
      child: Column(children: [
        for (final p in projects)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_name(p.path)),
            subtitle: Text(p.returned ? "You're back. Wake it to rebuild." : '${humanBytes(p.bytes)} put away'),
            trailing: p.returned
                ? FilledButton(onPressed: () => onWake(p), child: const Text('Wake'))
                : OutlinedButton(onPressed: () => onWake(p), child: const Text('Wake')),
          ),
      ]),
    );
  }
}

class _EventsCard extends StatelessWidget {
  const _EventsCard({required this.events});

  final List<ServiceEvent> events;

  @override
  Widget build(BuildContext context) {
    final quiet = Theme.of(context).colorScheme.onSurfaceVariant;
    return _Section(
      title: 'Recent activity',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final e in events.reversed.take(8))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              '${e.message}${e.bytes > 0 ? ' (${humanBytes(e.bytes)})' : ''}',
              style: TextStyle(color: e.kind == 'error' ? Theme.of(context).colorScheme.error : quiet),
            ),
          ),
      ]),
    );
  }
}

class _Offline extends StatefulWidget {
  const _Offline({required this.reason, required this.onRetry});

  final String reason;
  final VoidCallback onRetry;

  @override
  State<_Offline> createState() => _OfflineState();
}

class _OfflineState extends State<_Offline> {
  String? _error;
  bool _starting = false;

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _error = null;
    });
    final err = await MothballApi.installService();
    if (!mounted) return;
    setState(() {
      _starting = false;
      _error = err;
    });
    if (err == null) {
      await Future<void>.delayed(const Duration(seconds: 2));
      widget.onRetry();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const MothLogo(size: 72),
            const SizedBox(height: 20),
            Text(widget.reason, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'Mothball does its work in a small background service, so autopilot keeps running when this window is closed.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: _starting ? null : _start, child: Text(_starting ? 'Starting…' : 'Start Mothball')),
            TextButton(onPressed: widget.onRetry, child: const Text('Try again')),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ]),
        ),
      ),
    );
  }
}
