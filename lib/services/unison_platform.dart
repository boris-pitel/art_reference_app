import 'package:flutter/foundation.dart';

bool get unisonPlatformAvailable =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.iOS);
