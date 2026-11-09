import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'access.dart';
import 'api.dart';
import 'language.dart';
import 'logo.dart';
import 'models.dart';
import 'motion.dart';
import 'places.dart';
import 'settings.dart';
import 'theme.dart';
import 'update.dart';

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
  Timer? _fastPoll; // quicker refresh while an update downloads
  String? _laterFor; // version whose banner the user put off this session
  bool _triedStart = false; // started the bundled service once this launch

  @override
  void initState() {
    super.initState();
    _refresh(scanIfNeeded: true);
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _fastPoll?.cancel();
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
        if (mounted) await _run(context.t.busyScanning, () => widget.api.scan());
        st = await widget.api.status();
      }
      if (mounted) {
        appearance.value = themeModeOf(st.config.theme);
        language.value = st.config.language;
        setState(() {
          _status = st;
          _offline = null;
        });
      }
      // Poll faster while an update downloads, so the bar moves smoothly.
      _fastPoll?.cancel();
      if (st.update?.downloading ?? false) {
        _fastPoll = Timer(const Duration(milliseconds: 700), () {
          if (mounted) _refresh();
        });
      }
    } on ServiceUnavailable catch (e) {
      // First launch, or the service was quit: start the copy that ships
      // with the app once, quietly, before showing the "not running" screen.
      if (!_triedStart && MothballApi.bundledService() != null) {
        _triedStart = true;
        final err = await MothballApi.installService();
        if (err == null) {
          await Future<void>.delayed(const Duration(seconds: 2));
          return _refresh(scanIfNeeded: scanIfNeeded);
        }
      }
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
    await _run(context.t.busyScanning, () => widget.api.scan());
    await _refresh();
  }

  Future<void> _putAway(List<Candidate> items) async {
    final total = items.fold<int>(0, (s, c) => s + c.bytes);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.t.putAwayTitle(sizeOf(ctx, total))),
        content: SizedBox(
          width: 420,
          child: Text(ctx.t.putAwayBody(items.length, toTrash(ctx))),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.t.putAway)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await _run(context.t.busyPuttingAway, () => widget.api.clean(items.map((c) => c.path).toList()));
    if (res == null || !mounted) return;
    final moved = res.where((r) => r.moved).toList();
    final freed = moved.fold<int>(0, (s, r) => s + r.bytes);
    final left = res.length - moved.length;
    _toast(context.t.putAwayResult(left, sizeOf(context, freed)));
    await _refresh();
  }

  Future<void> _cleanCaches(List<CacheInfo> items) async {
    final total = items.fold<int>(0, (s, c) => s + c.bytes);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.t.cleanCachesTitle(sizeOf(ctx, total))),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final c in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${c.name} · ${sizeOf(ctx, c.bytes)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(c.how, style: TextStyle(fontSize: 13, color: MB.quiet(ctx))),
                ]),
              ),
          ]),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.t.clean)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await _run(context.t.busyCleaningCaches, () => widget.api.cleanCaches(items.map((c) => c.id).toList()));
    if (res == null || !mounted) return;
    final freed = res.fold<int>(0, (s, r) => s + r.bytes);
    final failed = res.where((r) => r.error.isNotEmpty).toList();
    _toast(failed.isEmpty
        ? context.t.cleanedResult(sizeOf(context, freed))
        : context.t.cleanedWithError(sizeOf(context, freed), failed.first.name, failed.first.error));
    await _refresh();
  }

  Future<void> _wake(MothballedProject p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.t.wakeTitle(p.name.isNotEmpty ? p.name : _name(p.path))),
        content: SizedBox(
          width: 420,
          child: p.commands.isEmpty
              ? Text(ctx.t.wakeRebuildsItself)
              : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(ctx.t.wakeWillRun),
                  const SizedBox(height: 12),
                  for (final c in p.commands) _Code(c),
                ]),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ctx.t.wake)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(context.t.busyWaking(p.name.isNotEmpty ? p.name : _name(p.path)), () => widget.api.wake(p.path));
    await _refresh();
  }

  Future<void> _update(UpdateInfo u) async {
    if (!u.canInstall) {
      await MothballApi.openUrl(u.notesUrl);
      return;
    }
    if (u.ready) {
      try {
        await widget.api.installUpdate();
      } catch (e) {
        _toast('$e');
        await _refresh();
        return;
      }
      // The service reopens the new app and restarts itself.
      exit(0);
    }
    try {
      await widget.api.downloadUpdate();
    } catch (e) {
      _toast('$e');
    }
    await _refresh();
  }

  void _whatsNew(UpdateInfo u) {
    showWhatsNew(context, u, onUpdate: () => _update(u), onGitHub: () => MothballApi.openUrl(u.notesUrl));
  }

  Future<void> _saveConfig(MothballConfig c) async {
    await _run(context.t.busySaving, () => widget.api.saveConfig(c));
    await _refresh();
  }

  bool _showBanner(Status? st) {
    final u = st?.update;
    if (u == null || !u.available || u.required || _offline != null) return false;
    // Once downloading, keep it visible: the user asked for it.
    return u.downloading || u.ready || u.installing || _laterFor != u.latest;
  }

  @override
  Widget build(BuildContext context) {
    final st = _status;
    final Widget body;
    if (_offline != null) {
      body = _Offline(key: const ValueKey('offline'), reason: _offline!, onRetry: () => _refresh(scanIfNeeded: true));
    } else if (st == null) {
      body = const Center(key: ValueKey('loading'), child: MothLogo(size: 56, alive: true, busy: true));
    } else if (st.update != null && st.update!.required) {
      body = UpdateRequired(
        key: const ValueKey('update-required'),
        update: st.update!,
        onUpdate: () => _update(st.update!),
        onNotes: () => _whatsNew(st.update!),
      );
    } else if (Platform.isMacOS && !st.access.fullDisk && !st.config.onboarded) {
      body = AccessOnboarding(
        key: const ValueKey('onboarding'),
        access: st.access,
        onCheck: () => _refresh(),
        onSkip: () => _saveConfig(st.config.copyWith(onboarded: true)),
      );
    } else {
      body = _Dashboard(
        key: const ValueKey('home'),
        status: st,
        busy: _busy,
        onScan: _scan,
        onPutAway: _putAway,
        onWake: _wake,
        onCleanCaches: _cleanCaches,
        onConfig: _saveConfig,
      );
    }
    return Scaffold(
      body: Column(children: [
        _TopBar(
          busy: _busy || (st?.scanning ?? false),
          running: st != null && _offline == null,
          onSettings: st == null
              ? null
              : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SettingsScreen(
                        config: st.config,
                        onSave: _saveConfig,
                        version: st.update?.current ?? '',
                        onCheckUpdate: () async {
                          final u = await widget.api.checkUpdate();
                          if (u != null && u.available) setState(() => _laterFor = null);
                          await _refresh();
                          return u;
                        },
                      ),
                    ),
                  ),
        ),
        AnimatedSize(
          duration: calm(context) ? Duration.zero : const Duration(milliseconds: 380),
          curve: ease,
          alignment: Alignment.topCenter,
          child: _showBanner(st)
              ? UpdateBanner(
                  update: st!.update!,
                  onUpdate: () => _update(st.update!),
                  onNotes: () => _whatsNew(st.update!),
                  onLater: () => setState(() => _laterFor = st.update!.latest),
                )
              : const SizedBox(width: double.infinity),
        ),
        Expanded(
          child: Stack(children: [
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: calm(context) ? Duration.zero : const Duration(milliseconds: 420),
                switchInCurve: ease,
                child: body,
              ),
            ),
            _BusyPill(visible: _busy, label: _busyLabel),
          ]),
        ),
      ]),
    );
  }
}

String _name(String path) => path.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).lastOrNull ?? path;

/// The last two folders of a project path, enough to tell siblings apart.
String _projectLabel(String project) {
  final parts = project.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).toList();
  if (parts.length >= 2 && parts.last.length <= 3) return '${parts[parts.length - 2]}/${parts.last}';
  return parts.isEmpty ? project : parts.last;
}

String _outputLabel(Candidate c) =>
    c.path.length > c.project.length ? c.path.substring(c.project.length + 1) : _name(c.path);

const _maxWidth = 860.0;

class _TopBar extends StatelessWidget {
  const _TopBar({required this.busy, required this.running, required this.onSettings});

  final bool busy;
  final bool running;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(24, 18, 16, 6),
      child: Row(children: [
        MothLogo(size: 30, busy: busy),
        const SizedBox(width: 10),
        Text('mothball', style: MB.display(context, 24)),
        const Spacer(),
        AnimatedOpacity(
          opacity: running ? 1 : 0,
          duration: const Duration(milliseconds: 400),
          child: Row(children: [
            const LiveDot(color: MB.accent, size: 6),
            const SizedBox(width: 4),
            Text(busy ? context.t.statusWorking : context.t.statusWatching, style: TextStyle(color: MB.quiet(context), fontSize: 13)),
          ]),
        ),
        const SizedBox(width: 8),
        IconButton(tooltip: context.t.settings, onPressed: onSettings, icon: const Icon(Icons.tune_rounded)),
      ]),
    );
  }
}

class _BusyPill extends StatelessWidget {
  const _BusyPill({required this.visible, required this.label});

  final bool visible;
  final String label;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = dark ? MB.ink : Colors.white;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 24,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, 1.6),
          duration: const Duration(milliseconds: 380),
          curve: ease,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 260),
            child: Center(
              child: Container(
                padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 18, 10),
                decoration: BoxDecoration(
                  color: dark ? const Color(0xFFEDEEEA) : MB.ink,
                  borderRadius: BorderRadius.circular(40),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 8))],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  MothLogo(size: 20, ink: fg, busy: visible),
                  const SizedBox(width: 10),
                  Text('$label…', style: TextStyle(color: fg, fontWeight: FontWeight.w500)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A rounded surface with a hairline border.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(24), this.tint});

  final Widget child;
  final EdgeInsets padding;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: tint ?? MB.cardColor(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MB.line(context)),
      ),
      child: child,
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({
    super.key,
    required this.status,
    required this.busy,
    required this.onScan,
    required this.onPutAway,
    required this.onWake,
    required this.onCleanCaches,
    required this.onConfig,
  });

  final Status status;
  final bool busy;
  final VoidCallback onScan;
  final ValueChanged<List<Candidate>> onPutAway;
  final ValueChanged<MothballedProject> onWake;
  final ValueChanged<List<CacheInfo>> onCleanCaches;
  final ValueChanged<MothballConfig> onConfig;

  @override
  Widget build(BuildContext context) {
    final st = status;
    var i = 0;
    Widget staggered(Widget w) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Appear(delay: Duration(milliseconds: 90 * i++), child: w),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 96),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxWidth),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (Platform.isMacOS && !st.access.fullDisk) staggered(AccessReminder(access: st.access, onCheck: onScan)),
              staggered(_SpacePanel(status: st, onAutopilot: (v) => onConfig(st.config.copyWith(autopilot: v)))),
              staggered(_IdlePanel(scan: st.lastScan, idleDays: st.config.idleDays, scanning: busy, onScan: onScan, onPutAway: onPutAway)),
              if ((st.lastScan?.caches ?? const []).isNotEmpty)
                staggered(_CachesPanel(caches: st.lastScan!.caches, onClean: onCleanCaches)),
              if (st.mothballed.isNotEmpty) staggered(_MothballedPanel(projects: st.mothballed, onWake: onWake)),
              if (st.events.isNotEmpty) staggered(_ActivityPanel(events: st.events)),
            ]),
          ),
        ),
      ],
    );
  }
}

class _SpacePanel extends StatelessWidget {
  const _SpacePanel({required this.status, required this.onAutopilot});

  final Status status;
  final ValueChanged<bool> onAutopilot;

  @override
  Widget build(BuildContext context) {
    final st = status;
    final quiet = MB.quiet(context);
    final reclaim = (st.lastScan?.idleBytes ?? 0) + (st.lastScan?.cacheBytes ?? 0);
    final gb = st.freeBytes / (1 << 30);
    return Panel(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 26),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Builder(builder: (context) {
                final (text, spacing) = MB.caps(context, context.t.freeSpace, 1.4);
                return Text(text, style: TextStyle(fontSize: 11, letterSpacing: spacing, fontWeight: FontWeight.w600, color: quiet));
              }),
              const SizedBox(height: 6),
              // The number and its unit read left to right in every language, and
              // shrink rather than overflow when the window is narrow.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Directionality(
                textDirection: TextDirection.ltr,
                child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  CountUp(
                    value: gb,
                    format: (v) => decimal(context, v, digits: v >= 100 ? 0 : 1),
                    style: MB.display(context, 72),
                  ),
                  const SizedBox(width: 10),
                  Text(context.t.unitGB, style: MB.display(context, 28, color: quiet)),
                ]),
                ),
              ),
            ]),
          ),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: _AutopilotToggle(config: st.config, onChanged: onAutopilot),
          ),
        ]),
        const SizedBox(height: 22),
        _SpaceBar(free: st.freeBytes, reclaim: reclaim, target: st.targetBytes, showTarget: st.config.autopilot),
        const SizedBox(height: 14),
        Wrap(spacing: 20, runSpacing: 8, children: [
          _Legend(color: MB.accent, label: context.t.legendFreeNow),
          if (reclaim > 0) _Legend(color: MB.accent, striped: true, label: context.t.legendCanGetBack(sizeOf(context, reclaim))),
          if (st.waitingBytes > 0) _Legend(color: quiet, label: context.t.legendWaiting(sizeOf(context, st.waitingBytes), inTrash(context))),
        ]),
      ]),
    );
  }
}

class _AutopilotToggle extends StatelessWidget {
  const _AutopilotToggle({required this.config, required this.onChanged});

  final MothballConfig config;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final on = config.autopilot;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: ease,
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 10, 12),
      decoration: BoxDecoration(
        color: on ? MB.accent.withValues(alpha: 0.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: on ? MB.accent.withValues(alpha: 0.35) : MB.line(context)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (on) ...[const LiveDot(color: MB.accent, size: 6), const SizedBox(width: 2)],
            Text(context.t.autopilot, style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 2),
          Text(on ? context.t.autopilotKeeping(gigabytes(context, config.targetFreeGB)) : context.t.off,
              style: TextStyle(fontSize: 13, color: MB.quiet(context))),
          ]),
        ),
        const SizedBox(width: 12),
        Switch(value: on, onChanged: onChanged),
      ]),
    );
  }
}

/// Free space, plus what putting idle output away would add, against the target.
class _SpaceBar extends StatelessWidget {
  const _SpaceBar({required this.free, required this.reclaim, required this.target, required this.showTarget});

  final int free;
  final int reclaim;
  final int target;
  final bool showTarget;

  @override
  Widget build(BuildContext context) {
    final scale = math.max((free + reclaim).toDouble(), target * 1.25).clamp(1, double.infinity);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: calm(context) ? Duration.zero : const Duration(milliseconds: 1300),
      curve: ease,
      builder: (context, t, _) => LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth;
        final freeW = w * (free / scale) * t;
        final reclaimW = w * (reclaim / scale) * t;
        final targetX = w * (target / scale);
        return SizedBox(
          height: 46,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              height: 14,
              child: DecoratedBox(
                decoration: BoxDecoration(color: MB.line(context), borderRadius: BorderRadius.circular(8)),
              ),
            ),
            PositionedDirectional(
              top: 8,
              start: 0,
              width: freeW + reclaimW,
              height: 14,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                // The bar fills from the start side, so it mirrors in Arabic.
                child: Transform.flip(flipX: context.rtl, child: CustomPaint(painter: _Stripes(MB.accent, solidWidth: freeW))),
              ),
            ),
            if (showTarget) ...[
              PositionedDirectional(
                start: targetX - 1,
                top: 0,
                width: 2,
                height: 30,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.onSurface, borderRadius: BorderRadius.circular(1)),
                ),
              ),
              PositionedDirectional(
                start: targetX - 60,
                width: 120,
                top: 32,
                child: Text(context.t.spaceTarget(sizeOf(context, target)),
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: MB.quiet(context))),
              ),
            ],
          ]),
        );
      }),
    );
  }
}

class _Stripes extends CustomPainter {
  _Stripes(this.color, {required this.solidWidth});

  final Color color;
  final double solidWidth;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, solidWidth, size.height), Paint()..color = color);
    final rest = Rect.fromLTWH(solidWidth, 0, size.width - solidWidth, size.height);
    canvas.save();
    canvas.clipRect(rest);
    canvas.drawRect(rest, Paint()..color = color.withValues(alpha: 0.18));
    final p = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..strokeWidth = 3;
    for (var x = solidWidth - size.height; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Stripes old) => old.solidWidth != solidWidth || old.color != color;
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, this.striped = false});

  final Color color;
  final String label;
  final bool striped;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          width: 12,
          height: 12,
          child: striped ? CustomPaint(painter: _Stripes(color, solidWidth: 0)) : ColoredBox(color: color),
        ),
      ),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(fontSize: 13, color: MB.quiet(context))),
    ]);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: MB.display(context, 26)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: TextStyle(color: MB.quiet(context))),
          ],
        ]),
      ),
      if (trailing != null) trailing!,
    ]);
  }
}

class _IdlePanel extends StatelessWidget {
  const _IdlePanel({required this.scan, required this.idleDays, required this.scanning, required this.onScan, required this.onPutAway});

  final ScanSummary? scan;
  final int idleDays;
  final bool scanning;
  final VoidCallback onScan;
  final ValueChanged<List<Candidate>> onPutAway;

  @override
  Widget build(BuildContext context) {
    final s = scan;
    final largest = s == null || s.idle.isEmpty ? 1 : s.idle.map((c) => c.bytes).reduce(math.max);
    return Panel(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _SectionHeader(
          title: context.t.idleProjects,
          subtitle: s == null
              ? context.t.notScannedYet
              : s.idle.isEmpty
                  ? context.t.idleNone('$idleDays', context.t.projectsCount(s.projects))
                  : context.t.idleSummary('$idleDays', sizeOf(context, s.idleBytes), context.t.foldersCount(s.idle.length)),
          trailing: TextButton.icon(
            onPressed: scanning ? null : onScan,
            icon: Spin(spinning: scanning, child: const Icon(Icons.refresh_rounded, size: 18)),
            label: Text(context.t.scan),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 360),
          curve: ease,
          alignment: Alignment.topCenter,
          child: s == null || s.idle.isEmpty
              ? const SizedBox(height: 8)
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const SizedBox(height: 18),
                  for (final (n, c) in s.idle.take(50).indexed)
                    Appear(
                      key: ValueKey(c.path),
                      delay: Duration(milliseconds: 260 + 45 * math.min(n, 12)),
                      offset: 8,
                      child: _IdleRow(c: c, share: c.bytes / largest, onPutAway: () => onPutAway([c])),
                    ),
                  if (s.idle.length > 50)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(context.t.andMore('${s.idle.length - 50}'), style: TextStyle(color: MB.quiet(context))),
                    ),
                  const SizedBox(height: 18),
                  Row(children: [
                    FilledButton.icon(
                      onPressed: () => onPutAway(s.idle),
                      icon: const Icon(Icons.inventory_2_outlined, size: 18),
                      label: Text(context.t.putAwayAll(sizeOf(context, s.idleBytes))),
                    ),
                    const SizedBox(width: 14),
                    Flexible(
                      child: Text(context.t.putAwayHint(toTrash(context)),
                          style: TextStyle(fontSize: 13, color: MB.quiet(context))),
                    ),
                  ]),
                ]),
        ),
      ]),
    );
  }
}

class _IdleRow extends StatelessWidget {
  const _IdleRow({required this.c, required this.share, required this.onPutAway});

  final Candidate c;
  final double share;
  final VoidCallback onPutAway;

  @override
  Widget build(BuildContext context) {
    final quiet = MB.quiet(context);
    final title = c.name.isNotEmpty ? c.name : _projectLabel(c.project);
    return Hoverable(
      builder: (context, hover) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: () => Places.open(c.project),
        onSecondaryTapUp: (d) => ProjectMenu.showAt(context, d.globalPosition, c.project),
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 6, 10),
        decoration: BoxDecoration(
          color: hover ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.04) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(title,
                      overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                ),
                const SizedBox(width: 8),
                _Chip(_outputLabel(c)),
              ]),
              const SizedBox(height: 3),
              _PathLine(c.project),
              const SizedBox(height: 3),
              Text(context.t.idleFor(c.idleDays, c.pack), style: TextStyle(fontSize: 13, color: quiet)),
            ]),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 120,
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(sizeOf(context, c.bytes), style: const TextStyle(fontWeight: FontWeight.w500, fontFeatures: [FontFeature.tabularFigures()])),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                height: 4,
                alignment: AlignmentDirectional.centerEnd,
                decoration: BoxDecoration(color: MB.line(context), borderRadius: BorderRadius.circular(3)),
                child: FractionallySizedBox(
                  widthFactor: share.clamp(0.04, 1.0),
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: MB.accent, borderRadius: BorderRadius.circular(3)),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          AnimatedOpacity(
            opacity: hover ? 1 : 0.45,
            duration: const Duration(milliseconds: 180),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              ProjectMenu(path: c.project),
              IconButton(tooltip: context.t.putAway, onPressed: onPutAway, icon: const Icon(Icons.inventory_2_outlined, size: 20)),
            ]),
          ),
        ]),
        ),
      ),
    );
  }
}

/// The project's folder, shortened, with the full path on hover.
class _PathLine extends StatelessWidget {
  const _PathLine(this.path);

  final String path;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: path,
      waitDuration: const Duration(milliseconds: 500),
      child: Text(
        Places.display(path),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textDirection: TextDirection.ltr,
        style: TextStyle(fontSize: 12.5, color: MB.quiet(context), fontFamily: 'Menlo', fontFamilyFallback: const ['Consolas', 'DejaVu Sans Mono', 'monospace']),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
      ),
      // Folder names like .next read left to right in every language.
      child: Text(text, textDirection: TextDirection.ltr, style: TextStyle(fontSize: 12, color: MB.quiet(context), fontWeight: FontWeight.w500)),
    );
  }
}

class _Code extends StatelessWidget {
  const _Code(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, textDirection: TextDirection.ltr, style: const TextStyle(fontFamily: 'Menlo', fontSize: 13)),
    );
  }
}

class _CachesPanel extends StatelessWidget {
  const _CachesPanel({required this.caches, required this.onClean});

  final List<CacheInfo> caches;
  final ValueChanged<List<CacheInfo>> onClean;

  @override
  Widget build(BuildContext context) {
    final quiet = MB.quiet(context);
    final safe = caches.where((c) => c.policy == 'auto' && c.canClean).toList();
    final safeBytes = safe.fold<int>(0, (s, c) => s + c.bytes);
    final total = caches.where((c) => c.canClean).fold<int>(0, (s, c) => s + c.bytes);
    final largest = caches.map((c) => c.bytes).fold<int>(1, math.max);
    return Panel(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _SectionHeader(
          title: context.t.caches,
          subtitle: context.t.cachesSubtitle(sizeOf(context, total)),
        ),
        const SizedBox(height: 18),
        for (final (n, c) in caches.indexed)
          Appear(
            key: ValueKey(c.id),
            delay: Duration(milliseconds: 200 + 40 * math.min(n, 12)),
            offset: 8,
            child: Hoverable(
              builder: (context, hover) => AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 6, 10),
                decoration: BoxDecoration(
                  color: hover ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.04) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(
                          child: Text(c.name,
                              overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                        ),
                        const SizedBox(width: 8),
                        if (c.policy == 'auto') _Tag(context.t.tagSafe, MB.accent),
                        if (c.policy == 'ask') _Tag(context.t.tagSlow, const Color(0xFFB7791F)),
                        if (c.policy == 'report') _Tag(context.t.tagInfo, quiet),
                      ]),
                      const SizedBox(height: 4),
                      Text(c.blocked.isNotEmpty ? context.t.cacheWaiting(c.blocked) : c.how,
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: quiet)),
                    ]),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 120,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(c.bytes == 0 ? context.t.sizeUnknown : sizeOf(context, c.bytes),
                          style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: c.bytes == 0 ? quiet : null,
                              fontFeatures: const [FontFeature.tabularFigures()])),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        height: 4,
                        alignment: AlignmentDirectional.centerEnd,
                        decoration: BoxDecoration(color: MB.line(context), borderRadius: BorderRadius.circular(3)),
                        child: FractionallySizedBox(
                          widthFactor: (c.bytes / largest).clamp(0.04, 1.0),
                          heightFactor: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: c.canClean ? MB.accent : MB.line(context),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 48,
                    child: c.canClean
                        ? AnimatedOpacity(
                            opacity: hover ? 1 : 0.45,
                            duration: const Duration(milliseconds: 180),
                            child: IconButton(
                                tooltip: context.t.clean, onPressed: () => onClean([c]), icon: const Icon(Icons.cleaning_services_outlined, size: 20)),
                          )
                        : null,
                  ),
                ]),
              ),
            ),
          ),
        if (safe.isNotEmpty) ...[
          const SizedBox(height: 18),
          Row(children: [
            FilledButton.icon(
              onPressed: () => onClean(safe),
              icon: const Icon(Icons.cleaning_services_outlined, size: 18),
              label: Text(context.t.cleanSafeCaches(sizeOf(context, safeBytes))),
            ),
            const SizedBox(width: 14),
            Flexible(
              child: Text(context.t.cachesAutopilotHint, style: TextStyle(fontSize: 13, color: quiet)),
            ),
          ]),
        ],
      ]),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _MothballedPanel extends StatelessWidget {
  const _MothballedPanel({required this.projects, required this.onWake});

  final List<MothballedProject> projects;
  final ValueChanged<MothballedProject> onWake;

  @override
  Widget build(BuildContext context) {
    final total = projects.fold<int>(0, (s, p) => s + p.bytes);
    return Panel(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _SectionHeader(
          title: context.t.mothballed,
          subtitle: context.t.mothballedSubtitle(context.t.projectsCount(projects.length), sizeOf(context, total)),
        ),
        const SizedBox(height: 14),
        for (final p in projects) _MothballedRow(p: p, onWake: () => onWake(p)),
      ]),
    );
  }
}

class _MothballedRow extends StatelessWidget {
  const _MothballedRow({required this.p, required this.onWake});

  final MothballedProject p;
  final VoidCallback onWake;

  @override
  Widget build(BuildContext context) {
    final quiet = MB.quiet(context);
    final row = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: () => Places.open(p.path),
      onSecondaryTapUp: (d) => ProjectMenu.showAt(context, d.globalPosition, p.path),
      child: Row(children: [
      MothLogo(size: 26, alive: p.returned, ink: p.returned ? null : quiet),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.name.isNotEmpty ? p.name : _name(p.path),
              overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 3),
          _PathLine(p.path),
          const SizedBox(height: 3),
          Text(
            p.returned ? context.t.backOnThisOne : context.t.sizePutAway(sizeOf(context, p.bytes)),
            style: TextStyle(fontSize: 13, color: p.returned ? MB.accentOn(context) : quiet),
          ),
        ]),
      ),
      ProjectMenu(path: p.path),
      const SizedBox(width: 4),
      p.returned
          ? FilledButton(onPressed: onWake, child: Text(context.t.wake))
          : OutlinedButton(onPressed: onWake, child: Text(context.t.wake)),
    ]),
    );
    if (!p.returned) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12), child: row);
    }
    return Pulse(
      period: const Duration(milliseconds: 2400),
      builder: (context, t) => Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: MB.accent.withValues(alpha: 0.06 + 0.05 * t),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MB.accent.withValues(alpha: 0.18 + 0.2 * t)),
        ),
        child: row,
      ),
    );
  }
}

class _ActivityPanel extends StatelessWidget {
  const _ActivityPanel({required this.events});

  final List<ServiceEvent> events;

  @override
  Widget build(BuildContext context) {
    final quiet = MB.quiet(context);
    final shown = events.reversed.take(8).toList();
    return Panel(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _SectionHeader(title: context.t.lately),
        const SizedBox(height: 14),
        for (final (i, e) in shown.indexed)
          IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(
                width: 18,
                child: Column(children: [
                  const SizedBox(height: 6),
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: e.kind == 'error' ? Theme.of(context).colorScheme.error : (i == 0 ? MB.accent : MB.line(context)),
                    ),
                  ),
                  if (i < shown.length - 1) Expanded(child: Container(width: 1.5, color: MB.line(context))),
                ]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      _headline(context, e),
                      style: TextStyle(
                          fontWeight: FontWeight.w600, color: e.kind == 'error' ? Theme.of(context).colorScheme.error : null),
                    ),
                    const SizedBox(height: 2),
                    Text(e.message, style: TextStyle(fontSize: 13, color: quiet)),
                  ]),
                ),
              ),
              if (e.at != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 12),
                  child: Text(ago(context, e.at!), style: TextStyle(fontSize: 12, color: quiet)),
                ),
            ]),
          ),
      ]),
    );
  }

  static String _headline(BuildContext context, ServiceEvent e) {
    final t = context.t;
    final size = e.bytes > 0 ? sizeOf(context, e.bytes) : null;
    return switch (e.kind) {
      'autopilot' => size == null ? t.eventAutopilot : t.eventAutopilotSize(size),
      'emptied' => size == null ? t.eventEmptied : t.eventEmptiedSize(size),
      'error' => t.eventError,
      _ => size == null ? e.kind : '${e.kind} $size',
    };
  }
}

class _Offline extends StatefulWidget {
  const _Offline({super.key, required this.reason, required this.onRetry});

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
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Appear(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              MothLogo(size: 84, alive: true, busy: _starting),
              const SizedBox(height: 28),
              Text(context.t.offlineTitle, textAlign: TextAlign.center, style: MB.display(context, 40)),
              const SizedBox(height: 12),
              Text(
                context.t.offlineBody,
                textAlign: TextAlign.center,
                style: TextStyle(color: MB.quiet(context), fontSize: 15, height: 1.5),
              ),
              const SizedBox(height: 28),
              FilledButton(onPressed: _starting ? null : _start, child: Text(_starting ? context.t.starting : context.t.startMothball)),
              const SizedBox(height: 6),
              TextButton(onPressed: widget.onRetry, child: Text(context.t.tryAgain)),
              AnimatedSize(
                duration: const Duration(milliseconds: 240),
                child: _error == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
