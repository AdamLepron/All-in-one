import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/notifications.dart';
import '../../core/settings.dart';
import '../../core/util.dart';
import 'alarms.dart';
import 'clock_controller.dart';
import 'world_cities.dart';

const _citiesKey = 'worldCities';
const _defaultCities = ['Europe/London', 'America/New_York', 'Asia/Tokyo'];

class ClockPage extends StatefulWidget {
  const ClockPage({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  State<ClockPage> createState() => _ClockPageState();
}

class _ClockPageState extends State<ClockPage> {
  late int _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Horloge')),
      body: switch (_tab) {
        0 => _WorldTab(onAlarms: () => setState(() => _tab = 1)),
        1 => const _AlarmsTab(),
        2 => const _TimerTab(),
        _ => const _StopwatchTab(),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.public), label: 'Horloge'),
          NavigationDestination(
            icon: Icon(Icons.alarm_rounded),
            label: 'Alarmes',
          ),
          NavigationDestination(
            icon: Icon(Icons.hourglass_bottom_rounded),
            label: 'Minuteur',
          ),
          NavigationDestination(
            icon: Icon(Icons.timer_outlined),
            label: 'Chronomètre',
          ),
        ],
      ),
    );
  }
}

/// Rebuilds its child on a fixed period while mounted.
class _Ticker extends StatefulWidget {
  const _Ticker({required this.period, required this.builder});
  final Duration period;
  final WidgetBuilder builder;

  @override
  State<_Ticker> createState() => _TickerState();
}

class _TickerState extends State<_Ticker> {
  late final Timer _timer = Timer.periodic(
    widget.period,
    (_) => setState(() {}),
  );

  @override
  void initState() {
    super.initState();
    _timer; // start ticking
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

String _two(int n) => n.toString().padLeft(2, '0');

class _WorldTab extends StatelessWidget {
  const _WorldTab({required this.onAlarms});
  final VoidCallback onAlarms;

  void _addCity(
    BuildContext context,
    AppSettings settings,
    List<String> zones,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, scroll) => ListView(
          controller: scroll,
          children: [
            for (final (name, zone) in worldCities)
              if (!zones.contains(zone))
                ListTile(
                  title: Text(name),
                  onTap: () {
                    settings.setList(_citiesKey, [...zones, zone]);
                    Navigator.pop(sheet);
                  },
                ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final saved = settings.raw('${_citiesKey}Set') == null
        ? _defaultCities
        : settings.list(_citiesKey);
    void save(List<String> zones) {
      settings.setRaw('${_citiesKey}Set', '1');
      settings.setList(_citiesKey, zones);
    }

    return _Ticker(
      period: const Duration(seconds: 1),
      builder: (context) {
        final now = DateTime.now();
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const SizedBox(height: 16),
            Center(
              child: Text(
                '${_two(now.hour)}:${_two(now.minute)}',
                style: text.displayLarge?.copyWith(
                  fontWeight: FontWeight.w300,
                  fontSize: 88,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Center(
              child: Text(
                '${dayLabelLong(now)} · ${_two(now.second)} s',
                style: text.titleMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: FilledButton.tonalIcon(
                onPressed: onAlarms,
                icon: const Icon(Icons.alarm_add_rounded),
                label: const Text('Mes alarmes'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Dans le monde',
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      settings.setRaw('${_citiesKey}Set', '1');
                      _addCity(context, settings, saved);
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Ajouter'),
                  ),
                ],
              ),
            ),
            if (saved.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text('Ajoutez une ville pour suivre son heure.'),
                ),
              ),
            for (final zone in saved)
              Builder(
                builder: (context) {
                  final name = worldCities
                      .firstWhere(
                        (c) => c.$2 == zone,
                        orElse: () => (zone, zone),
                      )
                      .$1;
                  final there = timeIn(zone, now);
                  final dayShift = DateTime(
                    there.time.year,
                    there.time.month,
                    there.time.day,
                  ).difference(DateTime(now.year, now.month, now.day)).inDays;
                  return Dismissible(
                    key: ValueKey(zone),
                    background: ColoredBox(color: scheme.errorContainer),
                    onDismissed: (_) =>
                        save(saved.where((z) => z != zone).toList()),
                    child: ListTile(
                      title: Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${offsetLabel(there.offset)}${dayShift == 0
                            ? ''
                            : dayShift > 0
                            ? ' · demain'
                            : ' · hier'}',
                      ),
                      trailing: Text(
                        '${_two(there.time.hour)}:${_two(there.time.minute)}',
                        style: text.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w300,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

class _TimerTab extends StatelessWidget {
  const _TimerTab();

  static const _presets = [1, 3, 5, 10, 15, 30, 45, 60];

  Future<void> _custom(BuildContext context, ClockController clock) async {
    final minutes = TextEditingController();
    final seconds = TextEditingController();
    Widget field(TextEditingController c, String label) => Expanded(
      child: TextField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(3),
        ],
        textAlign: TextAlign.center,
        decoration: InputDecoration(hintText: '0', labelText: label),
      ),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Durée du minuteur'),
        content: Row(
          children: [
            field(minutes, 'Minutes'),
            const SizedBox(width: 12),
            field(seconds, 'Secondes'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
    if (ok == true) {
      clock.setTimer(
        Duration(
          minutes: int.tryParse(minutes.text) ?? 0,
          seconds: int.tryParse(seconds.text) ?? 0,
        ),
      );
    }
  }

  Future<void> _addExtra(BuildContext context, ClockController clock) async {
    final label = TextEditingController();
    final minutes = TextEditingController(text: '5');
    final seconds = TextEditingController();
    Widget field(TextEditingController c, String hint) => Expanded(
      child: TextField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(3),
        ],
        textAlign: TextAlign.center,
        decoration: InputDecoration(labelText: hint),
      ),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Nouveau minuteur'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: label,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Nom (facultatif)'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                field(minutes, 'Minutes'),
                const SizedBox(width: 12),
                field(seconds, 'Secondes'),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Démarrer'),
          ),
        ],
      ),
    );
    final total = Duration(
      minutes: int.tryParse(minutes.text) ?? 0,
      seconds: int.tryParse(seconds.text) ?? 0,
    );
    if (ok == true && total > Duration.zero) {
      await Reminders.requestPermission();
      clock.addExtra(total, label: label.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final clock = context.watch<ClockController>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return _Ticker(
      period: const Duration(milliseconds: 200),
      builder: (context) {
        final remaining = clock.ringing ? Duration.zero : clock.remaining;
        final total = clock.timerTotal.inMilliseconds;
        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            SizedBox(
              height: 320,
              child: Center(
                child: SizedBox(
                  width: 280,
                  height: 280,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: total == 0
                            ? 0
                            : remaining.inMilliseconds / total,
                        strokeWidth: 10,
                        strokeCap: StrokeCap.round,
                        backgroundColor: scheme.surfaceContainerHighest,
                        color: clock.ringing ? scheme.error : scheme.primary,
                      ),
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              formatCountdown(remaining),
                              style: text.displayLarge?.copyWith(
                                fontWeight: FontWeight.w300,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            if (clock.ringing)
                              Text(
                                'Temps écoulé',
                                style: text.titleMedium?.copyWith(
                                  color: scheme.error,
                                ),
                              )
                            else if (clock.timerPaused)
                              Text('En pause', style: text.titleMedium),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (clock.timerIdle)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in _presets)
                      ChoiceChip(
                        showCheckmark: false,
                        label: Text(m == 60 ? '1 h' : '$m min'),
                        selected: clock.timerTotal == Duration(minutes: m),
                        onSelected: (_) => clock.setTimer(Duration(minutes: m)),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Autre'),
                      onPressed: () => _custom(context, clock),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (clock.ringing)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: scheme.error,
                        foregroundColor: scheme.onError,
                        minimumSize: const Size(200, 56),
                      ),
                      onPressed: clock.resetTimer,
                      icon: const Icon(Icons.notifications_off_outlined),
                      label: const Text('Arrêter'),
                    )
                  else if (clock.timerIdle)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(200, 56),
                      ),
                      onPressed: clock.startTimer,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Démarrer'),
                    )
                  else ...[
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(96, 52),
                      ),
                      onPressed: clock.resetTimer,
                      child: const Text('Annuler'),
                    ),
                    const SizedBox(width: 12),
                    if (clock.timerRunning)
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(80, 52),
                        ),
                        onPressed: clock.addMinute,
                        child: const Text('+1 min'),
                      ),
                    const SizedBox(width: 12),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(110, 52),
                      ),
                      onPressed: clock.timerRunning
                          ? clock.pauseTimer
                          : clock.startTimer,
                      child: Text(clock.timerRunning ? 'Pause' : 'Reprendre'),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 32),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Autres minuteurs',
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _addExtra(context, clock),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Ajouter'),
                  ),
                ],
              ),
            ),
            if (clock.extras.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  'Lancez plusieurs minuteurs à la fois, par exemple pour la cuisine.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            for (final t in clock.extras)
              _ExtraTimerCard(key: ValueKey(t.id), timer: t, clock: clock),
          ],
        );
      },
    );
  }
}

class _StopwatchTab extends StatelessWidget {
  const _StopwatchTab();

  @override
  Widget build(BuildContext context) {
    final clock = context.watch<ClockController>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final laps = clock.laps;

    return Column(
      children: [
        const SizedBox(height: 40),
        _Ticker(
          period: const Duration(milliseconds: 33),
          builder: (_) => Text(
            formatStopwatch(clock.elapsed),
            style: text.displayLarge?.copyWith(
              fontWeight: FontWeight.w300,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: laps.isEmpty
              ? const SizedBox.shrink()
              : ListView.builder(
                  itemCount: laps.length,
                  itemBuilder: (_, i) {
                    final number = laps.length - i;
                    final previous = i + 1 < laps.length
                        ? laps[i + 1]
                        : Duration.zero;
                    return ListTile(
                      dense: true,
                      leading: Text(
                        'Tour $number',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      title: Text(
                        '+${formatStopwatch(laps[i] - previous)}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      trailing: Text(
                        formatStopwatch(laps[i]),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(120, 56),
                ),
                onPressed: clock.watchRunning
                    ? clock.lap
                    : clock.elapsed > Duration.zero
                    ? clock.resetWatch
                    : null,
                child: Text(clock.watchRunning ? 'Tour' : 'Remettre à zéro'),
              ),
              const SizedBox(width: 16),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(120, 56)),
                onPressed: clock.toggleWatch,
                child: Text(
                  clock.watchRunning
                      ? 'Arrêter'
                      : clock.elapsed > Duration.zero
                      ? 'Reprendre'
                      : 'Démarrer',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExtraTimerCard extends StatelessWidget {
  const _ExtraTimerCard({super.key, required this.timer, required this.clock});
  final CountdownTimer timer;
  final ClockController clock;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final t = timer;
    final total = t.total.inMilliseconds;
    final remaining = t.ringing ? Duration.zero : t.remaining;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Card(
        color: t.ringing ? scheme.errorContainer : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t.label.isEmpty ? formatCountdown(t.total) : t.label,
                      style: text.titleSmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Supprimer le minuteur',
                    icon: const Icon(Icons.close),
                    onPressed: () => clock.removeExtra(t),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t.ringing ? 'Temps écoulé' : formatCountdown(remaining),
                      style: text.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w300,
                        color: t.ringing ? scheme.error : null,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  if (t.ringing) ...[
                    OutlinedButton(
                      onPressed: t.restart,
                      child: const Text('Relancer'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: t.dismiss,
                      child: const Text('Arrêter'),
                    ),
                  ] else ...[
                    if (t.running)
                      TextButton(
                        onPressed: t.addMinute,
                        child: const Text('+1 min'),
                      ),
                    IconButton.filledTonal(
                      tooltip: t.running ? 'Pause' : 'Reprendre',
                      icon: Icon(
                        t.running
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      onPressed: t.running ? t.pause : t.resume,
                    ),
                  ],
                ],
              ),
              if (!t.ringing)
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 8),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : remaining.inMilliseconds / total,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlarmsTab extends StatelessWidget {
  const _AlarmsTab();

  Future<void> _edit(
    BuildContext context,
    AlarmStore store, [
    Alarm? alarm,
  ]) async {
    final result = await showModalBottomSheet<Alarm>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AlarmEditor(alarm: alarm?.copy()),
    );
    if (result == null) return;
    await Reminders.requestPermission();
    await store.save(result);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AlarmStore>();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final alarms = store.alarms;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        tooltip: 'Nouvelle alarme',
        onPressed: () => _edit(context, store),
        child: const Icon(Icons.add),
      ),
      body: alarms.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.alarm_off_outlined,
                      size: 64,
                      color: scheme.outline,
                    ),
                    const SizedBox(height: 16),
                    Text('Aucune alarme', style: text.titleMedium),
                    const SizedBox(height: 8),
                    const Text(
                      'Touchez + pour en créer une. Elle sonne même si l\'application est fermée.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                for (final a in alarms)
                  Dismissible(
                    key: ValueKey('alarm-${a.id}'),
                    background: ColoredBox(color: scheme.errorContainer),
                    onDismissed: (_) => store.delete(a),
                    child: ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
                      onTap: () => _edit(context, store, a),
                      title: Text(
                        '${_two(a.hour)}:${_two(a.minute)}',
                        style: text.displaySmall?.copyWith(
                          fontWeight: FontWeight.w300,
                          color: a.enabled ? null : scheme.outline,
                        ),
                      ),
                      subtitle: Text(
                        [
                          if (a.label.isNotEmpty) a.label,
                          daysLabel(a.days),
                        ].join(' · '),
                      ),
                      trailing: Semantics(
                        label: 'Alarme ${_two(a.hour)}:${_two(a.minute)}',
                        child: Switch(
                          value: a.enabled,
                          onChanged: (on) async {
                            if (on) await Reminders.requestPermission();
                            await store.setEnabled(a, on);
                          },
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _AlarmEditor extends StatefulWidget {
  const _AlarmEditor({this.alarm});
  final Alarm? alarm;

  @override
  State<_AlarmEditor> createState() => _AlarmEditorState();
}

class _AlarmEditorState extends State<_AlarmEditor> {
  late final Alarm _alarm =
      widget.alarm ??
      (() {
        final now = DateTime.now().add(const Duration(minutes: 1));
        return Alarm(hour: now.hour, minute: now.minute);
      })();
  late final _label = TextEditingController(text: _alarm.label);

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _alarm.hour, minute: _alarm.minute),
      helpText: "Heure de l'alarme",
    );
    if (t != null) {
      setState(() {
        _alarm.hour = t.hour;
        _alarm.minute = t.minute;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const names = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
    const spoken = [
      'lundi',
      'mardi',
      'mercredi',
      'jeudi',
      'vendredi',
      'samedi',
      'dimanche',
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: TextButton(
                  onPressed: _pickTime,
                  child: Text(
                    '${_two(_alarm.hour)}:${_two(_alarm.minute)}',
                    style: text.displayMedium?.copyWith(
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                children: [
                  for (var d = 1; d <= 7; d++)
                    Semantics(
                      label: spoken[d - 1],
                      child: FilterChip(
                        label: Text(names[d - 1]),
                        selected: _alarm.days.contains(d),
                        showCheckmark: false,
                        onSelected: (on) => setState(
                          () => on ? _alarm.days.add(d) : _alarm.days.remove(d),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(daysLabel(_alarm.days), style: text.bodySmall),
              ),
              TextField(
                controller: _label,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nom (facultatif)',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Annuler'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () {
                      _alarm
                        ..label = _label.text.trim()
                        ..enabled = true;
                      Navigator.pop(context, _alarm);
                    },
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
