import '../network/api_client.dart';

class RealtimeConfig {
  const RealtimeConfig._();

  static const bool enabled = bool.fromEnvironment(
    'REALTIME_ENABLED',
    defaultValue: true,
  );
  static const String appKey = String.fromEnvironment(
    'REVERB_APP_KEY',
    defaultValue: 'tjoerah-reverb-key',
  );
  static const String _definedHost = String.fromEnvironment('REVERB_HOST');
  static const String _definedPort = String.fromEnvironment('REVERB_PORT');
  static const String _definedScheme = String.fromEnvironment('REVERB_SCHEME');

  static Uri get _apiUri => Uri.parse(ApiClient.baseUrl);

  static bool get encrypted =>
      (_definedScheme.isEmpty ? _apiUri.scheme : _definedScheme)
          .toLowerCase() ==
      'https';

  static String get host => _definedHost.isEmpty ? _apiUri.host : _definedHost;

  static int get port => int.tryParse(_definedPort) ?? (encrypted ? 443 : 8080);

  static String get authEndpoint => _apiUri
      .replace(path: '/broadcasting/auth', query: null, fragment: null)
      .toString();
}
