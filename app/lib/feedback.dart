import 'dart:ffi' show Abi;
import 'dart:io';

/// Links that open a new GitHub issue with this copy of Mothball's version,
/// system and chip already filled in. Nothing is sent anywhere until the
/// person submits the issue themselves.
class FeedbackLinks {
  static const _repo = 'https://github.com/herocodess/mothball';

  /// A bug report, prefilled.
  static String bugReport(String version) => _issue('bug_report.yml', version);

  /// A request for a stack or cache Mothball doesn't know yet, prefilled.
  static String newStack(String version) => _issue('new_stack.yml', version);

  static String _issue(String template, String version) => Uri.parse('$_repo/issues/new').replace(queryParameters: {
        'template': template,
        if (version.isNotEmpty) 'version': version,
        'os': systemName(),
        'chip': chipName(),
      }).toString();

  /// The operating system and its version, for example "macOS 15.1",
  /// "Windows 11 (build 26100)" or "Ubuntu 24.04.1 LTS".
  static String systemName() {
    final v = Platform.operatingSystemVersion;
    if (Platform.isMacOS) {
      final m = RegExp(r'(\d+(?:\.\d+)+)').firstMatch(v);
      return m == null ? 'macOS' : 'macOS ${m.group(1)}';
    }
    if (Platform.isWindows) {
      final build = int.tryParse(RegExp(r'Build (\d+)').firstMatch(v)?.group(1) ?? '');
      if (build == null) return 'Windows';
      // Windows 11 still reports itself as 10.0; the build number tells them apart.
      return '${build >= 22000 ? 'Windows 11' : 'Windows 10'} (build $build)';
    }
    if (Platform.isLinux) {
      try {
        for (final line in File('/etc/os-release').readAsLinesSync()) {
          if (line.startsWith('PRETTY_NAME=')) {
            return line.substring(12).replaceAll('"', '').trim();
          }
        }
      } catch (_) {}
      return 'Linux';
    }
    return Platform.operatingSystem;
  }

  /// The processor family, in the words people use for it.
  static String chipName() {
    final abi = Abi.current();
    final arm = abi == Abi.macosArm64 || abi == Abi.windowsArm64 || abi == Abi.linuxArm64;
    if (Platform.isMacOS) return arm ? 'Apple silicon' : 'Intel';
    return arm ? 'Arm64' : 'x64 (Intel or AMD)';
  }
}
