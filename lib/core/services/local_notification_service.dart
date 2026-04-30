import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationService {
  LocalNotificationService._();

  static final LocalNotificationService instance = LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'channel_id',
    'channel_name',
    description: 'CipherChat incoming message alerts',
    importance: Importance.high,
  );

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_cipherchat'),
      iOS: DarwinInitializationSettings(),
    );

    await _plugin.initialize(settings);

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    _initialized = true;
  }

  Future<void> showIncomingMessage({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialized) {
      return;
    }

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'channel_id',
        'channel_name',
        channelDescription: 'CipherChat incoming message alerts',
        importance: Importance.max,
        priority: Priority.high,
        icon: 'ic_cipherchat',
      ),
      iOS: DarwinNotificationDetails(),
    );

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: payload,
    );
  }
}
