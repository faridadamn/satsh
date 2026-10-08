import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'agent/agent.dart';
import 'agent/brain.dart';
import 'agent/mission.dart';
import 'phone_server.dart';
import 'ssh_manager.dart';
import 'store.dart';

@pragma('vm:entry-point')
void keepAliveCallback() => FlutterForegroundTask.setTaskHandler(_Idle());

class _Idle extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}
  @override
  void onRepeatEvent(DateTime timestamp) {}
  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

/// Runs an Android foreground service (with a notification) while any SSH
/// session or tunnel is open, so Android doesn't kill the connections when
/// the app is in the background.
class KeepAliveService {
  KeepAliveService._();
  static final KeepAliveService i = KeepAliveService._();
  bool _running = false;
  bool _busy = false;
  String _last = '';
  String? _event;

  /// Shows a one-line event (e.g. a finished cron job) in the notification.
  Future<void> notify(String title, String body) async {
    _event = '$title: $body';
    if (_running) {
      try {
        _last = _text();
        await FlutterForegroundTask.updateService(notificationTitle: title, notificationText: _text());
      } catch (_) {}
    }
  }

  void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'satsh_keepalive',
        channelName: 'Koneksi aktif',
        channelDescription: 'Jaga sesi SSH & tunnel tetap nyala di background',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
        stopWithTask: true,
      ),
    );
    SshManager.i.addListener(sync);
    Store.i.addListener(sync);
    Brain.i.addListener(sync);
    PhoneServer.i.addListener(sync);
    AgentController.i.addListener(sync);
    MissionRunner.i.addListener(sync);
  }

  bool get enabled => Store.i.get<bool>('keepAlive', true);

  String _text() {
    final s = SshManager.i.sessions.where((e) => e.state == ConnState.ready).length;
    final f = SshManager.i.forwards.length;
    final j = Brain.i.jobs.where((e) => e.enabled).length;
    final srv = PhoneServer.i.running;
    final mi = MissionRunner.i.missions.where((m) => m.active).length;
    final t = [if (mi > 0) '$mi misi jalan', if (AgentController.i.busy) 'agent lagi kerja', if (srv) 'mode server', if (s > 0) '$s sesi', if (f > 0) '$f tunnel', if (j > 0) '$j jadwal'].join(' · ');
    return _event == null ? t : '$_event\n$t';
  }

  Future<void> sync() async {
    if (_busy) return;
    _busy = true;
    try {
      final want = enabled &&
          (SshManager.i.sessions.any((e) => e.state == ConnState.ready) ||
              SshManager.i.forwards.isNotEmpty ||
              Brain.i.jobs.any((e) => e.enabled) ||
              PhoneServer.i.running ||
              AgentController.i.busy ||
              MissionRunner.i.anyActive);
      if (want && !_running) {
        if (await FlutterForegroundTask.checkNotificationPermission() != NotificationPermission.granted) {
          await FlutterForegroundTask.requestNotificationPermission();
        }
        final r = await FlutterForegroundTask.startService(
          serviceId: 4242,
          notificationTitle: 'satsh nyala',
          notificationText: _text(),
          callback: keepAliveCallback,
        );
        _running = r is ServiceRequestSuccess;
        _last = _text();
      } else if (want && _running && _text() != _last) {
        _last = _text();
        await FlutterForegroundTask.updateService(notificationTitle: 'satsh nyala', notificationText: _text());
      } else if (!want && _running) {
        await FlutterForegroundTask.stopService();
        _running = false;
      }
    } catch (_) {
      // never let the keep-alive break the app
    } finally {
      _busy = false;
    }
  }
}
