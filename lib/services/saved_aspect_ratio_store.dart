import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/saved_aspect_ratio.dart';

enum SaveAspectRatioStatus { added, duplicate, limitReached }

class SaveAspectRatioResult {
  const SaveAspectRatioResult(this.status, this.ratio);

  final SaveAspectRatioStatus status;
  final SavedAspectRatio ratio;
}

class SavedAspectRatioStore {
  const SavedAspectRatioStore();

  static const int maximumRatios = 10;
  static const int maximumRecentRatios = 5;
  static const String _preferenceKey = 'saved_aspect_ratios_v1';
  static const String _recentPreferenceKey = 'recent_aspect_ratios_v1';

  Future<List<SavedAspectRatio>> load() async {
    final encoded = (await SharedPreferences.getInstance()).getString(
      _preferenceKey,
    );
    if (encoded == null) return const [];
    try {
      final values = jsonDecode(encoded) as List<dynamic>;
      return values
          .whereType<Map>()
          .map(
            (value) =>
                SavedAspectRatio.fromJson(Map<String, dynamic>.from(value)),
          )
          .where(
            (ratio) =>
                ratio.width.isFinite &&
                ratio.height.isFinite &&
                ratio.width > 0 &&
                ratio.height > 0,
          )
          .take(maximumRatios)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<SaveAspectRatioResult> add(SavedAspectRatio ratio) async {
    final ratios = await load();
    for (final existing in ratios) {
      if (existing.hasSameProportion(ratio)) {
        return SaveAspectRatioResult(SaveAspectRatioStatus.duplicate, existing);
      }
    }
    if (ratios.length >= maximumRatios) {
      return SaveAspectRatioResult(SaveAspectRatioStatus.limitReached, ratio);
    }
    final updated = [...ratios, ratio];
    await _write(updated);
    return SaveAspectRatioResult(SaveAspectRatioStatus.added, ratio);
  }

  Future<List<SavedAspectRatio>> loadRecent() =>
      _loadFrom(_recentPreferenceKey, maximumRecentRatios);

  /// Remembers a ratio when it is actually applied, newest first.
  ///
  /// Proportional duplicates are removed so 3:2 and 6:4 do not occupy two
  /// history slots. The latest numbers are retained because they are the ones
  /// the person most recently chose.
  Future<List<SavedAspectRatio>> rememberRecent(SavedAspectRatio ratio) async {
    final recent = await loadRecent();
    final updated = <SavedAspectRatio>[
      ratio,
      ...recent.where((existing) => !existing.hasSameProportion(ratio)),
    ].take(maximumRecentRatios).toList(growable: false);
    await _writeTo(_recentPreferenceKey, updated);
    return updated;
  }

  Future<void> remove(String key) async {
    final ratios = await load();
    await _write(ratios.where((ratio) => ratio.key != key).toList());
  }

  Future<void> _write(List<SavedAspectRatio> ratios) async {
    await _writeTo(_preferenceKey, ratios);
  }

  Future<List<SavedAspectRatio>> _loadFrom(String key, int limit) async {
    final encoded = (await SharedPreferences.getInstance()).getString(key);
    if (encoded == null) return const [];
    try {
      final values = jsonDecode(encoded) as List<dynamic>;
      return values
          .whereType<Map>()
          .map(
            (value) =>
                SavedAspectRatio.fromJson(Map<String, dynamic>.from(value)),
          )
          .where(
            (ratio) =>
                ratio.width.isFinite &&
                ratio.height.isFinite &&
                ratio.width > 0 &&
                ratio.height > 0,
          )
          .take(limit)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _writeTo(String key, List<SavedAspectRatio> ratios) async {
    await (await SharedPreferences.getInstance()).setString(
      key,
      jsonEncode(ratios.map((ratio) => ratio.toJson()).toList()),
    );
  }
}
