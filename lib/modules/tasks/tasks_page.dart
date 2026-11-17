import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/notifications.dart';
import '../../core/util.dart';
import '../files/files_ui.dart' show askName, showMessage;
import 'organizer_store.dart';
import 'quick_add.dart';

const priorityColors = <Color>[
  Color(0xFF8B8D98),
  Color(0xFF0A84FF),
  Color(0xFFF76B15),
  Color(0xFFE5484D),
];
const _priorityLabels = ['Aucune', 'Basse', 'Moyenne', 'Haute'];

String _two(int n) => n.toString().padLeft(2, '0');

/// "Aujourd'hui", "Demain 9:00", "12 mars"… for a task's due date.
String dueLabel(Task t) {
  final due = t.due;
  if (due == null) return '';
  final now = DateTime.now();
  final days = dayOf(due).difference(dayOf(now)).inDays;
  final day = switch (days) {
    0 => "Aujourd'hui",
    1 => 'Demain',
    -1 => 'Hier',
    _ => dayLabel(due),
  };
  return t.hasTime ? '$day ${due.hour}:${_two(due.minute)}' : day;
}

enum _View {
  today("Aujourd'hui"),
  upcoming('À venir'),
  all('Toutes'),
  done('Terminées');

  const _View(this.label);
  final String label;
}

class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  _View _view = _View.today;
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final parsed = parseQuickTask(_input.text, DateTime.now());
    if (parsed.title.isEmpty) return;
    final store = context.read<OrganizerStore>();
    // With no date typed, a task added from "today" is due today.
    final due =
        parsed.due ?? (_view == _View.today ? dayOf(DateTime.now()) : null);
    _input.clear();
    setState(() {});
    if (parsed.hasTime) await Reminders.requestPermission();
    await store.saveTask(
      Task(
        title: parsed.title,
        due: due,
        hasTime: parsed.hasTime,
        priority: parsed.priority,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<OrganizerStore>();
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = dayOf(now);
    final open = store.open;

    // Sections of the current view: heading and tasks.
    final sections = <(String, List<Task>)>[];
    switch (_view) {
      case _View.today:
        final late = open
            .where((t) => t.due != null && dayOf(t.due!).isBefore(today))
            .toList();
        final due = open
            .where((t) => t.due != null && dayOf(t.due!) == today)
            .toList();
        if (late.isNotEmpty) sections.add(('En retard', late));
        if (due.isNotEmpty) sections.add(("Aujourd'hui", due));
      case _View.upcoming:
        for (final t in open.where(
          (t) => t.due != null && dayOf(t.due!).isAfter(today),
        )) {
          final label = dayOf(t.due!).difference(today).inDays == 1
              ? 'Demain'
              : dayLabel(t.due!);
          if (sections.isEmpty || sections.last.$1 != label) {
            sections.add((label, []));
          }
          sections.last.$2.add(t);
        }
      case _View.all:
        for (final list in store.lists) {
          final items = open.where((t) => t.list == list).toList();
          if (items.isNotEmpty) sections.add((list, items));
        }
      case _View.done:
        if (store.completed.isNotEmpty) sections.add(('', store.completed));
    }
    final preview = _input.text.trim().isEmpty
        ? null
        : parseQuickTask(_input.text, now);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tâches'),
        actions: [
          if (_view == _View.done && store.completed.isNotEmpty)
            TextButton(
              onPressed: store.clearCompleted,
              child: const Text('Tout effacer'),
            ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _View.values.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final v = _View.values[i];
                final count = switch (v) {
                  _View.today =>
                    open
                        .where(
                          (t) => t.due != null && !dayOf(t.due!).isAfter(today),
                        )
                        .length,
                  _ => 0,
                };
                return ChoiceChip(
                  showCheckmark: false,
                  label: Text(count > 0 ? '${v.label} · $count' : v.label),
                  selected: v == _view,
                  onSelected: (_) => setState(() => _view = v),
                );
              },
            ),
          ),
          Expanded(
            child: sections.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _view == _View.today
                                ? Icons.wb_sunny_outlined
                                : Icons.check_circle_outline,
                            size: 64,
                            color: scheme.outline,
                          ),
                          const SizedBox(height: 16),
                          Text(switch (_view) {
                            _View.today => "Rien de prévu aujourd'hui",
                            _View.upcoming => 'Aucune tâche à venir',
                            _View.all => 'Aucune tâche en cours',
                            _View.done => 'Aucune tâche terminée',
                          }, style: Theme.of(context).textTheme.titleMedium),
                          if (_view != _View.done) ...[
                            const SizedBox(height: 8),
                            const Text(
                              'Écrivez par exemple « appeler Paul demain 9h » dans le champ ci-dessous.',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.only(bottom: 12),
                    children: [
                      for (final (label, items) in sections) ...[
                        if (label.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                            child: Text(
                              label,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: label == 'En retard'
                                    ? scheme.error
                                    : scheme.primary,
                              ),
                            ),
                          ),
                        for (final t in items) TaskTile(t, key: ValueKey(t.id)),
                      ],
                    ],
                  ),
          ),
          if (_view != _View.done)
            Material(
              color: scheme.surfaceContainer,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Shows what was understood before the task is created.
                      if (preview != null &&
                          (preview.due != null || preview.priority > 0))
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 6),
                          child: Wrap(
                            spacing: 6,
                            children: [
                              if (preview.due != null)
                                _Pill(
                                  icon: Icons.event,
                                  label: dueLabel(
                                    Task(
                                      title: '',
                                      due: preview.due,
                                      hasTime: preview.hasTime,
                                    ),
                                  ),
                                  color: scheme.primary,
                                ),
                              if (preview.priority > 0)
                                _Pill(
                                  icon: Icons.flag,
                                  label: _priorityLabels[preview.priority],
                                  color: priorityColors[preview.priority],
                                ),
                            ],
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _input,
                              onChanged: (_) => setState(() {}),
                              onSubmitted: (_) => _add(),
                              textCapitalization: TextCapitalization.sentences,
                              textInputAction: TextInputAction.done,
                              decoration: const InputDecoration(
                                hintText: 'Ajouter une tâche…',
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton.filled(
                            tooltip: 'Ajouter',
                            icon: const Icon(Icons.arrow_upward_rounded),
                            onPressed: _input.text.trim().isEmpty ? null : _add,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// One task row: tap the circle to complete, swipe right to complete, swipe
/// left to postpone to tomorrow, tap to edit.
class TaskTile extends StatelessWidget {
  const TaskTile(this.task, {super.key, this.dense = false});
  final Task task;
  final bool dense;

  void _complete(BuildContext context) {
    final store = context.read<OrganizerStore>();
    store.setDone(task, true);
    showMessage(
      context,
      'Tâche terminée',
      action: SnackBarAction(
        label: 'Annuler',
        onPressed: () => store.setDone(task, false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<OrganizerStore>();
    final scheme = Theme.of(context).colorScheme;
    final color = priorityColors[task.priority];
    final overdue = task.isOverdue(DateTime.now());
    final details = [
      if (task.due != null) dueLabel(task),
      if (task.repeat != Repeat.none) task.repeat.label.toLowerCase(),
      if (task.list != 'Boîte de réception') task.list,
    ].join(' · ');

    final tile = ListTile(
      dense: dense,
      leading: IconButton(
        tooltip: task.done ? 'Rouvrir' : 'Terminer',
        icon: Icon(
          task.done ? Icons.check_circle_rounded : Icons.circle_outlined,
          color: task.done ? scheme.outline : color,
          size: 26,
        ),
        onPressed: () =>
            task.done ? store.setDone(task, false) : _complete(context),
      ),
      title: Text(
        task.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          decoration: task.done ? TextDecoration.lineThrough : null,
          color: task.done ? scheme.outline : null,
        ),
      ),
      subtitle: details.isEmpty
          ? null
          : Text(
              details,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: overdue ? scheme.error : scheme.onSurfaceVariant,
              ),
            ),
      onTap: () => showTaskEditor(context, task),
    );
    if (task.done) return tile;

    return Dismissible(
      key: ValueKey('task-${task.id}'),
      background: Container(
        color: const Color(0xFF30A46C),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        child: const Icon(Icons.check, color: Colors.white),
      ),
      secondaryBackground: Container(
        color: scheme.tertiary,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Demain', style: TextStyle(color: scheme.onTertiary)),
            const SizedBox(width: 8),
            Icon(Icons.event_repeat, color: scheme.onTertiary),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          _complete(context);
        } else {
          // Keeps the time of day, moves the day to tomorrow.
          final tomorrow = dayOf(DateTime.now()).add(const Duration(days: 1));
          final due = task.due;
          task.due = DateTime(
            tomorrow.year,
            tomorrow.month,
            tomorrow.day,
            task.hasTime ? due!.hour : 0,
            task.hasTime ? due!.minute : 0,
          );
          await store.saveTask(task);
        }
        return false; // the list rebuilds from the store
      },
      child: tile,
    );
  }
}

/// Bottom sheet to create or edit a task.
Future<void> showTaskEditor(BuildContext context, [Task? existing]) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TaskEditor(existing: existing),
  );
}

class _TaskEditor extends StatefulWidget {
  const _TaskEditor({this.existing});
  final Task? existing;

  @override
  State<_TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<_TaskEditor> {
  late final Task _task = widget.existing ?? Task(title: '');
  late final _title = TextEditingController(text: _task.title);
  late final _notes = TextEditingController(text: _task.notes);
  late DateTime? _due = _task.due;
  late bool _hasTime = _task.hasTime;
  late int _priority = _task.priority;
  late String _list = _task.list;
  late Repeat _repeat = _task.repeat;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null) return;
    setState(
      () => _due = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _hasTime ? _due!.hour : 0,
        _hasTime ? _due!.minute : 0,
      ),
    );
  }

  Future<void> _pickTime() async {
    final base = _due ?? dayOf(DateTime.now());
    final picked = await showTimePicker(
      context: context,
      initialTime: _hasTime
          ? TimeOfDay.fromDateTime(base)
          : const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked == null) return;
    setState(() {
      _due = DateTime(
        base.year,
        base.month,
        base.day,
        picked.hour,
        picked.minute,
      );
      _hasTime = true;
    });
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final store = context.read<OrganizerStore>();
    final navigator = Navigator.of(context);
    _task
      ..title = title
      ..notes = _notes.text.trim()
      ..due = _due
      ..hasTime = _hasTime && _due != null
      ..priority = _priority
      ..list = _list
      ..repeat = _due == null ? Repeat.none : _repeat;
    if (_task.hasTime) await Reminders.requestPermission();
    await store.saveTask(_task);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<OrganizerStore>();
    final lists = {...store.lists, _list}.toList();
    final due = _due;
    return Padding(
      // Lifts the sheet above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _title,
                autofocus: widget.existing == null,
                textCapitalization: TextCapitalization.sentences,
                style: Theme.of(context).textTheme.titleLarge,
                decoration: const InputDecoration(
                  hintText: 'Titre de la tâche',
                  filled: false,
                  border: InputBorder.none,
                ),
              ),
              TextField(
                controller: _notes,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 3,
                minLines: 1,
                decoration: const InputDecoration(
                  hintText: 'Notes',
                  filled: false,
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  InputChip(
                    avatar: const Icon(Icons.event, size: 18),
                    label: Text(due == null ? 'Date' : dayLabel(due)),
                    onPressed: _pickDate,
                    onDeleted: due == null
                        ? null
                        : () => setState(() {
                            _due = null;
                            _hasTime = false;
                          }),
                  ),
                  InputChip(
                    avatar: const Icon(Icons.schedule, size: 18),
                    label: Text(
                      _hasTime && due != null
                          ? '${due.hour}:${_two(due.minute)}'
                          : 'Heure',
                    ),
                    onPressed: _pickTime,
                    onDeleted: _hasTime
                        ? () => setState(() => _hasTime = false)
                        : null,
                  ),
                  if (due != null)
                    PopupMenuButton<Repeat>(
                      onSelected: (r) => setState(() => _repeat = r),
                      itemBuilder: (_) => [
                        for (final r in Repeat.values)
                          PopupMenuItem(value: r, child: Text(r.label)),
                      ],
                      child: Chip(
                        avatar: const Icon(Icons.repeat, size: 18),
                        label: Text(
                          _repeat == Repeat.none ? 'Répéter' : _repeat.label,
                        ),
                      ),
                    ),
                  PopupMenuButton<int>(
                    onSelected: (p) => setState(() => _priority = p),
                    itemBuilder: (_) => [
                      for (var i = 3; i >= 0; i--)
                        PopupMenuItem(
                          value: i,
                          child: Row(
                            children: [
                              Icon(
                                Icons.flag,
                                color: priorityColors[i],
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Text(_priorityLabels[i]),
                            ],
                          ),
                        ),
                    ],
                    child: Chip(
                      avatar: Icon(
                        Icons.flag,
                        size: 18,
                        color: priorityColors[_priority],
                      ),
                      label: Text(
                        _priority == 0
                            ? 'Priorité'
                            : _priorityLabels[_priority],
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value.isNotEmpty) {
                        return setState(() => _list = value);
                      }
                      final name = await askName(
                        context,
                        title: 'Nouvelle liste',
                        action: 'Créer',
                      );
                      if (name != null) setState(() => _list = name);
                    },
                    itemBuilder: (_) => [
                      for (final l in lists)
                        PopupMenuItem(value: l, child: Text(l)),
                      const PopupMenuItem(
                        value: '',
                        child: Text('Nouvelle liste…'),
                      ),
                    ],
                    child: Chip(
                      avatar: const Icon(Icons.list_alt, size: 18),
                      label: Text(_list),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (widget.existing != null)
                    TextButton.icon(
                      onPressed: () {
                        store.deleteTask(_task);
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Supprimer'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _save,
                    child: const Text('Enregistrer'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
