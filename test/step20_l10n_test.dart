import 'package:all_in_one/core/l10n.dart';
import 'package:all_in_one/core/modules.dart';
import 'package:all_in_one/core/settings.dart';
import 'package:all_in_one/core/theme.dart';
import 'package:all_in_one/core/util.dart';
import 'package:all_in_one/shell/settings_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  tearDown(() => L10n.use(AppLanguage.fr, const Locale('fr')));

  test(
    'automatic follows the phone: French stays French, others get English',
    () {
      L10n.use(AppLanguage.system, const Locale('fr', 'CA'));
      expect(L10n.english, isFalse);
      L10n.use(AppLanguage.system, const Locale('de'));
      expect(L10n.english, isTrue);
      L10n.use(AppLanguage.system, const Locale('en', 'US'));
      expect(L10n.english, isTrue);
      L10n.use(AppLanguage.fr, const Locale('en'));
      expect(L10n.english, isFalse);
      L10n.use(AppLanguage.en, const Locale('fr'));
      expect(L10n.english, isTrue);
    },
  );

  test(
    'tr: translated in English, untouched in French, French when unknown',
    () {
      L10n.use(AppLanguage.fr, const Locale('fr'));
      expect(tr('Notes récentes'), 'Notes récentes');
      L10n.use(AppLanguage.en, const Locale('fr'));
      expect(tr('Notes récentes'), 'Recent notes');
      expect(tr('Phrase pas encore traduite'), 'Phrase pas encore traduite');
      expect(L10n.locale.languageCode, 'en');
    },
  );

  test('every module and family has an English name and description', () {
    final known = englishKeys.toSet();
    final missing = <String>[];
    for (final m in modules) {
      L10n.use(AppLanguage.fr, const Locale('fr'));
      final fr = (m.name, m.description);
      for (final text in [fr.$1, fr.$2]) {
        if (!known.contains(text)) missing.add('${m.id}: $text');
      }
    }
    L10n.use(AppLanguage.fr, const Locale('fr'));
    for (final f in Family.values) {
      if (!known.contains(f.label)) missing.add('famille ${f.label}');
    }
    expect(missing, isEmpty);
  });

  test(
    'English module names differ from the French ones where they should',
    () {
      L10n.use(AppLanguage.en, const Locale('fr'));
      expect(moduleById('gallery').name, 'Gallery');
      expect(moduleById('tasks').name, 'Tasks');
      expect(Family.tools.label, 'Utilities');
      L10n.use(AppLanguage.fr, const Locale('fr'));
      expect(moduleById('gallery').name, 'Galerie');
    },
  );

  test('dates are written in the chosen language', () {
    final d = DateTime(2020, 3, 4); // a Wednesday, long ago
    L10n.use(AppLanguage.fr, const Locale('fr'));
    expect(dayLabel(d), '4 mars 2020');
    expect(dayLabelLong(d), 'mercredi 4 mars');
    L10n.use(AppLanguage.en, const Locale('fr'));
    expect(dayLabel(d), 'March 4 2020');
    expect(dayLabelLong(d), 'Wednesday, March 4');
    final now = DateTime.now();
    expect(dayLabel(now), 'Today');
  });

  test('the language choice is saved', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppSettings(await SharedPreferences.getInstance());
    expect(s.language, AppLanguage.system);
    s.language = AppLanguage.en;
    expect(
      AppSettings(await SharedPreferences.getInstance()).language,
      AppLanguage.en,
    );
    SharedPreferences.setMockInitialValues({'language': 'klingon'});
    expect(
      AppSettings(await SharedPreferences.getInstance()).language,
      AppLanguage.system,
    );
  });

  testWidgets('settings: choosing English switches the labels', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(await SharedPreferences.getInstance());
    Widget app() => ChangeNotifierProvider.value(
      value: settings,
      child: Consumer<AppSettings>(
        builder: (context, s, _) {
          L10n.use(s.language, const Locale('fr'));
          return MaterialApp(
            theme: buildTheme(const Color(0xFF5B5BD6), Brightness.light),
            home: const SettingsPage(),
          );
        },
      ),
    );
    await tester.pumpWidget(app());
    expect(find.text('Réglages'), findsOneWidget);
    expect(find.text('Sombre'), findsOneWidget);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    await tester.tap(find.text('Français'));
    await tester.pumpAndSettle();
    expect(find.text('Réglages'), findsOneWidget);
  });
}
