import 'package:material_ui/material_ui.dart';

import '../modules/calculator/calculator_page.dart';
import '../modules/calendar/calendar_page.dart';
import '../modules/tasks/tasks_page.dart';
import '../modules/cleaner/cleaner_page.dart';
import '../modules/clock/clock_page.dart';
import '../modules/scanner/scanner_page.dart';
import '../modules/qr/qr_page.dart';
import '../modules/recorder/recorder_page.dart';
import '../modules/sensors/sensors_page.dart';
import '../modules/converter/converter_page.dart';
import '../modules/equalizer/equalizer_page.dart';
import '../modules/files/files_page.dart';
import '../modules/reader/reader_page.dart';
import '../modules/gallery/gallery_page.dart';
import '../modules/video/video_page.dart';
import '../modules/music/music_page.dart';
import '../modules/notes/notes_page.dart';
import '../shell/coming_soon_page.dart';
import 'theme.dart';

/// One entry of the application catalogue.
class AppModule {
  const AppModule(
    this.id,
    this.name,
    this.description,
    this.icon,
    this.family, [
    this.builder,
  ]);

  final String id;
  final String name;
  final String description;
  final IconData icon;
  final Family family;

  /// Null while the module is not built yet.
  final WidgetBuilder? builder;

  bool get available => builder != null;

  void open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute(builder: builder ?? (_) => ComingSoonPage(module: this)),
  );
}

final modules = <AppModule>[
  // Multimédia
  AppModule(
    'gallery',
    'Galerie',
    'Photos et vidéos',
    Icons.photo_library_rounded,
    Family.media,
    (_) => const GalleryPage(),
  ),
  AppModule(
    'video',
    'Lecteur vidéo',
    'Tous formats, gestes',
    Icons.play_circle_rounded,
    Family.media,
    (_) => const VideoPage(),
  ),
  AppModule(
    'music',
    'Musique',
    'Votre bibliothèque audio',
    Icons.music_note_rounded,
    Family.media,
    (_) => const MusicPage(),
  ),
  AppModule(
    'equalizer',
    'Égaliseur',
    'Balance et effets sonores',
    Icons.equalizer_rounded,
    Family.media,
    (_) => const EqualizerPage(),
  ),
  const AppModule(
    'photo_editor',
    'Éditeur photo',
    'Retouche et filtres',
    Icons.auto_fix_high_rounded,
    Family.media,
  ),
  const AppModule(
    'video_editor',
    'Éditeur vidéo',
    'Montage multipiste',
    Icons.movie_edit,
    Family.media,
  ),
  AppModule(
    'recorder',
    'Enregistreur',
    'Notes vocales',
    Icons.mic_rounded,
    Family.media,
    (_) => const RecorderPage(),
  ),
  // Productivité
  AppModule(
    'files',
    'Fichiers',
    'Stockage et dossiers',
    Icons.folder_rounded,
    Family.productivity,
    (_) => const FilesPage(),
  ),
  AppModule(
    'reader',
    'Lecteur de documents',
    'PDF, Office, livres',
    Icons.menu_book_rounded,
    Family.productivity,
    (_) => const ReaderPage(),
  ),
  const AppModule(
    'doc_editor',
    'Éditeur de documents',
    'Texte, tableur, diapos',
    Icons.edit_document,
    Family.productivity,
  ),
  AppModule(
    'notes',
    'Notes',
    'Bloc-notes rapide',
    Icons.sticky_note_2_rounded,
    Family.productivity,
    (_) => const NotesPage(),
  ),
  AppModule(
    'scanner',
    'Scanner',
    'Documents et OCR',
    Icons.document_scanner_rounded,
    Family.productivity,
    (_) => const ScannerPage(),
  ),
  AppModule(
    'tasks',
    'Tâches',
    'Listes et rappels',
    Icons.check_circle_rounded,
    Family.productivity,
    (_) => const TasksPage(),
  ),
  AppModule(
    'calendar',
    'Agenda',
    'Événements',
    Icons.calendar_month_rounded,
    Family.productivity,
    (_) => const CalendarPage(),
  ),
  // Utilitaires
  AppModule(
    'calculator',
    'Calculatrice',
    'Standard et scientifique',
    Icons.calculate_rounded,
    Family.tools,
    (_) => const CalculatorPage(),
  ),
  AppModule(
    'converter',
    'Convertisseur',
    'Unités et mesures',
    Icons.swap_horiz_rounded,
    Family.tools,
    (_) => const ConverterPage(),
  ),
  AppModule(
    'qr',
    'Lecteur QR',
    'Codes QR et codes-barres',
    Icons.qr_code_scanner_rounded,
    Family.tools,
    (_) => const QrPage(),
  ),
  AppModule(
    'clock',
    'Horloge',
    'Minuteur, chrono, fuseaux',
    Icons.alarm_rounded,
    Family.tools,
    (_) => const ClockPage(),
  ),
  AppModule(
    'sensors',
    'Outils capteurs',
    'Lampe, boussole, niveau, règle',
    Icons.explore_rounded,
    Family.tools,
    (_) => const SensorsPage(),
  ),
  AppModule(
    'cleaner',
    'Nettoyeur',
    'Libérer du stockage',
    Icons.cleaning_services_rounded,
    Family.tools,
    (_) => const CleanerPage(),
  ),
  const AppModule(
    'transfer',
    'Transfert local',
    'Envoi entre appareils',
    Icons.wifi_tethering_rounded,
    Family.tools,
  ),
];

AppModule moduleById(String id) => modules.firstWhere((m) => m.id == id);

List<AppModule> modulesOf(Family family) =>
    modules.where((m) => m.family == family).toList();
