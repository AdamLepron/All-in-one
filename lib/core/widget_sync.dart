import 'dart:async';
import 'dart:convert';

import '../modules/tasks/organizer_store.dart';
import 'l10n.dart';
import 'platform.dart';

/// What the home-screen widgets show: today's open tasks (late ones first).
/// Kept apart from the platform call so it can be tested.
Map<String, Object> widgetSnapshot(OrganizerStore store, DateTime now) {
  final today = dayOf(now);
  final tasks = store.tasksOn(today, overdue: true).where((t) => !t.done);
  return {
    'tasks': [for (final t in tasks.take(6)) t.title],
    'tasksTitle': tr('Tâches du jour'),
    'tasksEmpty': tr('Rien de prévu'),
    'noteLabel': tr('Note rapide'),
  };
}

/// Pushes a fresh snapshot to the widgets whenever tasks change.
class WidgetSync {
  WidgetSync(this._store, {Future<void> Function(String json)? send})
    : _send = send ?? MediaChannel.updateWidgets;

  final OrganizerStore _store;
  final Future<void> Function(String json) _send;
  Timer? _timer;
  String _last = '';

  void start() {
    _store.addListener(_changed);
    _changed();
  }

  void _changed() {
    _timer?.cancel();
    // Several edits in a row make one update.
    _timer = Timer(const Duration(seconds: 1), push);
  }

  Future<void> push() async {
    final json = jsonEncode(widgetSnapshot(_store, DateTime.now()));
    if (json == _last) return;
    _last = json;
    await _send(json);
  }

  void dispose() {
    _timer?.cancel();
    _store.removeListener(_changed);
  }
}
