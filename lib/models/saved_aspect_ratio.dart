class SavedAspectRatio {
  const SavedAspectRatio({required this.width, required this.height});

  final double width;
  final double height;

  double get value => width / height;
  String get key => '${_number(width)}x${_number(height)}';
  String get label => '${_number(width)}:${_number(height)} — Saved';

  Map<String, Object> toJson() => {'width': width, 'height': height};

  factory SavedAspectRatio.fromJson(Map<String, dynamic> json) {
    return SavedAspectRatio(
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
    );
  }

  bool hasSameProportion(SavedAspectRatio other) {
    return (value - other.value).abs() < 0.000001;
  }

  static String _number(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}
