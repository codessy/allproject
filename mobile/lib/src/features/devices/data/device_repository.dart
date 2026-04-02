import '../../../core/networking/api_client.dart';

class DeviceRegistration {
  DeviceRegistration({
    required this.platform,
    required this.pushToken,
    required this.appVersion,
  });

  final String platform;
  final String pushToken;
  final String appVersion;
}

class DeviceRepository {
  DeviceRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<void> registerDevice(DeviceRegistration registration) async {
    await _apiClient.post(
      '/v1/devices',
      data: <String, dynamic>{
        'platform': registration.platform,
        'pushToken': registration.pushToken,
        'appVersion': registration.appVersion,
      },
    );
  }
}
