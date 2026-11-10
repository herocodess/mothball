import 'dart:io';

import 'package:flutter/material.dart';

import 'api.dart';
import 'feedback.dart';
import 'language.dart';
import 'models.dart';
import 'motion.dart';
import 'theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.config,
    required this.onSave,
    this.version = '',
    this.onCheckUpdate,
  });

  final MothballConfig config;
  final Future<void> Function(MothballConfig) onSave;
  final String version;
  final Future<UpdateInfo?> Function()? onCheckUpdate;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late MothballConfig _c = widget.config;
  late final TextEditingController _roots = TextEditingController(text: widget.config.roots.join('\n'));
  bool _saving = false;
  bool _checking = false;
  String? _checkResult;

  Future<void> _checkNow() async {
    setState(() {
      _checking = true;
      _checkResult = null;
    });
    final t = context.t;
    String msg;
    try {
      final u = await widget.onCheckUpdate!();
      if (u == null || u.error.isNotEmpty) {
        msg = t.updateCheckFailed;
      } else if (u.available) {
        msg = t.updateCheckAvailable(u.latest);
      } else {
        msg = t.updateCheckLatest;
      }
    } catch (_) {
      msg = t.updateCheckError;
    }
    if (mounted) {
      setState(() {
        _checking = false;
        _checkResult = msg;
      });
    }
  }

  @override
  void dispose() {
    _roots.dispose();
    // Leaving without saving puts the saved appearance and language back.
    if (!_saving) {
      appearance.value = themeModeOf(widget.config.theme);
      language.value = widget.config.language;
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final roots = _roots.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    await widget.onSave(_c.copyWith(roots: roots));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final quiet = MB.quiet(context);
    var i = 0;
    Widget staggered(Widget w) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Appear(delay: Duration(milliseconds: 70 * i++), child: w),
        );
    return Scaffold(
      body: Column(children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 18, 24, 6),
          child: Row(children: [
            IconButton(tooltip: context.t.back, onPressed: () => Navigator.pop(context), icon: const BackButtonIcon()),
            const SizedBox(width: 6),
            Text(context.t.settings, style: MB.display(context, 28)),
            const Spacer(),
            FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? context.t.saving : context.t.save)),
          ]),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(24, 12, 24, 48), children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  staggered(_Group(children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(24, 20, 18, 20),
                      child: Wrap(
                        spacing: 20,
                        runSpacing: 12,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                            Text(context.t.appearance, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                            const SizedBox(height: 4),
                            Text(context.t.appearanceHint, style: TextStyle(color: quiet)),
                          ]),
                          SegmentedButton<String>(
                            showSelectedIcon: false,
                            segments: [
                              ButtonSegment(value: 'system', label: Text(context.t.themeSystem), icon: const Icon(Icons.contrast_rounded, size: 18)),
                              ButtonSegment(value: 'light', label: Text(context.t.themeLight), icon: const Icon(Icons.light_mode_outlined, size: 18)),
                              ButtonSegment(value: 'dark', label: Text(context.t.themeDark), icon: const Icon(Icons.dark_mode_outlined, size: 18)),
                            ],
                            selected: {_c.theme},
                            onSelectionChanged: (v) {
                              setState(() => _c = _c.copyWith(theme: v.first));
                              appearance.value = themeModeOf(v.first); // preview right away
                            },
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: MB.line(context)),
                    _LanguagePicker(
                      value: _c.language,
                      version: widget.version,
                      onChanged: (code) {
                        setState(() => _c = _c.copyWith(language: code));
                        language.value = code; // preview right away
                      },
                    ),
                  ])),
                  staggered(_Group(children: [
                    _Value(
                      title: context.t.idleAfter,
                      hint: context.t.idleAfterHint,
                      value: _c.idleDays,
                      unit: context.t.daysUnit(_c.idleDays),
                      min: 7,
                      max: 365,
                      onChanged: (v) => setState(() => _c = _c.copyWith(idleDays: v)),
                    ),
                  ])),
                  staggered(_Group(children: [
                    _Toggle(
                      title: context.t.autopilot,
                      hint: context.t.autopilotHint,
                      value: _c.autopilot,
                      onChanged: (v) => setState(() => _c = _c.copyWith(autopilot: v)),
                    ),
                    _Reveal(
                      show: _c.autopilot,
                      child: _Value(
                        title: context.t.keepFree,
                        value: _c.targetFreeGB,
                        unit: context.t.unitGB,
                        min: 5,
                        max: 500,
                        onChanged: (v) => setState(() => _c = _c.copyWith(targetFreeGB: v)),
                      ),
                    ),
                  ])),
                  if (Platform.isWindows)
                    staggered(_Group(children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(context.t.autoEmpty, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                          const SizedBox(height: 4),
                          Text(
                            context.t.autoEmptyWindows,
                            style: TextStyle(color: quiet, height: 1.45),
                          ),
                        ]),
                      ),
                    ]))
                  else
                    staggered(_Group(children: [
                    _Toggle(
                      title: context.t.autoEmpty,
                      hint: context.t.autoEmptyHint(inTrash(context)),
                      value: _c.autoEmptyDays > 0,
                      onChanged: (v) => setState(() => _c = _c.copyWith(autoEmptyDays: v ? 7 : 0)),
                    ),
                    _Reveal(
                      show: _c.autoEmptyDays > 0,
                      child: _Value(
                        title: context.t.emptyAfter,
                        value: _c.autoEmptyDays.clamp(1, 60),
                        unit: context.t.daysUnit(_c.autoEmptyDays.clamp(1, 60)),
                        min: 1,
                        max: 60,
                        onChanged: (v) => setState(() => _c = _c.copyWith(autoEmptyDays: v)),
                      ),
                    ),
                  ])),
                  staggered(_Group(children: [
                    _Toggle(
                      title: context.t.checkForUpdates,
                      hint: context.t.checkForUpdatesHint,
                      value: !_c.skipUpdateCheck,
                      onChanged: (v) => setState(() => _c = _c.copyWith(skipUpdateCheck: !v)),
                    ),
                    Divider(height: 1, color: MB.line(context)),
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(24, 16, 18, 16),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(widget.version.isEmpty ? 'Mothball' : context.t.versionLabel(widget.version),
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                            if (_checkResult != null) ...[
                              const SizedBox(height: 4),
                              Text(_checkResult!, style: TextStyle(color: quiet)),
                            ],
                          ]),
                        ),
                        if (widget.onCheckUpdate != null)
                          OutlinedButton(
                            onPressed: _checking ? null : _checkNow,
                            child: Text(_checking ? context.t.checking : context.t.checkNow),
                          ),
                      ]),
                    ),
                  ])),
                  staggered(_Group(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(context.t.sendFeedback, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text(
                          context.t.sendFeedbackHint,
                          style: TextStyle(color: quiet),
                        ),
                        const SizedBox(height: 14),
                        Wrap(spacing: 10, runSpacing: 10, children: [
                          OutlinedButton.icon(
                            onPressed: () => MothballApi.openUrl(FeedbackLinks.bugReport(widget.version)),
                            icon: const Icon(Icons.bug_report_outlined, size: 18),
                            label: Text(context.t.reportProblem),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => MothballApi.openUrl(FeedbackLinks.newStack(widget.version)),
                            icon: const Icon(Icons.add_circle_outline, size: 18),
                            label: Text(context.t.suggestStack),
                          ),
                        ]),
                      ]),
                    ),
                  ])),
                  staggered(_Group(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(context.t.foldersToWatch, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text(context.t.foldersToWatchHint, style: TextStyle(color: quiet)),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _roots,
                          textDirection: TextDirection.ltr, // paths read left to right
                          minLines: 3,
                          maxLines: 8,
                          style: const TextStyle(fontFamily: 'Menlo', fontSize: 13),
                          decoration: InputDecoration(
                            hintText: '/Users/you/dev',
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.04),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(context.t.ignoreTip,
                            style: TextStyle(fontSize: 13, color: quiet)),
                      ]),
                    ),
                  ])),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MB.cardColor(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MB.line(context)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

class _Reveal extends StatelessWidget {
  const _Reveal({required this.show, required this.child});

  final bool show;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 320),
      curve: ease,
      alignment: Alignment.topCenter,
      child: show
          ? Column(children: [Divider(height: 1, color: MB.line(context)), child])
          : const SizedBox(width: double.infinity),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.title, required this.hint, required this.value, required this.onChanged});

  final String title;
  final String hint;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(24, 20, 18, 20),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 4),
            Text(hint, style: TextStyle(color: MB.quiet(context), height: 1.45)),
          ]),
        ),
        const SizedBox(width: 20),
        Switch(value: value, onChanged: onChanged),
      ]),
    );
  }
}

class _Value extends StatelessWidget {
  const _Value({
    required this.title,
    this.hint,
    required this.value,
    required this.unit,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String title;
  final String? hint;
  final int value;
  final String unit;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(min, max);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              if (hint != null) ...[
                const SizedBox(height: 4),
                Text(hint!, style: TextStyle(color: MB.quiet(context))),
              ],
            ]),
          ),
          Text('$v', style: MB.display(context, 36)),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(unit, style: TextStyle(color: MB.quiet(context))),
          ),
        ]),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(overlayShape: const RoundSliderOverlayShape(overlayRadius: 14)),
          child: Slider(
            value: v.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: max - min,
            onChanged: (d) => onChanged(d.round()),
          ),
        ),
      ]),
    );
  }
}

/// The language list. Each language is shown in its own words, so someone
/// who opened Mothball in the wrong language can still find theirs.
class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker({required this.value, required this.version, required this.onChanged});

  final String value;
  final String version;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final quiet = MB.quiet(context);
    final known = value.isEmpty || languages.any((l) => l.$1 == value);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(24, 18, 18, 18),
      child: Wrap(
        spacing: 20,
        runSpacing: 12,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.translate_rounded, size: 18, color: quiet),
              const SizedBox(width: 8),
              Text(context.t.language, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            ]),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(context.t.languageHint, style: TextStyle(color: quiet)),
            ),
            // The translations are new: make fixing them one click away.
            if (context.t.localeName != 'en') ...[
              const SizedBox(height: 6),
              ConstrainedBox(
                // Long translations wrap rather than push past the hint.
                constraints: const BoxConstraints(maxWidth: 360),
                child: TextButton.icon(
                  onPressed: () => MothballApi.openUrl(FeedbackLinks.translation(version, FeedbackLinks.translationLanguage(context.t.localeName))),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.edit_note_rounded, size: 18),
                  label: Text(context.t.helpTranslate),
                ),
              ),
            ],
          ]),
          DropdownMenu<String>(
            key: const ValueKey('language'),
            initialSelection: known ? value : '',
            width: 240,
            requestFocusOnTap: false,
            inputDecorationTheme: InputDecorationTheme(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: MB.line(context))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: MB.line(context))),
            ),
            dropdownMenuEntries: [
              DropdownMenuEntry(value: '', label: context.t.languageSystem),
              for (final (code, name) in languages) DropdownMenuEntry(value: code, label: name),
            ],
            onSelected: (v) => onChanged(v ?? ''),
          ),
        ],
      ),
    );
  }
}
