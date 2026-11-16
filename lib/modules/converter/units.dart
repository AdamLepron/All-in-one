import 'package:material_ui/material_ui.dart';

class Unit {
  const Unit(this.name, this.symbol, this.factor, [this.offset = 0]);

  final String name;
  final String symbol;

  /// base = value × factor + offset
  final double factor;
  final double offset;

  double toBase(double value) => value * factor + offset;
  double fromBase(double base) => (base - offset) / factor;
}

class UnitCategory {
  const UnitCategory(this.name, this.icon, this.units);
  final String name;
  final IconData icon;
  final List<Unit> units;
}

double convert(double value, Unit from, Unit to) => to.fromBase(from.toBase(value));

const unitCategories = <UnitCategory>[
  UnitCategory('Longueur', Icons.straighten, [
    Unit('Mètre', 'm', 1),
    Unit('Kilomètre', 'km', 1000),
    Unit('Centimètre', 'cm', 0.01),
    Unit('Millimètre', 'mm', 0.001),
    Unit('Mile', 'mi', 1609.344),
    Unit('Yard', 'yd', 0.9144),
    Unit('Pied', 'ft', 0.3048),
    Unit('Pouce', 'in', 0.0254),
    Unit('Mille marin', 'nmi', 1852),
  ]),
  UnitCategory('Masse', Icons.scale_outlined, [
    Unit('Kilogramme', 'kg', 1),
    Unit('Gramme', 'g', 0.001),
    Unit('Milligramme', 'mg', 0.000001),
    Unit('Tonne', 't', 1000),
    Unit('Livre', 'lb', 0.45359237),
    Unit('Once', 'oz', 0.028349523125),
  ]),
  UnitCategory('Température', Icons.thermostat, [
    Unit('Celsius', '°C', 1, 273.15),
    Unit('Fahrenheit', '°F', 5 / 9, 459.67 * 5 / 9),
    Unit('Kelvin', 'K', 1),
  ]),
  UnitCategory('Volume', Icons.local_drink_outlined, [
    Unit('Litre', 'L', 1),
    Unit('Millilitre', 'mL', 0.001),
    Unit('Centilitre', 'cL', 0.01),
    Unit('Mètre cube', 'm³', 1000),
    Unit('Gallon US', 'gal', 3.785411784),
    Unit('Pinte US', 'pt', 0.473176473),
    Unit('Tasse US', 'cup', 0.2365882365),
    Unit('Once liquide US', 'fl oz', 0.0295735295625),
    Unit('Cuillère à soupe', 'c. à s.', 0.015),
    Unit('Cuillère à café', 'c. à c.', 0.005),
  ]),
  UnitCategory('Surface', Icons.crop_square, [
    Unit('Mètre carré', 'm²', 1),
    Unit('Kilomètre carré', 'km²', 1e6),
    Unit('Centimètre carré', 'cm²', 0.0001),
    Unit('Hectare', 'ha', 10000),
    Unit('Are', 'a', 100),
    Unit('Acre', 'ac', 4046.8564224),
    Unit('Pied carré', 'ft²', 0.09290304),
  ]),
  UnitCategory('Vitesse', Icons.speed, [
    Unit('Kilomètre par heure', 'km/h', 1 / 3.6),
    Unit('Mètre par seconde', 'm/s', 1),
    Unit('Mile par heure', 'mph', 0.44704),
    Unit('Nœud', 'kn', 1852 / 3600),
  ]),
  UnitCategory('Temps', Icons.schedule, [
    Unit('Seconde', 's', 1),
    Unit('Milliseconde', 'ms', 0.001),
    Unit('Minute', 'min', 60),
    Unit('Heure', 'h', 3600),
    Unit('Jour', 'j', 86400),
    Unit('Semaine', 'sem.', 604800),
    Unit('Année', 'an', 31557600),
  ]),
  UnitCategory('Données', Icons.sd_storage_outlined, [
    Unit('Octet', 'o', 1),
    Unit('Kilooctet', 'ko', 1e3),
    Unit('Mégaoctet', 'Mo', 1e6),
    Unit('Gigaoctet', 'Go', 1e9),
    Unit('Téraoctet', 'To', 1e12),
    Unit('Kibioctet', 'Kio', 1024),
    Unit('Mébioctet', 'Mio', 1048576),
    Unit('Gibioctet', 'Gio', 1073741824),
    Unit('Bit', 'bit', 0.125),
  ]),
  UnitCategory('Énergie', Icons.bolt, [
    Unit('Joule', 'J', 1),
    Unit('Kilojoule', 'kJ', 1000),
    Unit('Calorie', 'cal', 4.184),
    Unit('Kilocalorie', 'kcal', 4184),
    Unit('Wattheure', 'Wh', 3600),
    Unit('Kilowattheure', 'kWh', 3.6e6),
  ]),
  UnitCategory('Pression', Icons.compress, [
    Unit('Bar', 'bar', 100000),
    Unit('Pascal', 'Pa', 1),
    Unit('Hectopascal', 'hPa', 100),
    Unit('Atmosphère', 'atm', 101325),
    Unit('PSI', 'psi', 6894.757293168),
    Unit('Millimètre de mercure', 'mmHg', 133.322387415),
  ]),
];
