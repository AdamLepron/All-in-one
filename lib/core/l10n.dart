import 'dart:ui';

import 'settings.dart';

/// Languages of the app.
enum AppLanguage {
  system('Automatique', 'Automatic'),
  fr('Français', 'Français'),
  en('English', 'English');

  const AppLanguage(this.labelFr, this.labelEn);
  final String labelFr;
  final String labelEn;
}

/// The language in use. French is the language the app is written in; the
/// others come from [_english] and fall back to French for anything not yet
/// translated, so a screen is never left blank.
class L10n {
  static bool _english = false;

  static bool get english => _english;

  /// Chooses the language for [choice]; "automatic" follows the phone:
  /// French phones get French, every other language gets English.
  static void use(AppLanguage choice, Locale device) {
    _english = switch (choice) {
      AppLanguage.fr => false,
      AppLanguage.en => true,
      AppLanguage.system => device.languageCode != 'fr',
    };
  }

  static Locale get locale => Locale(_english ? 'en' : 'fr');
}

/// The text in the current language: [fr] is the French original.
String tr(String fr) => L10n.english ? (_english[fr] ?? fr) : fr;

extension LanguageSetting on AppSettings {
  AppLanguage get language {
    final raw = this.raw('language');
    return AppLanguage.values.firstWhere(
      (l) => l.name == raw,
      orElse: () => AppLanguage.system,
    );
  }

  set language(AppLanguage value) => setRaw('language', value.name);
}

/// English texts, keyed by their French original.
const _english = <String, String>{
  // Families and navigation
  'Multimédia': 'Media',
  'Productivité': 'Productivity',
  'Utilitaires': 'Utilities',
  'Accueil': 'Home',
  'Médias': 'Media',
  'Documents': 'Documents',
  'Outils': 'Tools',
  'Recherche': 'Search',
  'Créer': 'Create',
  // Modules
  'Galerie': 'Gallery',
  'Photos et vidéos': 'Photos and videos',
  'Lecteur vidéo': 'Video player',
  'Tous formats, gestes': 'Every format, gestures',
  'Musique': 'Music',
  'Votre bibliothèque audio': 'Your audio library',
  'Radios et podcasts': 'Radio and podcasts',
  'Écoutez en ligne': 'Listen online',
  'Égaliseur': 'Equalizer',
  'Balance et effets sonores': 'Balance and sound effects',
  'Éditeur photo': 'Photo editor',
  'Retouche et filtres': 'Retouching and filters',
  'Éditeur vidéo': 'Video editor',
  'Couper, assembler, vitesse, musique': 'Cut, join, speed, music',
  'Enregistreur': 'Recorder',
  'Notes vocales': 'Voice notes',
  'Fichiers': 'Files',
  'Stockage et dossiers': 'Storage and folders',
  'Lecteur de documents': 'Document reader',
  'PDF, Office, livres': 'PDF, Office, books',
  'Éditeur de documents': 'Document editor',
  'Texte et Markdown, export PDF': 'Text and Markdown, PDF export',
  'Notes': 'Notes',
  'Bloc-notes rapide': 'Quick notepad',
  'Scanner': 'Scanner',
  'Documents et OCR': 'Documents and OCR',
  'Tâches': 'Tasks',
  'Listes et rappels': 'Lists and reminders',
  'Agenda': 'Calendar',
  'Événements': 'Events',
  'Calculatrice': 'Calculator',
  'Standard et scientifique': 'Standard and scientific',
  'Convertisseur': 'Converter',
  'Unités et mesures': 'Units and measures',
  'Lecteur QR': 'QR reader',
  'Codes QR et codes-barres': 'QR codes and barcodes',
  'Horloge': 'Clock',
  'Minuteur, chrono, fuseaux': 'Timer, stopwatch, time zones',
  'Outils capteurs': 'Sensor tools',
  'Lampe, boussole, niveau, règle': 'Torch, compass, level, ruler',
  'Nettoyeur': 'Cleaner',
  'Libérer du stockage': 'Free up storage',
  'Transfert local': 'Local transfer',
  'Envoi par Wi-Fi, sans Internet': 'Send over Wi-Fi, no Internet',
  // Home
  'Bonne nuit': 'Good night',
  'Bonjour': 'Good morning',
  'Bonsoir': 'Good evening',
  'Reprendre': 'Resume',
  'Raccourcis': 'Shortcuts',
  'Notes récentes': 'Recent notes',
  'Tout voir': 'See all',
  'Aucune note pour le moment': 'No notes yet',
  'Appuyez pour écrire la première': 'Tap to write the first one',
  "Appuyez longuement sur un module pour l'épingler ici.":
      'Long-press a module to pin it here.',
  'Toute la journée': 'All day',
  // Create sheet
  'Nouvelle note': 'New note',
  'Tâches du jour': 'Tasks for today',
  'Rien de prévu': 'Nothing planned',
  'Note rapide': 'Quick note',
  'Nouvelle tâche': 'New task',
  'Nouvel événement': 'New event',
  'Enregistrement audio': 'Audio recording',
  'Scanner un document': 'Scan a document',
  'Nouveau document': 'New document',
  // Settings
  'Réglages': 'Settings',
  'Thème': 'Theme',
  'Système': 'System',
  'Clair': 'Light',
  'Sombre': 'Dark',
  'Noir AMOLED': 'AMOLED black',
  'Fond noir pur en thème sombre': 'Pure black background in the dark theme',
  "Couleur d'accent": 'Accent colour',
  'Langue': 'Language',
  'Données': 'Data',
  'Sauvegarde et restauration': 'Backup and restore',
  'Notes, tâches, événements, réglages': 'Notes, tasks, events, settings',
  'Diagnostic': 'Diagnostics',
  "Journal d'incidents": 'Incident log',
  'À propos': 'About',
  // Search
  'Rechercher': 'Search',
  // Common
  'Annuler': 'Cancel',
  'Enregistrer': 'Save',
  'Supprimer': 'Delete',
  'Fermer': 'Close',
  'Aujourd\'hui': 'Today',
  'Hier': 'Yesterday',
};

/// Every key of the catalogue, for tests that check nothing is forgotten.
Iterable<String> get englishKeys => _english.keys;

const _monthsEn = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
const _weekdaysEn = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// Month name (0-based index) in the current language, lower-case in French.
String monthName(int index0, List<String> french) =>
    L10n.english ? _monthsEn[index0] : french[index0];

String weekdayName(int index0, List<String> french) =>
    L10n.english ? _weekdaysEn[index0] : french[index0];
