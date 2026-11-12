// Text the background service sends in English, shown in the app's
// language: cache names and descriptions by cache id, and activity details by
// event code. Anything new the app doesn't know yet falls back to the
// service's own English text.
//
// The cache cases mirror core/caches/caches.go; test/service_words_test.dart
// checks that every cache there has a case here.

import 'package:flutter/widgets.dart';

import 'language.dart';
import 'models.dart';

/// A cache's name, like "Chrome cache", in the current language.
String cacheName(BuildContext context, String id, String fallback) {
  final t = context.t;
  return switch (id) {
        'xcode-derived-data' => t.cacheXcodeDerivedDataName,
        'simulator-caches' => t.cacheSimulatorCachesName,
        'simulators-unavailable' => t.cacheSimulatorsUnavailableName,
        'xcode-device-support' => t.cacheXcodeDeviceSupportName,
        'npm' => t.cacheNpmName,
        'yarn' => t.cacheYarnName,
        'pnpm' => t.cachePnpmName,
        'bun' => t.cacheBunName,
        'pip' => t.cachePipName,
        'uv' => t.cacheUvName,
        'cocoapods' => t.cacheCocoapodsName,
        'homebrew' => t.cacheHomebrewName,
        'gradle' => t.cacheGradleName,
        'go-modules' => t.cacheGoModulesName,
        'pub' => t.cachePubName,
        'cargo' => t.cacheCargoName,
        'android-emulators' => t.cacheAndroidEmulatorsName,
        'vscode' => t.cacheVscodeName,
        'cursor' => t.cacheCursorName,
        'slack' => t.cacheSlackName,
        'chrome' => t.cacheChromeName,
        'edge' => t.cacheEdgeName,
        'brave' => t.cacheBraveName,
        'firefox' => t.cacheFirefoxName,
        'teams' => t.cacheTeamsName,
        'discord' => t.cacheDiscordName,
        'notion' => t.cacheNotionName,
        'figma' => t.cacheFigmaName,
        'obsidian' => t.cacheObsidianName,
        'claude' => t.cacheClaudeName,
    _ => fallback,
  };
}

/// What cleaning a cache does, in the current language.
String cacheHow(BuildContext context, CacheInfo c) {
  final t = context.t;
  final trash = toTrash(context);
  return switch (c.id) {
        'xcode-derived-data' => t.cacheXcodeDerivedDataHow(trash),
        'simulator-caches' => t.cacheSimulatorCachesHow(trash),
        'simulators-unavailable' => t.cacheSimulatorsUnavailableHow,
        'xcode-device-support' => t.cacheXcodeDeviceSupportHow(trash),
        'npm' => t.cacheNpmHow,
        'yarn' => t.cacheYarnHow,
        'pnpm' => t.cachePnpmHow,
        'bun' => t.cacheBunHow,
        'pip' => t.cachePipHow,
        'uv' => t.cacheUvHow,
        'cocoapods' => t.cacheCocoapodsHow,
        'homebrew' => t.cacheHomebrewHow,
        'gradle' => t.cacheGradleHow(trash),
        'go-modules' => t.cacheGoModulesHow,
        'pub' => t.cachePubHow,
        'cargo' => t.cacheCargoHow,
        'android-emulators' => t.cacheAndroidEmulatorsHow,
        'vscode' => t.cacheVscodeHow(trash),
        'cursor' => t.cacheCursorHow(trash),
        'slack' => t.cacheSlackHow(trash),
        'chrome' => t.cacheChromeHow(trash),
        'edge' => t.cacheEdgeHow(trash),
        'brave' => t.cacheBraveHow(trash),
        'firefox' => t.cacheFirefoxHow(trash),
        'teams' => t.cacheTeamsHow(trash),
        'discord' => t.cacheDiscordHow(trash),
        'notion' => t.cacheNotionHow(trash),
        'figma' => t.cacheFigmaHow(trash),
        'obsidian' => t.cacheObsidianHow(trash),
        'claude' => t.cacheClaudeHow(trash),
    _ => c.how,
  };
}

/// Why a cache can't be cleaned right now, or '' when it can.
String cacheWaiting(BuildContext context, CacheInfo c) {
  final t = context.t;
  if (c.blockedBy.isNotEmpty) return t.cacheWaitingOpen(c.blockedBy);
  if (c.missingTool.isNotEmpty) return t.cacheWaitingMissing(c.missingTool);
  if (c.blocked.isNotEmpty) return t.cacheWaiting(c.blocked); // an older service
  return '';
}

/// The detail line under an activity entry.
String eventDetail(BuildContext context, ServiceEvent e) {
  final t = context.t;
  return switch (e.code) {
    'putAwayEmptiesLater' => t.eventPutAwayEmptiesLater,
    'putAwayEmptyTrash' => t.eventPutAwayEmptyTrash(inTrash(context)),
    'cleanedCaches' => t.eventCleanedCaches,
    'nothingToPutAway' => t.eventNothingToPutAway,
    'emptied' => t.eventEmptiedDetail(inTrash(context)),
    'updateRequired' when e.arg.isNotEmpty => t.eventUpdateRequired(e.arg),
    _ => e.message, // errors carry their own message
  };
}
