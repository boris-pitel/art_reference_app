List<Map<String, dynamic>> searchUnisonCatalogue(
  List<Map<String, dynamic>> rows,
  String query,
) {
  final words = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty);
  return rows.where((row) {
    final text = [
      'brand',
      'code',
      'printed_code',
      'retailer_sku',
      'display_name',
      'approximate_name',
    ].map((key) => row[key] ?? '').join(' ').toLowerCase();
    return words.every(text.contains);
  }).toList();
}

int compareUnisonCodes(Map<String, dynamic> a, Map<String, dynamic> b) {
  final pattern = RegExp(r'^(.*?)(\d+)$');
  final left = '${a['code']}', right = '${b['code']}';
  final l = pattern.firstMatch(left), r = pattern.firstMatch(right);
  if (l != null && r != null) {
    final prefix = l[1]!.compareTo(r[1]!);
    if (prefix != 0) return prefix;
    return int.parse(l[2]!).compareTo(int.parse(r[2]!));
  }
  return left.compareTo(right);
}
