// Data shapes returned by the Mothball service. They mirror the Go structs in
// core/service, core/scan, core/wake and core/config.

List<dynamic> _list(Object? v) => v is List ? v : const [];
int _int(Object? v) => v is num ? v.toInt() : 0;
bool _bool(Object? v) => v == true;
String _str(Object? v) => v is String ? v : '';
DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

class Candidate {
  Candidate({
    required this.path,
    required this.project,
    required this.pack,
    required this.bytes,
    required this.idleDays,
    required this.dirty,
    required this.wake,
  });

  factory Candidate.fromJson(Map<String, dynamic> j) => Candidate(
        path: _str(j['path']),
        project: _str(j['project']),
        pack: _str(j['pack']),
        bytes: _int(j['bytes']),
        idleDays: _int(j['idleDays']),
        dirty: _bool(j['dirty']),
        wake: _str(j['wake']),
      );

  final String path;
  final String project;
  final String pack;
  final int bytes;
  final int idleDays;
  final bool dirty;
  final String wake;
}

class ScanSummary {
  ScanSummary({required this.at, required this.projects, required this.idle, required this.idleBytes});

  factory ScanSummary.fromJson(Map<String, dynamic> j) => ScanSummary(
        at: _time(j['at']),
        projects: _int(j['projects']),
        idle: _list(j['idle']).map((e) => Candidate.fromJson(e as Map<String, dynamic>)).toList(),
        idleBytes: _int(j['idleBytes']),
      );

  final DateTime? at;
  final int projects;
  final List<Candidate> idle;
  final int idleBytes;
}

class MothballedProject {
  MothballedProject({
    required this.path,
    required this.since,
    required this.bytes,
    required this.returned,
    required this.commands,
  });

  factory MothballedProject.fromJson(Map<String, dynamic> j) => MothballedProject(
        path: _str(j['path']),
        since: _time(j['since']),
        bytes: _int(j['bytes']),
        returned: _bool(j['returned']),
        commands: _list(j['commands']).map((e) => e.toString()).toList(),
      );

  final String path;
  final DateTime? since;
  final int bytes;
  final bool returned;
  final List<String> commands;
}

class ServiceEvent {
  ServiceEvent({required this.at, required this.kind, required this.message, required this.bytes});

  factory ServiceEvent.fromJson(Map<String, dynamic> j) => ServiceEvent(
        at: _time(j['at']),
        kind: _str(j['kind']),
        message: _str(j['message']),
        bytes: _int(j['bytes']),
      );

  final DateTime? at;
  final String kind;
  final String message;
  final int bytes;
}

class MothballConfig {
  MothballConfig({
    required this.roots,
    required this.idleDays,
    required this.autopilot,
    required this.targetFreeGB,
    required this.autoEmptyDays,
    required this.checkMinutes,
  });

  factory MothballConfig.fromJson(Map<String, dynamic> j) => MothballConfig(
        roots: _list(j['roots']).map((e) => e.toString()).toList(),
        idleDays: _int(j['idleDays']),
        autopilot: _bool(j['autopilot']),
        targetFreeGB: _int(j['targetFreeGB']),
        autoEmptyDays: _int(j['autoEmptyDays']),
        checkMinutes: _int(j['checkMinutes']),
      );

  final List<String> roots;
  final int idleDays;
  final bool autopilot;
  final int targetFreeGB;
  final int autoEmptyDays;
  final int checkMinutes;

  MothballConfig copyWith({
    List<String>? roots,
    int? idleDays,
    bool? autopilot,
    int? targetFreeGB,
    int? autoEmptyDays,
  }) =>
      MothballConfig(
        roots: roots ?? this.roots,
        idleDays: idleDays ?? this.idleDays,
        autopilot: autopilot ?? this.autopilot,
        targetFreeGB: targetFreeGB ?? this.targetFreeGB,
        autoEmptyDays: autoEmptyDays ?? this.autoEmptyDays,
        checkMinutes: checkMinutes,
      );

  Map<String, dynamic> toJson() => {
        'roots': roots,
        'idleDays': idleDays,
        'autopilot': autopilot,
        'targetFreeGB': targetFreeGB,
        'autoEmptyDays': autoEmptyDays,
        'checkMinutes': checkMinutes,
      };
}

class Status {
  Status({
    required this.freeBytes,
    required this.targetBytes,
    required this.waitingBytes,
    required this.config,
    required this.lastScan,
    required this.mothballed,
    required this.events,
  });

  factory Status.fromJson(Map<String, dynamic> j) => Status(
        freeBytes: _int(j['freeBytes']),
        targetBytes: _int(j['targetBytes']),
        waitingBytes: _int(j['waitingBytes']),
        config: MothballConfig.fromJson((j['config'] as Map<String, dynamic>?) ?? const {}),
        lastScan: j['lastScan'] is Map<String, dynamic> ? ScanSummary.fromJson(j['lastScan'] as Map<String, dynamic>) : null,
        mothballed: _list(j['mothballed']).map((e) => MothballedProject.fromJson(e as Map<String, dynamic>)).toList(),
        events: _list(j['events']).map((e) => ServiceEvent.fromJson(e as Map<String, dynamic>)).toList(),
      );

  final int freeBytes;
  final int targetBytes;
  final int waitingBytes;
  final MothballConfig config;
  final ScanSummary? lastScan;
  final List<MothballedProject> mothballed;
  final List<ServiceEvent> events;
}

class CleanResult {
  CleanResult({required this.path, required this.bytes, required this.moved, required this.note});

  factory CleanResult.fromJson(Map<String, dynamic> j) => CleanResult(
        path: _str(j['path']),
        bytes: _int(j['bytes']),
        moved: _bool(j['moved']),
        note: _str(j['note']),
      );

  final String path;
  final int bytes;
  final bool moved;
  final String note;
}

/// Formats bytes the same way the CLI does: 1024-based, one decimal.
String humanBytes(int b) {
  const units = 'KMGTPE';
  if (b < 1024) return '$b B';
  var value = b / 1024;
  var i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i++;
  }
  return '${value.toStringAsFixed(1)} ${units[i]}B';
}
