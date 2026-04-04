/// Non-web: unused (guarded by [kIsWeb]).
Future<bool> requestDomNotificationPermission() async => false;

bool browserNotificationPermissionIsGranted() => false;

bool browserNotificationPermissionIsDenied() => false;

String describeBrowserNotificationPermission() => 'Unknown';
