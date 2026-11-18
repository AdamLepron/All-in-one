# All-in-One

Une seule application Android (iOS ensuite) qui regroupe galerie, lecteurs audio et vidéo,
documents, notes, fichiers et utilitaires. Développée avec Flutter.

## État

| Étape | Contenu | État |
| --- | --- | --- |
| 1 — Fondations | Navigation à 5 onglets, thèmes (clair, sombre, AMOLED, accent), accueil, recherche, Notes, Calculatrice, Convertisseur | Livrée (0.1.0) |
| 2 — Fichiers et musique | Gestionnaire de fichiers (navigation, copie, déplacement, renommage, corbeille 30 jours, partage), lecteur de musique (bibliothèque, mini-lecteur, écran de lecture, file d'attente, lecture en arrière-plan) | Livrée (0.2.0) |
| 3 — Galerie et vidéo | Galerie (chronologie par jour, albums, favoris, visionneuse avec zoom, partage, corbeille), lecteur vidéo à gestes (saut ±10 s, recherche, luminosité, volume, vitesse, verrouillage, reprise) | Livrée (0.3.0) |
| 4 — Documents et égaliseur | Lecteur de documents (bibliothèque, PDF en défilement continu avec zoom et mode nuit, fichiers texte, reprise), égaliseur (bandes, préréglages, balance gauche/droite, basses, élargissement, amplification) | Livrée (0.4.0) |
| 5 — Outils et enregistreur | Lecteur QR (scan, création, historique), horloge (fuseaux, minuteur, chronomètre), outils capteurs (lampe, boussole, niveau, règle), enregistreur audio | Livrée (0.5.0) |
| 6 — Tâches et agenda | Tâches (saisie en langage naturel, priorités, listes, répétition, glisser pour terminer ou reporter), agenda (vue mois et planning, événements répétés, agendas du téléphone en lecture), rappels par notification | Livrée (0.6.0) |
| 7 — Scanner et nettoyeur | Scanner de documents (détection des bords, multipage, PDF, texte reconnu et cherchable), nettoyeur (doublons, gros fichiers, téléchargements et captures anciens, APK, fichiers temporaires, corbeille) | Livrée (0.7.0) |
| 8 — Éditeur photo | Réglages (luminosité, contraste, saturation, chaleur, fondu, vignette), 12 filtres à intensité réglable, rognage par ratios, rotation, miroir, dessin à main levée, annuler/rétablir, enregistrement en copie JPEG | Livrée (0.8.0) |
| 9 — Transfert et documents | Transfert local (envoi et réception par Wi-Fi via un lien et un QR code, sans application sur l'autre appareil), éditeur de documents texte et Markdown (barre de mise en forme, aperçu, enregistrement automatique, export PDF) | Livrée (0.9.0) |
| 10 — Éditeur vidéo | Montage : découpe, assemblage de plusieurs vidéos, vitesse de 0,25× à 4×, rotation, son d'origine coupé ou remplacé par une musique, export MP4 (H.264) avec progression | Livrée (1.0.0) |
| 11 — Fiabilité et socle | Journal des incidents, grosses bibliothèques fluides, réception de fichiers/texte depuis les autres apps (Partager / Ouvrir avec), recherche universelle étendue (documents, fichiers, scans, rappels…), sauvegarde et restauration complètes, accessibilité (lecteur d'écran, texte agrandi) | Livrée (1.1.0) |
| 12 — Écouter et regarder | Musique : accueil, playlists, file réordonnable, minuterie de sommeil, paroles (.lrc). Égaliseur : préréglages personnels, profil par appareil audio. Vidéo : sous-titres (.srt/.vtt), pistes audio, image dans l'image, lecture suivante, écoute en arrière-plan | Livrée (1.2.1) |
| 13 — Organiser sa vie | Notes : cases à cocher, mise en forme, dossiers, pièces jointes, corbeille. Tâches : étapes, étiquettes, boutons dans la notification. Agenda : vues semaine et jour, création et modification dans les agendas du téléphone. Horloge : alarmes propres (répétition, report), plusieurs minuteurs, sonnerie app fermée. Enregistreur : continue en arrière-plan | Livrée (1.3.1) |
| 14 — Fichiers et documents | Fichiers : archives (zip, extraction zip/tar/tar.gz), catégories, carte SD, recherche globale. Lecteur PDF : recherche avec surlignage, sommaire, annotations (surligneur, stylo, notes). Éditeur : rechercher/remplacer, images, tableaux. Scanner : PDF cherchable, réorganisation, rotation et suppression de pages | Livrée (1.4.0) |
| 15 — Créer | Photo : redressement, texte, exposition et teinte, options d'export (format, qualité, taille). Vidéo : scinder, volume, titres, fondus au noir, montages enregistrés. Galerie : albums personnels, recherche, dossier protégé par code | Livrée (1.5.0) |
| 16 — Finitions des utilitaires | Convertisseur : devises (taux de la BCE, gardés hors ligne). QR : lecture depuis une image, connexion Wi-Fi, contacts (vCard), SMS et position, création Wi-Fi/contact. Capteurs : sonomètre, loupe. Nettoyeur : photos floues, médias des messageries. Transfert : acceptation des envois, « Envoyer par Wi-Fi » dans Fichiers et Galerie | Livrée (1.6.0) |
| 20 — En ligne et ouverture | Radios et podcasts (annuaires ouverts, favoris, abonnements, téléchargements). Dossier protégé chiffré (AES-256-GCM) et « Déplacer vers le dossier protégé » depuis Fichiers. Widgets Android : tâches du jour, note rapide. Tablettes : rail latéral, grilles adaptatives. Langues : français et anglais (coque de l'app). Dossier docs/store : guide de publication, confidentialité, fiche | Livrée (2.0.0) |
| 21 — Montage vidéo renforcé | Filtres (10 looks + luminosité, contraste, saturation), effets (zoom avant/arrière, pulsation, secousse, flou, miroir), formats 16:9 / 9:16 / 1:1 / 4:5 / 4:3 avec remplissage ou bandes, titres animés (fondu, glissé, rebond) avec fond et alignement, autocollants emoji, barre d'outils défilante | Livrée (2.1.0) |
| 22 — Montage multipistes | Transitions entre extraits (fondu noir, flash blanc, glissés, zoom), retrait d'un passage du milieu d'un extrait, photos comme extraits, calques image/vidéo (3 pistes, position glissée dans l'aperçu), plusieurs sons placés sur la frise + enregistrement de voix, titres positionnables librement, aperçu en direct (mouvements, transitions, titres, calques), frise multipistes | Livrée (2.2.0) |
| 23 — Éditeur vidéo refait (façon CapCut) | Plein écran paysage, aperçu + frise multipistes à tête de lecture centrée (glisser pour avancer, pincer ou boutons pour zoomer), lecture continue de tout le montage, barre d'outils qui suit la sélection (diviser, supprimer, vitesse 0,1–8×, volume, filtres, ajuster, effets, transition, segment, pivoter, miroir, dupliquer, déplacer), poignées pour rogner, déplacement des calques/textes/sons sur la frise, annuler/rétablir, brouillons enregistrés | Livrée (3.0.0) |
| 24 — Publicités discrètes | Bannière fine au-dessus de la barre du bas et annonces natives dans l'accueil, les tâches et les listes de modules ; jamais dans l'éditeur vidéo, le dossier protégé, le scanner, le lecteur PDF ni les alarmes. Achat unique « Supprimer les publicités » (Google Play), restauration, formulaire de consentement RGPD (Google UMP). Identifiants de test tant qu'aucun identifiant AdMob réel n'est fourni | Livrée (3.1.0) |

Les 21 modules du cahier des charges sont désormais disponibles ; leurs fonctions les plus avancées (pistes multiples, transitions, titres animés, tableur, présentations) restent à venir.

## Structure

- `lib/core` : réglages, thème, catalogue des modules, utilitaires.
- `lib/shell` : écran principal, onglets, recherche, réglages.
- `lib/modules/<module>` : un dossier par module, qui ne dépend que de `core`.
- `test` : tests unitaires et un parcours complet avec captures (`test/screenshots`).

## Commandes

```sh
flutter test                                # tests
flutter test --update-goldens               # régénérer les captures
flutter build apk --release --split-per-abi # APK de test
```

Les APK sont signés avec `android/app/test.keystore`, une clé de test versionnée pour que
chaque nouvelle version s'installe par-dessus la précédente. À remplacer par une clé privée
avant toute publication sur un store.
