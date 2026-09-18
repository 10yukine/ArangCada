import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Android owns the settings for both foreground local alerts and background
/// FCM notification payloads. Local Hive flags cannot mute the latter.
class NotificationSettingsTile extends StatefulWidget {
  const NotificationSettingsTile({super.key});

  @override
  State<NotificationSettingsTile> createState() =>
      _NotificationSettingsTileState();
}

class _NotificationSettingsTileState extends State<NotificationSettingsTile>
    with WidgetsBindingObserver {
  final _android = AndroidFlutterLocalNotificationsPlugin();
  static const _timeout = Duration(seconds: 10);
  late Future<bool?> _permission;
  bool _opening = false;
  bool _openFailed = false;

  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _permission = _readPermission();
  }

  Future<bool?> _readPermission() async {
    if (!_supported) return null;
    try {
      return await _android.areNotificationsEnabled().timeout(_timeout);
    } on Exception {
      return null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _supported) {
      setState(() {
        _permission = _readPermission();
      });
    }
  }

  Future<void> _openSettings() async {
    if (_opening || !_supported) return;
    setState(() {
      _opening = true;
      _openFailed = false;
    });
    var opened = false;
    try {
      opened =
          await _android.openAppNotificationSettings().timeout(_timeout) ??
          false;
    } on Exception {
      // Missing plugin, unsupported device settings, or a platform failure.
    }
    if (!mounted) return;
    setState(() {
      _opening = false;
      _openFailed = !opened;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool?>(
    future: _permission,
    builder: (context, snapshot) {
      final subtitle = !_supported
          ? 'Push notifications are available in the Android app.'
          : _openFailed
          ? 'Could not open notification settings. Tap to try again.'
          : snapshot.connectionState != ConnectionState.done
          ? 'Checking Android notification permission…'
          : switch (snapshot.data) {
              true =>
                'Allowed by Android. Individual alerts may still be muted in settings.',
              false =>
                'Blocked by Android. Tap to review notification settings.',
              null =>
                'Permission status unavailable. Tap to check Android settings.',
            };
      return ListTile(
        leading: const Icon(Icons.notifications_outlined),
        title: const Text('Notification settings'),
        subtitle: Text(subtitle),
        trailing: !_supported
            ? null
            : _opening
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.open_in_new),
        onTap: _supported && !_opening ? _openSettings : null,
      );
    },
  );
}
