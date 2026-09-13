import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  String? _listeningUid;
  StreamSubscription<DatabaseEvent>? _notifSub;

  static const String channelId = 'chat_messages';
  static const String channelName = 'Chat Messages';
  static const String channelDesc = 'Notifications for chat messages';

  /// Initialize local notification plugin and setup default channels
  Future<void> initialize() async {
    if (_isInitialized) return;

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    await _localNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint("Notification clicked with payload: ${response.payload}");
      },
    );

    // Create high importance notification channel for Android heads-up banners
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDesc,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    final androidImplementation = _localNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      await androidImplementation.createNotificationChannel(channel);
    }

    _isInitialized = true;
  }

  /// Request system notification permissions (Android 13+ prompt)
  Future<bool> requestPermission() async {
    final androidImplementation = _localNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      final granted =
          await androidImplementation.requestNotificationsPermission();
      return granted ?? false;
    }
    return true;
  }

  /// Start listening for incoming notifications for the active user
  void startListening(String uid) {
    if (_listeningUid == uid && _notifSub != null) return;
    stopListening();

    _listeningUid = uid;
    final notifsRef = FirebaseDatabase.instance.ref("notifications/$uid");

    // Listen only to child additions to avoid re-triggering historical notifications
    final startTime = DateTime.now().millisecondsSinceEpoch - 5000;

    _notifSub = notifsRef.onChildAdded.listen((event) async {
      if (!event.snapshot.exists) return;
      final raw = event.snapshot.value;
      if (raw is! Map) return;

      final data = Map<String, dynamic>.from(raw);
      final isRead = data['isRead'] == true;
      final isArchived = data['isArchived'] == true;
      if (isRead || isArchived) return;

      final ts = data['timestamp'];
      int msgTime = 0;
      if (ts is int) {
        msgTime = ts;
      } else if (ts is double) {
        msgTime = ts.toInt();
      }

      // Only trigger notification pop-up for recent messages
      if (msgTime > 0 && msgTime < startTime) return;

      final title = data['title']?.toString() ?? 'New Message';
      final body = data['message']?.toString() ?? '';
      final senderUid = data['senderUid']?.toString();

      // Retrieve sender profile picture if available
      String? avatarUrl;
      if (senderUid != null && senderUid.isNotEmpty) {
        try {
          final uSnap =
              await FirebaseDatabase.instance.ref("users/$senderUid").get();
          if (uSnap.exists && uSnap.value is Map) {
            final uMap = uSnap.value as Map;
            avatarUrl = uMap['profilePicUrl']?.toString();
          } else {
            final pSnap =
                await FirebaseDatabase.instance.ref("properties/$senderUid").get();
            if (pSnap.exists && pSnap.value is Map) {
              final pMap = pSnap.value as Map;
              final imgs = pMap['imageUrls'];
              if (imgs is List && imgs.isNotEmpty) {
                avatarUrl = imgs[0].toString();
              }
            }
          }
        } catch (e) {
          debugPrint("Error loading sender avatar: $e");
        }
      }

      await showChatNotification(
        title: title,
        body: body,
        avatarUrl: avatarUrl,
        payload: data['chatId']?.toString(),
      );
    });
  }

  /// Stop listening for user notifications
  void stopListening() {
    _notifSub?.cancel();
    _notifSub = null;
    _listeningUid = null;
  }

  /// Displays an Android push notification banner with avatar, sender name, and message preview
  Future<void> showChatNotification({
    required String title,
    required String body,
    String? avatarUrl,
    String? payload,
  }) async {
    ByteArrayAndroidBitmap? largeIconBitmap;

    if (avatarUrl != null && avatarUrl.isNotEmpty && avatarUrl.startsWith('http')) {
      try {
        final res = await http.get(Uri.parse(avatarUrl)).timeout(
              const Duration(seconds: 4),
            );
        if (res.statusCode == 200) {
          largeIconBitmap = ByteArrayAndroidBitmap(res.bodyBytes);
        }
      } catch (e) {
        debugPrint("Could not download avatar for notification: $e");
      }
    }

    final BigTextStyleInformation bigTextStyleInformation =
        BigTextStyleInformation(
      body,
      contentTitle: title,
      summaryText: 'Chat',
    );

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'New message',
      icon: '@mipmap/ic_launcher',
      largeIcon: largeIconBitmap,
      styleInformation: bigTextStyleInformation,
      playSound: true,
      enableVibration: true,
      showWhen: true,
    );

    final NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidDetails);

    final int id = DateTime.now().millisecondsSinceEpoch.remainder(100000);

    await _localNotificationsPlugin.show(
      id,
      title,
      body,
      platformChannelSpecifics,
      payload: payload,
    );
  }
}
