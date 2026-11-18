import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/notifications.dart';
import '../../core/platform.dart';
import '../../core/util.dart';
import '../tasks/organizer_store.dart';
import 'calendar_page.dart' show eventColors;

const _reminders = <int?, String>{
  null: 'Aucun rappel',
  0: "À l'heure de l'événement",
  10: '10 minutes avant',
  30: '30 minutes avant',
  60: '1 heure avant',
  1440: 'La veille',
};

const _colorNames = [
  'bleue',
  'verte',
  'rouge',
  'orange',
  'violette',
  'rose',
  'turquoise',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// Creates or edits an event of the built-in calendar.
class EventEditorPage extends StatefulWidget {
  const EventEditorPage({
    super.key,
    this.event,
    required this.day,
    this.startHour,
  });
  final Event? event;

  /// Hour preselected for a new event (tapped on a week or day view).
  final int? startHour;

  /// Day preselected for a new event.
  final DateTime day;

  @override
  State<EventEditorPage> createState() => _EventEditorPageState();
}

class _EventEditorPageState extends State<EventEditorPage> {
  late final Event? _existing = widget.event;
  late final _title = TextEditingController(text: _existing?.title ?? '');
  late final _location = TextEditingController(text: _existing?.location ?? '');
  late final _notes = TextEditingController(text: _existing?.notes ?? '');
  late DateTime _start;
  late DateTime _end;
  late bool _allDay = _existing?.allDay ?? false;
  late int _color = _existing?.color ?? 0;
  late Repeat _repeat = _existing?.repeat ?? Repeat.none;
  late int? _reminder = _existing == null ? 10 : _existing.reminder;

  /// Phone calendars a new event can go to; empty when none is available.
  List<({int id, String name, String account})> _calendars = const [];

  /// Calendar chosen for a new event: null for the app's own.
  int? _target;

  /// True when the event lives in a phone calendar.
  bool get _onDevice => _existing?.external ?? _target != null;

  @override
  void initState() {
    super.initState();
    final e = _existing;
    if (e == null) _loadCalendars();
    if (e != null) {
      _start = e.start;
      // All-day events store an exclusive end; show the last day instead.
      _end = e.allDay ? e.end.subtract(const Duration(days: 1)) : e.end;
    } else {
      // Next full hour of the chosen day.
      final now = DateTime.now();
      final hour = widget.startHour ?? (now.hour + 1).clamp(0, 23);
      _start = DateTime(
        widget.day.year,
        widget.day.month,
        widget.day.day,
        hour,
      );
      _end = _start.add(const Duration(hours: 1));
    }
  }

  Future<void> _loadCalendars() async {
    final rows = await MediaChannel.calendars();
    if (!mounted || rows.isEmpty) return;
    setState(() {
      _calendars = [
        for (final m in rows)
          (
            id: (m['id'] as num).toInt(),
            name: (m['name'] as String?) ?? '',
            account: (m['account'] as String?) ?? '',
          ),
      ];
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool start) async {
    final current = start ? _start : _end;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 5),
      lastDate: DateTime(current.year + 20),
    );
    if (picked == null) return;
    setState(() {
      final value = DateTime(
        picked.year,
        picked.month,
        picked.day,
        current.hour,
        current.minute,
      );
      if (start) {
        // Moving the start keeps the duration.
        final length = _end.difference(_start);
        _start = value;
        _end = value.add(length);
      } else {
        _end = value.isBefore(_start) ? _start : value;
      }
    });
  }

  Future<void> _pickTime(bool start) async {
    final current = start ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (picked == null) return;
    setState(() {
      final value = DateTime(
        current.year,
        current.month,
        current.day,
        picked.hour,
        picked.minute,
      );
      if (start) {
        final length = _end.difference(_start);
        _start = value;
        _end = value.add(length);
      } else {
        // An end before the start means the next day.
        _end = value.isAfter(_start)
            ? value
            : value.add(const Duration(days: 1));
      }
    });
  }

  Future<void> _save() async {
    final store = context.read<OrganizerStore>();
    final navigator = Navigator.of(context);
    final title = _title.text.trim();
    final start = _allDay
        ? DateTime(_start.year, _start.month, _start.day)
        : _start;
    final end = _allDay ? DateTime(_end.year, _end.month, _end.day + 1) : _end;
    if (_onDevice) return _saveOnDevice(title, start, end);
    final event = _existing ?? Event(title: '', start: start, end: end);
    event
      ..title = title.isEmpty ? '(Sans titre)' : title
      ..start = start
      ..end = end
      ..allDay = _allDay
      ..location = _location.text.trim()
      ..notes = _notes.text.trim()
      ..color = _color
      ..repeat = _repeat
      ..reminder = _reminder;
    if (_reminder != null) await Reminders.requestPermission();
    await store.saveEvent(event);
    navigator.pop(true);
  }

  /// Writes the event into a phone calendar.
  Future<void> _saveOnDevice(String title, DateTime start, DateTime end) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // All-day events are stored at midnight UTC by Android's calendar.
    final from = _allDay
        ? DateTime.utc(start.year, start.month, start.day)
        : start;
    final to = _allDay ? DateTime.utc(end.year, end.month, end.day) : end;
    final id = await MediaChannel.saveCalendarEvent({
      'id': _existing?.deviceId,
      'calendarId': _target,
      'title': title.isEmpty ? '(Sans titre)' : title,
      'start': from.millisecondsSinceEpoch,
      'end': to.millisecondsSinceEpoch,
      'allDay': _allDay,
      'location': _location.text.trim(),
      'notes': _notes.text.trim(),
      'reminder': _existing == null ? _reminder : null,
    });
    if (id == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text("Le téléphone a refusé d'enregistrer l'événement"),
        ),
      );
      return;
    }
    navigator.pop(true);
  }

  Future<void> _deleteOnDevice() async {
    final navigator = Navigator.of(context);
    final id = _existing?.deviceId;
    if (id != null) await MediaChannel.deleteCalendarEvent(id);
    navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    Widget dateRow(String label, bool start) {
      final value = start ? _start : _end;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
        child: Row(
          children: [
            SizedBox(width: 56, child: Text(label, style: text.bodyMedium)),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => _pickDate(start),
                  child: Text(
                    dayLabelLong(value),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
            if (!_allDay)
              TextButton(
                onPressed: () => _pickTime(start),
                child: Text('${value.hour}:${_two(value.minute)}'),
              ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Fermer',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          _existing == null ? 'Nouvel événement' : "Modifier l'événement",
        ),
        actions: [
          if (_existing != null)
            IconButton(
              tooltip: 'Supprimer',
              icon: const Icon(Icons.delete_outline),
              onPressed: () {
                if (_existing.external) {
                  _deleteOnDevice();
                  return;
                }
                context.read<OrganizerStore>().deleteEvent(_existing);
                Navigator.of(context).pop(true);
              },
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _save,
              child: const Text('Enregistrer'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: TextField(
              controller: _title,
              autofocus: _existing == null,
              textCapitalization: TextCapitalization.sentences,
              style: text.headlineSmall,
              decoration: const InputDecoration(
                hintText: 'Titre',
                filled: false,
                border: InputBorder.none,
              ),
            ),
          ),
          if (_calendars.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('Agenda'),
              subtitle: DropdownButton<int?>(
                value: _target,
                underline: const SizedBox.shrink(),
                isExpanded: true,
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All-in-One'),
                  ),
                  for (final c in _calendars)
                    DropdownMenuItem(
                      value: c.id,
                      child: Text(
                        c.name == c.account || c.account.isEmpty
                            ? c.name
                            : '${c.name} (${c.account})',
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _target = v),
              ),
            ),
          if (_existing?.external ?? false)
            ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: Text(_existing!.calendar),
              subtitle: const Text('Agenda du téléphone'),
            ),
          SwitchListTile(
            secondary: const Icon(Icons.schedule),
            title: const Text('Toute la journée'),
            value: _allDay,
            onChanged: (v) => setState(() => _allDay = v),
          ),
          dateRow('Début', true),
          dateRow('Fin', false),
          const Divider(),
          if (!_onDevice)
            ListTile(
              leading: const Icon(Icons.repeat),
              title: const Text('Répétition'),
              subtitle: DropdownButton<Repeat>(
                value: _repeat,
                underline: const SizedBox.shrink(),
                isExpanded: true,
                items: [
                  for (final r in Repeat.values)
                    DropdownMenuItem(value: r, child: Text(r.label)),
                ],
                onChanged: (r) => setState(() => _repeat = r!),
              ),
            ),
          if (!(_existing?.external ?? false))
            ListTile(
              leading: const Icon(Icons.notifications_none),
              title: const Text('Rappel'),
              subtitle: DropdownButton<int?>(
                value: _reminder,
                underline: const SizedBox.shrink(),
                isExpanded: true,
                items: [
                  for (final e in _reminders.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _reminder = v),
              ),
            ),
          if (!_onDevice)
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: Wrap(
                children: [
                  for (var i = 0; i < eventColors.length; i++)
                    Semantics(
                      label: 'Couleur ${_colorNames[i]}',
                      button: true,
                      selected: _color == i,
                      excludeSemantics: true,
                      onTap: () => setState(() => _color = i),
                      child: InkResponse(
                        onTap: () => setState(() => _color = i),
                        radius: 24,
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: Center(
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: eventColors[i],
                                shape: BoxShape.circle,
                                border: _color == i
                                    ? Border.all(
                                        color: scheme.onSurface,
                                        width: 2.5,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: TextField(
              controller: _location,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Lieu',
                prefixIcon: Icon(Icons.place_outlined),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: TextField(
              controller: _notes,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 4,
              minLines: 2,
              decoration: const InputDecoration(hintText: 'Notes'),
            ),
          ),
        ],
      ),
    );
  }
}
