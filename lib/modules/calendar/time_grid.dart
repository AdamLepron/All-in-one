import 'package:material_ui/material_ui.dart';

import '../../core/util.dart';
import '../tasks/organizer_store.dart';

/// An event placed on a day's timeline.
class PlacedEvent {
  PlacedEvent(
    this.event,
    this.startMinute,
    this.endMinute,
    this.lane,
    this.lanes,
  );
  final Event event;

  /// Minutes since midnight, clamped to the day.
  final int startMinute;
  final int endMinute;

  /// Column of the event among [lanes] side by side while others overlap it.
  final int lane;
  final int lanes;
}

/// Places the timed events of [day]: events that overlap share the width,
/// each in its own lane. All-day events are not placed (see [allDayOf]).
List<PlacedEvent> layoutDay(List<Event> events, DateTime day) {
  final from = dayOf(day);
  final to = DateTime(from.year, from.month, from.day + 1);
  final items = <(Event, int, int)>[];
  for (final e in events) {
    if (e.allDay || !e.start.isBefore(to) || !e.end.isAfter(from)) continue;
    final start = e.start.isBefore(from)
        ? 0
        : e.start.difference(from).inMinutes;
    var end = e.end.isAfter(to) ? 24 * 60 : e.end.difference(from).inMinutes;
    // Very short events stay tappable: at least 30 minutes tall.
    if (end - start < 30) end = (start + 30).clamp(0, 24 * 60);
    items.add((e, start, end));
  }
  items.sort((a, b) {
    final c = a.$2.compareTo(b.$2);
    return c != 0 ? c : b.$3.compareTo(a.$3);
  });

  final placed = <PlacedEvent>[];
  var cluster = <(Event, int, int, int)>[]; // event, start, end, lane
  var clusterEnd = -1;
  var laneEnds = <int>[];

  void flush() {
    for (final c in cluster) {
      placed.add(PlacedEvent(c.$1, c.$2, c.$3, c.$4, laneEnds.length));
    }
    cluster = [];
    laneEnds = [];
  }

  for (final (e, start, end) in items) {
    if (cluster.isNotEmpty && start >= clusterEnd) flush();
    var lane = laneEnds.indexWhere((l) => l <= start);
    if (lane < 0) {
      laneEnds.add(end);
      lane = laneEnds.length - 1;
    } else {
      laneEnds[lane] = end;
    }
    cluster.add((e, start, end, lane));
    clusterEnd = cluster.fold<int>(0, (m, c) => c.$3 > m ? c.$3 : m);
  }
  flush();
  return placed;
}

/// Events shown in the all-day strip of [day]: all-day ones, and timed
/// events lasting a whole day or more.
List<Event> allDayOf(List<Event> events, DateTime day) {
  final from = dayOf(day);
  final to = DateTime(from.year, from.month, from.day + 1);
  return [
    for (final e in events)
      if (e.start.isBefore(to) &&
          e.end.isAfter(from) &&
          (e.allDay || (!e.start.isAfter(from) && !e.end.isBefore(to))))
        e,
  ];
}

const _letters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

/// A timeline for one or several days: hours down the side, one column per
/// day, events as blocks. Long-press an empty spot to create an event.
class TimeGrid extends StatefulWidget {
  const TimeGrid({
    super.key,
    required this.days,
    required this.eventsOn,
    required this.color,
    required this.onEvent,
    required this.onCreate,
    required this.onDay,
    this.selected,
    this.hourHeight = 56,
  });

  final List<DateTime> days;
  final List<Event> Function(DateTime day) eventsOn;
  final Color Function(Event) color;
  final ValueChanged<Event> onEvent;

  /// Called with the day and hour pressed.
  final void Function(DateTime day, int hour) onCreate;

  /// Called when a day heading is tapped.
  final ValueChanged<DateTime> onDay;
  final DateTime? selected;
  final double hourHeight;

  @override
  State<TimeGrid> createState() => _TimeGridState();
}

class _TimeGridState extends State<TimeGrid> {
  static const _gutter = 44.0;
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    // Opens around the current hour, or 7 a.m. on other days.
    final now = DateTime.now();
    final today = widget.days.any((d) => dayOf(d) == dayOf(now));
    final hour = today ? (now.hour - 1).clamp(0, 22) : 7;
    _scroll = ScrollController(initialScrollOffset: hour * widget.hourHeight);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String _hm(DateTime d) => '${d.hour}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = dayOf(DateTime.now());
    final days = widget.days;
    final events = [for (final d in days) widget.eventsOn(d)];
    final allDay = [
      for (var i = 0; i < days.length; i++) allDayOf(events[i], days[i]),
    ];
    final maxAllDay = allDay.fold<int>(
      0,
      (m, l) => l.length > m ? l.length : m,
    );

    return Column(
      children: [
        // Day headings.
        Row(
          children: [
            const SizedBox(width: _gutter),
            for (final d in days)
              Expanded(
                child: InkWell(
                  onTap: () => widget.onDay(d),
                  child: Semantics(
                    label: dayLabelLong(d),
                    button: true,
                    excludeSemantics: true,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        children: [
                          Text(
                            _letters[d.weekday - 1],
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: dayOf(d) == today
                                  ? scheme.primary
                                  : dayOf(d) == widget.selected
                                  ? scheme.primaryContainer
                                  : null,
                            ),
                            child: Text(
                              '${d.day}',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: dayOf(d) == today
                                    ? scheme.onPrimary
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        // All-day strip.
        if (maxAllDay > 0)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(width: _gutter),
              for (var i = 0; i < days.length; i++)
                Expanded(
                  child: Column(
                    children: [
                      for (final e in allDay[i].take(3))
                        Padding(
                          padding: const EdgeInsets.fromLTRB(1, 1, 1, 0),
                          child: Material(
                            color: widget.color(e).withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(4),
                            child: InkWell(
                              onTap: () => widget.onEvent(e),
                              child: SizedBox(
                                width: double.infinity,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 3,
                                    vertical: 2,
                                  ),
                                  child: Text(
                                    e.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (allDay[i].length > 3)
                        Text(
                          '+${allDay[i].length - 3}',
                          style: const TextStyle(fontSize: 11),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            child: SizedBox(
              height: 24 * widget.hourHeight,
              child: LayoutBuilder(
                builder: (context, box) {
                  final colWidth = (box.maxWidth - _gutter) / days.length;
                  final now = DateTime.now();
                  return Stack(
                    children: [
                      for (var h = 0; h < 24; h++) ...[
                        Positioned(
                          top: h * widget.hourHeight,
                          left: _gutter,
                          right: 0,
                          child: Divider(
                            height: 1,
                            color: scheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        if (h > 0)
                          Positioned(
                            top: h * widget.hourHeight - 8,
                            left: 0,
                            width: _gutter - 6,
                            child: Text(
                              '$h h',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                      for (var i = 0; i < days.length; i++) ...[
                        // Long press on an empty spot creates an event there.
                        Positioned(
                          left: _gutter + i * colWidth,
                          width: colWidth,
                          top: 0,
                          bottom: 0,
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onLongPressStart: (d) => widget.onCreate(
                              days[i],
                              (d.localPosition.dy / widget.hourHeight)
                                  .floor()
                                  .clamp(0, 23),
                            ),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(
                                    color: scheme.outlineVariant.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        for (final p in layoutDay(events[i], days[i]))
                          Positioned(
                            left:
                                _gutter +
                                i * colWidth +
                                p.lane * colWidth / p.lanes +
                                1,
                            width: colWidth / p.lanes - 2,
                            top: p.startMinute / 60 * widget.hourHeight,
                            height:
                                (p.endMinute - p.startMinute) /
                                    60 *
                                    widget.hourHeight -
                                1,
                            child: Material(
                              color: widget
                                  .color(p.event)
                                  .withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(6),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => widget.onEvent(p.event),
                                child: Padding(
                                  padding: const EdgeInsets.all(3),
                                  child: Text(
                                    days.length == 1
                                        ? '${p.event.title}\n${_hm(p.event.start)} – ${_hm(p.event.end)}'
                                        : p.event.title,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: days.length == 1 ? 3 : 4,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      height: 1.15,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (dayOf(days[i]) == today)
                          Positioned(
                            left: _gutter + i * colWidth,
                            width: colWidth,
                            top:
                                (now.hour * 60 + now.minute) /
                                    60 *
                                    widget.hourHeight -
                                1,
                            child: Container(height: 2, color: scheme.error),
                          ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
