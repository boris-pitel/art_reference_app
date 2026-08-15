import 'package:flutter/widgets.dart';

/// Shared with [ImpersonationController] so it can reset navigation back to
/// the root screen without needing a BuildContext of its own.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
