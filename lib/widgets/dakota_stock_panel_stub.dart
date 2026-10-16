import 'package:flutter/material.dart';
import '../services/dakota_stock.dart';

class DakotaStockPanel extends StatelessWidget {
  const DakotaStockPanel({super.key, required this.onChanged});
  final ValueChanged<Map<String, DakotaStock>> onChanged;
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
