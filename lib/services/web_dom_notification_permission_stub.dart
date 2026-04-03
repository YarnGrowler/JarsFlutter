/// Non-web: unused (guarded by [kIsWeb]).
Future<bool> requestDomNotificationPermission() async => false;

bool browserNotificationPermissionIsGranted() => false;
