import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../core/platform.dart';
import '../../core/settings.dart';
import '../../core/util.dart';
import '../tasks/organizer_store.dart';
import '../tasks/tasks_page.dart';
import 'event_editor_page.dart';
import 'time_grid.dart';

const eventColors = <Color>[
  Color(0xFF0A84FF),
  Color(0xFF30A46C),
  Color(0xFFE5484D),
  Color(0xFFF76B15),
  Color(0xFF8E4EC6),
  Color(0xFFD6409F),
  Color(0xFF12A594),
];

const _monthNames = [
  'Janvier',
  'Février',
  'Mars',
  'Avril',
  'Mai',
  'Juin',
  'Juillet',
  'Août',
  'Septembre',
  'Octobre',
  'Novembre',
  'Décembre',
];
const _dayLetters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

/// Page index of January of year 0 in the month pager.
const _epochPage = 0;
int _pageOf(DateTime month) => month.year * 12 + month.month - 1 - _epochPage;
DateTime _monthOf(int page) =>
    DateTime((page + _epochPage) ~/ 12, (page + _epochPage) % 12 + 1);

/// Weeks and days are counted from a Monday far in the past, in UTC so that
/// daylight saving time never shifts a page.
final _refMonday = DateTime.utc(2000, 1, 3);
int _dayPage(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).difference(_refMonday).inDays;
DateTime _dayAt(int page) {
  final u = _refMonday.add(Duration(days: page));
  return DateTime(u.year, u.month, u.day);
}

int _weekPage(DateTime d) => (_dayPage(d) / 7).floor();
DateTime _weekStart(int page) => _dayAt(page * 7);

enum _Mode {
  month('Mois', Icons.calendar_month),
  week('Semaine', Icons.view_week_outlined),
  day('Jour', Icons.calendar_view_day_outlined),
  agenda('Planning', Icons.view_agenda_outlined);

  const _Mode(this.label, this.icon);
  final String label;
  final IconData icon;
}

String _two(int n) => n.toString().padLeft(2, '0');
String _hm(DateTime d) => '${d.hour}:${_two(d.minute)}';

Color eventColor(Event e) => e.externalColor != null
    ? Color(0xFF000000 | e.externalColor!)
    : eventColors[e.color.clamp(0, eventColors.length - 1)];

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late DateTime _selected = dayOf(DateTime.now());
  late DateTime _month = DateTime(_selected.year, _selected.month);
  late final _pager = PageController(initialPage: _pageOf(_month));
  _Mode _mode = _Mode.month;
  PageController? _weekPager;
  PageController? _dayPager;

  /// Events of the phone's calendars for the loaded range.
  List<Event> _device = [];
  bool _deviceAllowed = false;

  @override
  void initState() {
    super.initState();
    _loadDevice(request: false);
  }

  void _setMode(_Mode mode) {
    _weekPager?.dispose();
    _dayPager?.dispose();
    _weekPager = _dayPager = null;
    if (mode == _Mode.week) {
      _weekPager = PageController(initialPage: _weekPage(_selected));
    } else if (mode == _Mode.day) {
      _dayPager = PageController(initialPage: _dayPage(_selected));
    }
    setState(() => _mode = mode);
  }

  @override
  void dispose() {
    _weekPager?.dispose();
    _dayPager?.dispose();
    _pager.dispose();
    super.dispose();
  }

  Future<void> _loadDevice({required bool request}) async {
    try {
      var status = await Permission.calendarFullAccess.status;
      if (!status.isGranted && request) {
        status = await Permission.calendarFullAccess.request();
      }
      if (!status.isGranted) {
        if (request && mounted && status.isPermanentlyDenied) openAppSettings();
        return;
      }
    } on Exception {
      return; // not on a device (tests)
    }
    // One year around the displayed month covers both views.
    final from = DateTime(_month.year, _month.month - 2);
    final to = DateTime(_month.year, _month.month + 10);
    final rows = await MediaChannel.calendarEvents(
      from.millisecondsSinceEpoch,
      to.millisecondsSinceEpoch,
    );
    if (!mounted) return;
    setState(() {
      _deviceAllowed = true;
      _device = [
        for (final m in rows)
          () {
            final allDay = m['allDay'] == true;
            var start = DateTime.fromMillisecondsSinceEpoch(
              (m['start'] as num).toInt(),
            );
            var end = DateTime.fromMillisecondsSinceEpoch(
              (m['end'] as num).toInt(),
            );
            if (allDay) {
              // All-day events are stored at midnight UTC.
              final s = start.toUtc(), e = end.toUtc();
              start = DateTime(s.year, s.month, s.day);
              end = DateTime(e.year, e.month, e.day);
            }
            return Event(
              title: (m['title'] as String?)?.trim().isNotEmpty == true
                  ? m['title'] as String
                  : '(Sans titre)',
              start: start,
              end: end,
              allDay: allDay,
              location: (m['location'] as String?) ?? '',
              notes: (m['notes'] as String?) ?? '',
              external: true,
              calendar: (m['calendar'] as String?) ?? '',
              externalColor: (m['color'] as num?)?.toInt(),
              deviceId: (m['id'] as num?)?.toInt(),
              deviceCalendarId: (m['calendarId'] as num?)?.toInt(),
              editable: m['editable'] == true,
              recurring: m['recurring'] == true,
            );
          }(),
      ];
    });
  }

  List<Event> _eventsBetween(
    OrganizerStore store,
    DateTime from,
    DateTime to,
  ) => [
    ...store.eventsBetween(from, to),
    ..._device.where((e) => e.start.isBefore(to) && e.end.isAfter(from)),
  ]..sort((a, b) => a.start.compareTo(b.start));

  void _goTo(DateTime day) {
    setState(() {
      _selected = dayOf(day);
      _month = DateTime(day.year, day.month);
    });
    void animate(PageController? c, int page) {
      if (c != null && c.hasClients && c.page?.round() != page) {
        c.animateToPage(
          page,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    }

    animate(_weekPager, _weekPage(day));
    animate(_dayPager, _dayPage(day));
    final page = _pageOf(DateTime(day.year, day.month));
    if (_pager.hasClients && _pager.page?.round() != page) {
      _pager.animateToPage(
        page,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _edit([Event? event, DateTime? day, int? hour]) async {
    // Phone events that cannot be changed here are shown, not edited.
    if (event != null &&
        event.external &&
        !(event.editable && !event.recurring)) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              event.recurring
                  ? "Événement répétitif : modifiez-le dans l'application Agenda du téléphone"
                  : 'Cet agenda est en lecture seule',
            ),
          ),
        );
      return;
    }
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => EventEditorPage(
          event: event,
          day: day ?? _selected,
          startHour: hour,
        ),
      ),
    );
    // A phone calendar may have been written to.
    if (changed == true && _deviceAllowed) await _loadDevice(request: false);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<OrganizerStore>();
    final settings = context.watch<AppSettings>();
    final hidePrompt = settings.raw('calendarPromptHidden') != null;

    return Scaffold(
      appBar: AppBar(
        title: Text('${_monthNames[_month.month - 1]} ${_month.year}'),
        actions: [
          TextButton(
            onPressed: () => _goTo(DateTime.now()),
            child: const Text("Aujourd'hui"),
          ),
          PopupMenuButton<_Mode>(
            tooltip: 'Changer de vue',
            icon: Icon(_mode.icon),
            initialValue: _mode,
            onSelected: _setMode,
            itemBuilder: (_) => [
              for (final m in _Mode.values)
                PopupMenuItem(
                  value: m,
                  child: Row(
                    children: [
                      Icon(m.icon, size: 20),
                      const SizedBox(width: 12),
                      Text(m.label),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Nouvel événement',
        onPressed: _edit,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          if (!_deviceAllowed && !hidePrompt)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.sync),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Afficher aussi les agendas du téléphone',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            TextButton(
                              onPressed: () => _loadDevice(request: true),
                              child: const Text('Activer'),
                            ),
                            IconButton(
                              tooltip: 'Masquer',
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () =>
                                  settings.setRaw('calendarPromptHidden', '1'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: switch (_mode) {
              _Mode.month => _monthView(store),
              _Mode.week => _weekView(store),
              _Mode.day => _dayView(store),
              _Mode.agenda => _agendaView(store),
            },
          ),
        ],
      ),
    );
  }

  Widget _monthView(OrganizerStore store) {
    final scheme = Theme.of(context).colorScheme;
    // A scrolling page: with large system text the grid and the day's
    // entries no longer fit one screen.
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              for (final l in _dayLetters)
                Expanded(
                  child: Center(
                    child: Text(
                      l,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // The grid keeps a fixed size, so its text is not enlarged past 130 %.
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: SizedBox(
            height: 6 * 52,
            child: PageView.builder(
              controller: _pager,
              onPageChanged: (page) {
                final month = _monthOf(page);
                setState(() {
                  _month = month;
                  // Keep a day selected inside the visible month.
                  if (_selected.year != month.year ||
                      _selected.month != month.month) {
                    final now = dayOf(DateTime.now());
                    _selected =
                        now.year == month.year && now.month == month.month
                        ? now
                        : month;
                  }
                });
                if (_deviceAllowed) _loadDevice(request: false);
              },
              itemBuilder: (_, page) => _MonthGrid(
                month: _monthOf(page),
                selected: _selected,
                onSelect: _goTo,
                dotsFor: (day) {
                  final next = day.add(const Duration(days: 1));
                  return [
                    for (final e in _eventsBetween(store, day, next).take(3))
                      eventColor(e),
                    if (store.tasksOn(day).isNotEmpty) scheme.outline,
                  ];
                },
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        ..._dayEntries(store, _selected, header: true),
      ],
    );
  }

  /// Events and tasks of one day.
  List<Widget> _dayEntries(
    OrganizerStore store,
    DateTime day, {
    bool header = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final events = _eventsBetween(store, day, day.add(const Duration(days: 1)));
    final tasks = store.tasksOn(day);
    return [
      if (header)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Text(
            dayLabelLong(day),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
          ),
        ),
      if (events.isEmpty && tasks.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              'Rien de prévu',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
        ),
      for (final e in events)
        _EventTile(event: e, day: day, onTap: () => _edit(e)),
      for (final t in tasks) TaskTile(t, dense: true),
    ];
  }

  void _onGridPage(DateTime day) {
    setState(() {
      _selected = day;
      _month = DateTime(day.year, day.month);
    });
    if (_deviceAllowed) _loadDevice(request: false);
  }

  Widget _grid(OrganizerStore store, List<DateTime> days) => TimeGrid(
    days: days,
    selected: _selected,
    eventsOn: (d) =>
        _eventsBetween(store, d, DateTime(d.year, d.month, d.day + 1)),
    color: eventColor,
    onEvent: _edit,
    onCreate: (day, hour) => _edit(null, day, hour),
    onDay: (d) {
      _goTo(d);
      if (_mode == _Mode.week) _setMode(_Mode.day);
    },
  );

  Widget _weekView(OrganizerStore store) => PageView.builder(
    controller: _weekPager,
    onPageChanged: (page) {
      final start = _weekStart(page);
      // Keeps the same weekday selected in the new week.
      _onGridPage(
        DateTime(start.year, start.month, start.day + _selected.weekday - 1),
      );
    },
    itemBuilder: (_, page) {
      final start = _weekStart(page);
      return _grid(store, [
        for (var i = 0; i < 7; i++)
          DateTime(start.year, start.month, start.day + i),
      ]);
    },
  );

  Widget _dayView(OrganizerStore store) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            dayLabelLong(_selected),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ),
      Expanded(
        child: PageView.builder(
          controller: _dayPager,
          onPageChanged: (page) => _onGridPage(_dayAt(page)),
          itemBuilder: (_, page) => _grid(store, [_dayAt(page)]),
        ),
      ),
    ],
  );

  Widget _agendaView(OrganizerStore store) {
    final scheme = Theme.of(context).colorScheme;
    final today = dayOf(DateTime.now());
    // The next 60 days that have something planned.
    final days = <DateTime>[
      for (var i = 0; i < 60; i++)
        if (() {
          final d = DateTime(today.year, today.month, today.day + i);
          return _eventsBetween(
                store,
                d,
                d.add(const Duration(days: 1)),
              ).isNotEmpty ||
              store.tasksOn(d).isNotEmpty;
        }())
          DateTime(today.year, today.month, today.day + i),
    ];
    if (days.isEmpty) {
      return Center(
        child: Text(
          'Rien de prévu dans les 60 prochains jours',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        for (final day in days) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 2),
            child: Text(
              day == today
                  ? "Aujourd'hui · ${dayLabelLong(day)}"
                  : dayLabelLong(day),
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: scheme.primary,
              ),
            ),
          ),
          for (final e in _eventsBetween(
            store,
            day,
            day.add(const Duration(days: 1)),
          ))
            _EventTile(event: e, day: day, onTap: () => _edit(e)),
          for (final t in store.tasksOn(day)) TaskTile(t, dense: true),
        ],
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.onSelect,
    required this.dotsFor,
  });

  final DateTime month;
  final DateTime selected;
  final ValueChanged<DateTime> onSelect;
  final List<Color> Function(DateTime day) dotsFor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = dayOf(DateTime.now());
    // The grid starts on the Monday on or before the 1st.
    final first = DateTime(month.year, month.month, 1 - (month.weekday - 1));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          for (var week = 0; week < 6; week++)
            Expanded(
              child: Row(
                children: [
                  for (var d = 0; d < 7; d++)
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final day = DateTime(
                            first.year,
                            first.month,
                            first.day + week * 7 + d,
                          );
                          final inMonth = day.month == month.month;
                          final isSelected = day == selected;
                          final isToday = day == today;
                          final dots = inMonth ? dotsFor(day) : const <Color>[];
                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => onSelect(day),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isSelected ? scheme.primary : null,
                                    border: isToday && !isSelected
                                        ? Border.all(
                                            color: scheme.primary,
                                            width: 1.5,
                                          )
                                        : null,
                                  ),
                                  child: Text(
                                    '${day.day}',
                                    style: TextStyle(
                                      fontWeight: isToday || isSelected
                                          ? FontWeight.w800
                                          : FontWeight.w500,
                                      color: isSelected
                                          ? scheme.onPrimary
                                          : inMonth
                                          ? scheme.onSurface
                                          : scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                SizedBox(
                                  height: 6,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (final c in dots)
                                        Container(
                                          width: 5,
                                          height: 5,
                                          margin: const EdgeInsets.symmetric(
                                            horizontal: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: c,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.event,
    required this.day,
    required this.onTap,
  });
  final Event event;
  final DateTime day;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final e = event;
    final nextDay = day.add(const Duration(days: 1));
    // Shown relative to [day] for events spanning several days.
    final startsBefore = e.start.isBefore(day);
    final endsAfter = e.end.isAfter(nextDay);
    final time = e.allDay || (startsBefore && endsAfter)
        ? 'Toute la journée'
        : startsBefore
        ? "Jusqu'à ${_hm(e.end)}"
        : endsAfter
        ? 'À partir de ${_hm(e.start)}'
        : '${_hm(e.start)} – ${_hm(e.end)}';
    final details = [
      time,
      if (e.location.isNotEmpty) e.location,
      if (e.external && e.calendar.isNotEmpty) e.calendar,
    ].join(' · ');

    return ListTile(
      dense: true,
      leading: Container(
        width: 5,
        height: 38,
        decoration: BoxDecoration(
          color: eventColor(e),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      title: Text(
        e.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
      subtitle: Text(
        details,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: scheme.onSurfaceVariant),
      ),
      trailing: e.repeat != Repeat.none
          ? const Icon(Icons.repeat, size: 16)
          : null,
      onTap: onTap,
    );
  }
}
