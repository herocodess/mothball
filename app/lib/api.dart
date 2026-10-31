import 'dart:convert';
import 'dart:io';

import 'models.dart';

/// Thrown when the background service is not running or cannot be reached.
class ServiceUnavailable implements Exception {
  ServiceUnavailable(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

/// Where Mothball keeps its state. Must match os.UserConfigDir() in Go.
String stateDir() {
  final env = Platform.environment;
  final override = env['MOTHBALL_STATE_DIR'];
  if (override != null && override.isNotEmpty) return override;
  if (Platform.isMacOS) {
    return '${env['HOME']}/Library/Application Support/mothball';
  }
  if (Platform.isWindows) {
    return '${env['APPDATA']}\\mothball';
  }
  final xdg = env['XDG_CONFIG_HOME'];
  if (xdg != null && xdg.isNotEmpty) return '$xdg/mothball';
  return '${env['HOME']}/.config/mothball';
}

/// Talks to the Mothball background service over its local, token-protected
/// API. The app never touches project files itself.
class MothballApi {
  MothballApi({String? dir}) : _dir = dir ?? stateDir();

  final String _dir;
  final HttpClient _http = HttpClient()..connectionTimeout = const Duration(seconds: 3);

  Future<({Uri base, String token})> _endpoint() async {
    final file = File('$_dir${Platform.pathSeparator}service.json');
    if (!await file.exists()) {
      throw ServiceUnavailable('The Mothball service is not running.');
    }
    final j = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    return (base: Uri.parse(j['url'] as String), token: j['token'] as String);
  }

  Future<Object?> _call(String method, String path, [Object? body]) async {
    final ep = await _endpoint();
    try {
      final req = await _http.openUrl(method, ep.base.resolve(path));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${ep.token}');
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) {
        throw HttpException('${res.statusCode}: ${text.trim()}');
      }
      return text.isEmpty ? null : jsonDecode(text);
    } on SocketException {
      throw ServiceUnavailable('The Mothball service is not responding.');
    }
  }

  Future<Status> status() async => Status.fromJson((await _call('GET', '/v1/status')) as Map<String, dynamic>);

  Future<ScanSummary> scan() async => ScanSummary.fromJson((await _call('POST', '/v1/scan')) as Map<String, dynamic>);

  /// Puts away the given folders, or every idle folder when [paths] is empty.
  Future<List<CleanResult>> clean([List<String> paths = const []]) async {
    final res = await _call('POST', '/v1/clean', {'paths': paths});
    return res is List ? res.map((e) => CleanResult.fromJson(e as Map<String, dynamic>)).toList() : const [];
  }

  Future<List<CacheResult>> cleanCaches(List<String> ids) async {
    final res = await _call('POST', '/v1/caches/clean', {'ids': ids});
    return res is List ? res.map((e) => CacheResult.fromJson(e as Map<String, dynamic>)).toList() : const [];
  }

  Future<void> wake(String project) async {
    await _call('POST', '/v1/wake', {'project': project});
  }

  Future<MothballConfig> saveConfig(MothballConfig c) async =>
      MothballConfig.fromJson((await _call('PUT', '/v1/config', c.toJson())) as Map<String, dynamic>);

  /// Starts the service at login using the mothball CLI on PATH.
  static Future<String?> installService() async {
    try {
      final r = await Process.run('mothball', ['service', 'install'], runInShell: true);
      return r.exitCode == 0 ? null : '${r.stderr}'.trim();
    } on ProcessException {
      return 'The mothball command was not found. Install the CLI first.';
    }
  }
}
