const String appVersion = '1.2.0+63';

String get appVersionLabel {
  final parts = appVersion.split('+');
  return parts.length == 2
      ? 'Version ${parts[0]} (Build ${parts[1]})'
      : 'Version $appVersion';
}
