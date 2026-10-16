import 'package:flutter/material.dart';
import '../services/unison_cart.dart';

/// The number below the cart counts sticks, including repeated quantities.
class UnisonCartButton extends StatefulWidget {
  const UnisonCartButton({super.key, required this.userId, this.onPressed});
  final String userId;
  final VoidCallback? onPressed;
  @override
  State<UnisonCartButton> createState() => _UnisonCartButtonState();
}

class _UnisonCartButtonState extends State<UnisonCartButton> {
  late Future<int> _count;
  void _load() {
    _count = UnisonCart(widget.userId).load().then(
      (rows) => rows.fold<int>(0, (sum, row) => sum + (row['quantity'] as int)),
    );
  }

  void _changed() => setState(_load);
  @override
  void initState() {
    super.initState();
    _load();
    UnisonCart.changes.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant UnisonCartButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) _load();
  }

  @override
  void dispose() {
    UnisonCart.changes.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<int>(
    future: _count,
    builder: (context, snapshot) {
      final label = snapshot.hasError ? '?' : '${snapshot.data ?? '…'}';
      return TextButton(
        onPressed: widget.onPressed,
        child: Tooltip(
          message: 'Shopping cart · $label sticks',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.shopping_cart_outlined),
              Text(label, style: const TextStyle(fontSize: 11, height: 1.1)),
            ],
          ),
        ),
      );
    },
  );
}
