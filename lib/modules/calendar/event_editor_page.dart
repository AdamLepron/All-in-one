import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/notifications.dart';
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

String _two(int n) => n.toString().padLeft(2, '0');

/// Creates or edits an event of the built-in calendar.
class EventEditorPage extends StatefulWidget {
  const EventEditorPage({super.key, this.event, required this.day});
  final Event? event;

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

  @override
  void initState() {
    super.initState();
    final e = _existing;
    if (e != null) {
      _start = e.start;
      // All-day events store an exclusive end; show the last day instead.
      _end = e.allDay ? e.end.subtract(const Duration(days: 1)) : e.end;
    } else {
      // Next full hour of the chosen day.
      final now = DateTime.now();
      final hour = (now.hour + 1).clamp(0, 23);
      _start = DateTime(
        widget.day.year,
        widget.day.month,
        widget.day.day,
        hour,
      );
      _end = _start.add(const Duration(hours: 1));
    }
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
    navigator.pop();
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
            TextButton(
              onPressed: () => _pickDate(start),
              child: Text(dayLabelLong(value)),
            ),
            const Spacer(),
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
                context.read<OrganizerStore>().deleteEvent(_existing);
                Navigator.of(context).pop();
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
          SwitchListTile(
            secondary: const Icon(Icons.schedule),
            title: const Text('Toute la journée'),
            value: _allDay,
            onChanged: (v) => setState(() => _allDay = v),
          ),
          dateRow('Début', true),
          dateRow('Fin', false),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.repeat),
            title: const Text('Répétition'),
            trailing: DropdownButton<Repeat>(
              value: _repeat,
              underline: const SizedBox.shrink(),
              items: [
                for (final r in Repeat.values)
                  DropdownMenuItem(value: r, child: Text(r.label)),
              ],
              onChanged: (r) => setState(() => _repeat = r!),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_none),
            title: const Text('Rappel'),
            trailing: DropdownButton<int?>(
              value: _reminder,
              underline: const SizedBox.shrink(),
              items: [
                for (final e in _reminders.entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _reminder = v),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: Row(
              children: [
                for (var i = 0; i < eventColors.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => setState(() => _color = i),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: eventColors[i],
                          shape: BoxShape.circle,
                          border: _color == i
                              ? Border.all(color: scheme.onSurface, width: 2.5)
                              : null,
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
