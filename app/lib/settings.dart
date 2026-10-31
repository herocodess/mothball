import 'package:flutter/material.dart';

import 'models.dart';
import 'motion.dart';
import 'theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.config, required this.onSave});

  final MothballConfig config;
  final Future<void> Function(MothballConfig) onSave;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late MothballConfig _c = widget.config;
  late final TextEditingController _roots = TextEditingController(text: widget.config.roots.join('\n'));
  bool _saving = false;

  @override
  void dispose() {
    _roots.dispose();
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
          padding: const EdgeInsets.fromLTRB(12, 18, 24, 6),
          child: Row(children: [
            IconButton(tooltip: 'Back', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded)),
            const SizedBox(width: 6),
            Text('Settings', style: MB.display(context, 34)),
            const Spacer(),
            FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
          ]),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(24, 12, 24, 48), children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  staggered(_Group(children: [
                    _Value(
                      title: 'Idle after',
                      hint: 'A project with no commits for this long counts as idle.',
                      value: _c.idleDays,
                      unit: 'days',
                      min: 7,
                      max: 365,
                      onChanged: (v) => setState(() => _c = _c.copyWith(idleDays: v)),
                    ),
                  ])),
                  staggered(_Group(children: [
                    _Toggle(
                      title: 'Autopilot',
                      hint: 'Put away output from the longest-idle projects whenever free space drops below your target.',
                      value: _c.autopilot,
                      onChanged: (v) => setState(() => _c = _c.copyWith(autopilot: v)),
                    ),
                    _Reveal(
                      show: _c.autopilot,
                      child: _Value(
                        title: 'Keep free',
                        value: _c.targetFreeGB,
                        unit: 'GB',
                        min: 5,
                        max: 500,
                        onChanged: (v) => setState(() => _c = _c.copyWith(targetFreeGB: v)),
                      ),
                    ),
                  ])),
                  staggered(_Group(children: [
                    _Toggle(
                      title: 'Auto-empty',
                      hint: 'Permanently empty the folders Mothball put in the Trash after a grace period. Nothing else in the Trash is touched.',
                      value: _c.autoEmptyDays > 0,
                      onChanged: (v) => setState(() => _c = _c.copyWith(autoEmptyDays: v ? 7 : 0)),
                    ),
                    _Reveal(
                      show: _c.autoEmptyDays > 0,
                      child: _Value(
                        title: 'Empty after',
                        value: _c.autoEmptyDays.clamp(1, 60),
                        unit: 'days',
                        min: 1,
                        max: 60,
                        onChanged: (v) => setState(() => _c = _c.copyWith(autoEmptyDays: v)),
                      ),
                    ),
                  ])),
                  staggered(_Group(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Folders to watch', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text('One per line. Leave empty to watch your whole home folder.', style: TextStyle(color: quiet)),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _roots,
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
                        Text('Tip: add a .mothballignore file to any project to keep Mothball out of it.',
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
      padding: const EdgeInsets.fromLTRB(24, 20, 18, 20),
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
          Text('$v', style: MB.display(context, 44)),
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
