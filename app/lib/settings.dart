import 'package:flutter/material.dart';

import 'models.dart';

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
    final quiet = Theme.of(context).colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(onPressed: _saving ? null : _save, child: const Text('Save')),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.all(20), children: [
            _Slider(
              label: 'A project is idle after',
              value: _c.idleDays,
              min: 7,
              max: 365,
              unit: 'days without commits',
              onChanged: (v) => setState(() => _c = _c.copyWith(idleDays: v)),
            ),
            const Divider(height: 32),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Autopilot'),
              subtitle: const Text('Put away output from the longest-idle projects when free space drops below the target'),
              value: _c.autopilot,
              onChanged: (v) => setState(() => _c = _c.copyWith(autopilot: v)),
            ),
            _Slider(
              label: 'Keep free at least',
              value: _c.targetFreeGB,
              min: 5,
              max: 500,
              unit: 'GB',
              onChanged: (v) => setState(() => _c = _c.copyWith(targetFreeGB: v)),
            ),
            const Divider(height: 32),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto-empty'),
              subtitle: const Text(
                  'Permanently empty folders Mothball put in the Trash after a grace period. Nothing else in the Trash is touched.'),
              value: _c.autoEmptyDays > 0,
              onChanged: (v) => setState(() => _c = _c.copyWith(autoEmptyDays: v ? 7 : 0)),
            ),
            if (_c.autoEmptyDays > 0)
              _Slider(
                label: 'Empty after',
                value: _c.autoEmptyDays,
                min: 1,
                max: 60,
                unit: 'days in the Trash',
                onChanged: (v) => setState(() => _c = _c.copyWith(autoEmptyDays: v)),
              ),
            const Divider(height: 32),
            Text('Folders to watch', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text('One per line. Leave empty to watch your whole home folder.', style: TextStyle(color: quiet)),
            const SizedBox(height: 8),
            TextField(
              controller: _roots,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '/Users/you/dev'),
            ),
            const SizedBox(height: 16),
            Text('Add a .mothballignore file to any project to keep Mothball out of it.', style: TextStyle(color: quiet)),
          ]),
        ),
      ),
    );
  }
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.unit,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final String unit;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(min, max);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 8),
      Text('$label $v $unit'),
      Slider(
        value: v.toDouble(),
        min: min.toDouble(),
        max: max.toDouble(),
        divisions: max - min,
        label: '$v',
        onChanged: (d) => onChanged(d.round()),
      ),
    ]);
  }
}
