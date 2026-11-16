import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Cities offered for the world clock: display name and tz database zone.
const worldCities = <(String, String)>[
  ('Paris', 'Europe/Paris'),
  ('Londres', 'Europe/London'),
  ('Lisbonne', 'Europe/Lisbon'),
  ('Madrid', 'Europe/Madrid'),
  ('Berlin', 'Europe/Berlin'),
  ('Rome', 'Europe/Rome'),
  ('Athènes', 'Europe/Athens'),
  ('Istanbul', 'Europe/Istanbul'),
  ('Moscou', 'Europe/Moscow'),
  ('Casablanca', 'Africa/Casablanca'),
  ('Alger', 'Africa/Algiers'),
  ('Tunis', 'Africa/Tunis'),
  ('Dakar', 'Africa/Dakar'),
  ('Abidjan', 'Africa/Abidjan'),
  ('Le Caire', 'Africa/Cairo'),
  ('Johannesburg', 'Africa/Johannesburg'),
  ('Nairobi', 'Africa/Nairobi'),
  ('Dubaï', 'Asia/Dubai'),
  ('Mumbai', 'Asia/Kolkata'),
  ('Bangkok', 'Asia/Bangkok'),
  ('Singapour', 'Asia/Singapore'),
  ('Hong Kong', 'Asia/Hong_Kong'),
  ('Pékin', 'Asia/Shanghai'),
  ('Séoul', 'Asia/Seoul'),
  ('Tokyo', 'Asia/Tokyo'),
  ('Sydney', 'Australia/Sydney'),
  ('Auckland', 'Pacific/Auckland'),
  ('Honolulu', 'Pacific/Honolulu'),
  ('Los Angeles', 'America/Los_Angeles'),
  ('Denver', 'America/Denver'),
  ('Chicago', 'America/Chicago'),
  ('New York', 'America/New_York'),
  ('Montréal', 'America/Toronto'),
  ('Mexico', 'America/Mexico_City'),
  ('Bogota', 'America/Bogota'),
  ('São Paulo', 'America/Sao_Paulo'),
  ('Buenos Aires', 'America/Argentina/Buenos_Aires'),
  ('La Réunion', 'Indian/Reunion'),
  ('Fort-de-France', 'America/Martinique'),
  ('Nouméa', 'Pacific/Noumea'),
];

bool _ready = false;

/// Current time in [zone], and its difference with the device's time.
({DateTime time, Duration offset}) timeIn(String zone, DateTime now) {
  if (!_ready) {
    tzdata.initializeTimeZones();
    _ready = true;
  }
  final there = tz.TZDateTime.from(now, tz.getLocation(zone));
  final wall = DateTime(
    there.year,
    there.month,
    there.day,
    there.hour,
    there.minute,
    there.second,
  );
  return (time: wall, offset: there.timeZoneOffset - now.timeZoneOffset);
}

/// "Même heure", "+6 h", "−4 h 30".
String offsetLabel(Duration offset) {
  if (offset == Duration.zero) return 'Même heure';
  final minutes = offset.inMinutes.abs();
  final rest = minutes % 60;
  return '${offset.isNegative ? '−' : '+'}${minutes ~/ 60} h${rest == 0 ? '' : ' ${rest.toString().padLeft(2, '0')}'}';
}
