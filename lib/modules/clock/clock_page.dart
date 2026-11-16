import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/platform.dart';
import '../../core/settings.dart';
import '../../core/util.dart';
import '../files/files_ui.dart' show showMessage;
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
        0 => const _WorldTab(),
        1 => const _TimerTab(),
        _ => const _StopwatchTab(),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.public), label: 'Horloge'),
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
  const _WorldTab();

  Future<void> _newAlarm(BuildContext context) async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      helpText: "Heure de l'alarme",
    );
    if (time == null) return;
    final ok = await MediaChannel.setAlarm(
      time.hour,
      time.minute,
      'All-in-One',
    );
    if (context.mounted && !ok) {
      showMessage(
        context,
        "Aucune application d'horloge n'a pu créer l'alarme",
      );
    }
  }

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
                onPressed: () => _newAlarm(context),
                icon: const Icon(Icons.alarm_add_rounded),
                label: const Text('Créer une alarme'),
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
        return Column(
          children: [
            Expanded(
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
