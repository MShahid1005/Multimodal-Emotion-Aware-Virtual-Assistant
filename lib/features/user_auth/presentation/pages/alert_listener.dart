import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class AlertListener extends StatefulWidget {
  @override
  _AlertListenerState createState() => _AlertListenerState();
}

class _AlertListenerState extends State<AlertListener> {
  final databaseRef = FirebaseDatabase.instance.ref("alerts");
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _listenToAlerts();
  }

  void _initNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initializationSettings = InitializationSettings(
      android: androidSettings,
    );
    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  void _listenToAlerts() {
    databaseRef.onChildAdded.listen((event) {
      final message = event.snapshot.child('message').value?.toString() ?? "";
      if (message.isNotEmpty) {
        _showNotification("Sad Emotion Detected", message);
      }
    });
  }

  void _showNotification(String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      'channelId',
      'Emotion Alerts',
      importance: Importance.high,
      priority: Priority.high,
    );
    const notificationDetails = NotificationDetails(android: androidDetails);
    await flutterLocalNotificationsPlugin.show(
      0,
      title,
      body,
      notificationDetails,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Emotion Monitor")),
      body: Center(child: Text("Listening for emotion alerts...")),
    );
  }
}
