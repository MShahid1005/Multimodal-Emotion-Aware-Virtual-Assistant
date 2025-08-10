import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme_notifier.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'settings_notifier.dart' as my_settings; // Create this for global settings

class SettingPage extends StatefulWidget {
  const SettingPage({super.key});

  @override
  State<SettingPage> createState() => _SettingPageState();
}

class _SettingPageState extends State<SettingPage> {
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);
    _notificationsPlugin.initialize(initializationSettings);
  }

  @override
  Widget build(BuildContext context) {
    final themeNotifier = Provider.of<ThemeNotifier>(context);
    final settingsNotifier = Provider.of<my_settings.SettingsNotifier>(context);
    final bool _isDarkMode = themeNotifier.isDarkMode;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              "App Preferences",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text("Dark Mode"),
              value: themeNotifier.isDarkMode,
              onChanged: (value) {
                themeNotifier.setDarkMode(value);
              },
              secondary: const Icon(Icons.dark_mode),
            ),
            SwitchListTile(
              title: const Text("Enable Notifications"),
              value: settingsNotifier.notificationsEnabled,
              onChanged: (value) {
                settingsNotifier.setNotificationsEnabled(value);
              },
              secondary: const Icon(Icons.notifications_active),
            ),
            SwitchListTile(
              title: const Text("Enable Sound"),
              value: settingsNotifier.soundEnabled,
              onChanged: (value) {
                settingsNotifier.setSoundEnabled(value);
              },
              secondary: const Icon(Icons.volume_up),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              icon: const Icon(Icons.home),
              onPressed: () {
                Navigator.pop(context);
              },
              label: const Text("Back to Home"),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isDarkMode ? Colors.black : Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(fontSize: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.notifications),
              onPressed: settingsNotifier.notificationsEnabled ? _sendNotification : null,
              label: const Text("Send Test Notification"),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isDarkMode ? Colors.grey[800] : Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(fontSize: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendNotification() async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'your_channel_id',
          'your_channel_name',
          channelDescription: 'your_channel_description',
          importance: Importance.max,
          priority: Priority.high,
          showWhen: false,
        );
    const NotificationDetails notificationDetails =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    final settings = Provider.of<my_settings.SettingsNotifier>(context, listen: false);
    if (!settings.notificationsEnabled) return; // ✅ Check for notifications

    await _notificationsPlugin.show(
      0,
      'Title',
      'Message',
      notificationDetails,
    );

    if (settings.soundEnabled) {
      // ✅ Play sound if enabled
      // Example: play a beep or custom sound
    }
  }
}
