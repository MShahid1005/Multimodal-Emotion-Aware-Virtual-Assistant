// ...existing imports...
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'settings_notifier.dart'; // Create this for global settings
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Example SettingsNotifier for Provider
class SettingsNotifier extends ChangeNotifier {
  bool _notificationsEnabled = true;
  bool _soundEnabled = true;

  bool get notificationsEnabled => _notificationsEnabled;
  bool get soundEnabled => _soundEnabled;

  void setNotificationsEnabled(bool value) {
    _notificationsEnabled = value;
    notifyListeners();
  }

  void setSoundEnabled(bool value) {
    _soundEnabled = value;
    notifyListeners();
  }
}

// Import the plugin at the top of your file:
// import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// Initialize the notifications plugin
final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

// In your notification logic:
void _showDominantEmotionNotification(String emotion, String recommendation, BuildContext context) async {
  final settings = Provider.of<SettingsNotifier>(context, listen: false);
  if (!settings.notificationsEnabled) return; // ✅ Check for notifications

  // ...notification details...
  final AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
    'your_channel_id',
    'Your Channel Name',
    channelDescription: 'Your channel description',
    importance: Importance.max,
    priority: Priority.high,
    playSound: settings.soundEnabled,
  );
  final NotificationDetails notificationDetails =
      NotificationDetails(android: androidPlatformChannelSpecifics);

  await _notificationsPlugin.show(
    0,
    'Dominant Emotion',
    'You seem mostly $emotion.\n$recommendation',
    notificationDetails,
  );

  if (settings.soundEnabled) {
    // ✅ Play sound if enabled
    // Example: play a beep or custom sound
  }
}

// In your SettingPage, use Provider to toggle these:
// Place the following inside a widget's build method where BuildContext context is available:
class SettingPage extends StatelessWidget {
  const SettingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsNotifier>(context);

    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: SwitchListTile(
        title: const Text("Enable Notifications"),
        value: settings.notificationsEnabled,
        onChanged: (value) => settings.setNotificationsEnabled(value),
      ),
    );
  }
}