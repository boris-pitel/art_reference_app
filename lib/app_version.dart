const String appVersion = '1.2.2+101';

String get appVersionLabel {
  final parts = appVersion.split('+');
  return parts.length == 2
      ? 'Version ${parts[0]} (Build ${parts[1]})'
      : 'Version $appVersion';
}
