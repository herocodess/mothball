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

class CacheInfo {
  CacheInfo({required this.id, required this.name, required this.policy, required this.bytes, required this.how, required this.blocked});

  factory CacheInfo.fromJson(Map<String, dynamic> j) => CacheInfo(
        id: _str(j['id']),
        name: _str(j['name']),
        policy: _str(j['policy']),
        bytes: _int(j['bytes']),
        how: _str(j['how']),
        blocked: _str(j['blocked']),
      );

  final String id;
  final String name;
  final String policy; // auto, ask or report
  final int bytes;
  final String how;
  final String blocked;

  bool get canClean => policy != 'report' && blocked.isEmpty;
}

class CacheResult {
  CacheResult({required this.id, required this.name, required this.bytes, required this.error});

  factory CacheResult.fromJson(Map<String, dynamic> j) =>
      CacheResult(id: _str(j['id']), name: _str(j['name']), bytes: _int(j['bytes']), error: _str(j['error']));

  final String id;
  final String name;
  final int bytes;
  final String error;
}

class ScanSummary {
  ScanSummary({
    required this.at,
    required this.projects,
    required this.idle,
    required this.idleBytes,
    this.caches = const [],
    this.cacheBytes = 0,
  });

  factory ScanSummary.fromJson(Map<String, dynamic> j) => ScanSummary(
        at: _time(j['at']),
        projects: _int(j['projects']),
        idle: _list(j['idle']).map((e) => Candidate.fromJson(e as Map<String, dynamic>)).toList(),
        idleBytes: _int(j['idleBytes']),
        caches: _list(j['caches']).map((e) => CacheInfo.fromJson(e as Map<String, dynamic>)).toList(),
        cacheBytes: _int(j['cacheBytes']),
      );

  final DateTime? at;
  final int projects;
  final List<Candidate> idle;
  final int idleBytes;
  final List<CacheInfo> caches;
  final int cacheBytes;
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

class AccessInfo {
  AccessInfo({required this.fullDisk, required this.skipped, required this.executable});

  factory AccessInfo.fromJson(Map<String, dynamic> j) => AccessInfo(
        // Older services do not report access; treat that as granted.
        fullDisk: j.isEmpty ? true : _bool(j['fullDisk']),
        skipped: _list(j['skipped']).map((e) => e.toString()).toList(),
        executable: _str(j['executable']),
      );

  final bool fullDisk;
  final List<String> skipped;
  final String executable;
}

class MothballConfig {
  MothballConfig({
    required this.roots,
    required this.idleDays,
    required this.autopilot,
    required this.targetFreeGB,
    required this.autoEmptyDays,
    required this.checkMinutes,
    this.onboarded = false,
  });

  factory MothballConfig.fromJson(Map<String, dynamic> j) => MothballConfig(
        roots: _list(j['roots']).map((e) => e.toString()).toList(),
        idleDays: _int(j['idleDays']),
        autopilot: _bool(j['autopilot']),
        targetFreeGB: _int(j['targetFreeGB']),
        autoEmptyDays: _int(j['autoEmptyDays']),
        checkMinutes: _int(j['checkMinutes']),
        onboarded: _bool(j['onboarded']),
      );

  final List<String> roots;
  final int idleDays;
  final bool autopilot;
  final int targetFreeGB;
  final int autoEmptyDays;
  final int checkMinutes;
  final bool onboarded;

  MothballConfig copyWith({
    List<String>? roots,
    int? idleDays,
    bool? autopilot,
    int? targetFreeGB,
    int? autoEmptyDays,
    bool? onboarded,
  }) =>
      MothballConfig(
        roots: roots ?? this.roots,
        idleDays: idleDays ?? this.idleDays,
        autopilot: autopilot ?? this.autopilot,
        targetFreeGB: targetFreeGB ?? this.targetFreeGB,
        autoEmptyDays: autoEmptyDays ?? this.autoEmptyDays,
        checkMinutes: checkMinutes,
        onboarded: onboarded ?? this.onboarded,
      );

  Map<String, dynamic> toJson() => {
        'roots': roots,
        'idleDays': idleDays,
        'autopilot': autopilot,
        'targetFreeGB': targetFreeGB,
        'autoEmptyDays': autoEmptyDays,
        'checkMinutes': checkMinutes,
        'onboarded': onboarded,
      };
}

class Status {
  Status({
    required this.access,
    this.scanning = false,
    required this.freeBytes,
    required this.targetBytes,
    required this.waitingBytes,
    required this.config,
    required this.lastScan,
    required this.mothballed,
    required this.events,
  });

  factory Status.fromJson(Map<String, dynamic> j) => Status(
        access: AccessInfo.fromJson((j['access'] as Map<String, dynamic>?) ?? const {}),
        scanning: _bool(j['scanning']),
        freeBytes: _int(j['freeBytes']),
        targetBytes: _int(j['targetBytes']),
        waitingBytes: _int(j['waitingBytes']),
        config: MothballConfig.fromJson((j['config'] as Map<String, dynamic>?) ?? const {}),
        lastScan: j['lastScan'] is Map<String, dynamic> ? ScanSummary.fromJson(j['lastScan'] as Map<String, dynamic>) : null,
        mothballed: _list(j['mothballed']).map((e) => MothballedProject.fromJson(e as Map<String, dynamic>)).toList(),
        events: _list(j['events']).map((e) => ServiceEvent.fromJson(e as Map<String, dynamic>)).toList(),
      );

  final AccessInfo access;
  final bool scanning; // the service is scanning on its own
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
