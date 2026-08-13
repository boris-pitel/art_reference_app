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
  static const String _preferenceKey = 'saved_aspect_ratios_v1';

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

  Future<void> remove(String key) async {
    final ratios = await load();
    await _write(ratios.where((ratio) => ratio.key != key).toList());
  }

  Future<void> _write(List<SavedAspectRatio> ratios) async {
    await (await SharedPreferences.getInstance()).setString(
      _preferenceKey,
      jsonEncode(ratios.map((ratio) => ratio.toJson()).toList()),
    );
  }
}
