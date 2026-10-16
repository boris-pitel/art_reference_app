import 'package:flutter/material.dart';

class DakotaCartScreen extends StatelessWidget {
  const DakotaCartScreen({super.key, required this.items});
  final List<Map<String, dynamic>> items;
  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Text('Dakota transfer is available in the Windows app.'),
    ),
  );
}
