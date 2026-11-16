# All-in-One

Une seule application Android (iOS ensuite) qui regroupe galerie, lecteurs audio et vidéo,
documents, notes, fichiers et utilitaires. Développée avec Flutter.

## État

| Étape | Contenu | État |
| --- | --- | --- |
| 1 — Fondations | Navigation à 5 onglets, thèmes (clair, sombre, AMOLED, accent), accueil, recherche, Notes, Calculatrice, Convertisseur | Livrée (0.1.0) |

Les 18 autres modules apparaissent dans l'application avec l'étiquette « Bientôt ».

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
