# Questionnaire « Sécurité des données » (Google Play)

| Question | Réponse proposée |
|---|---|
| L'application collecte-t-elle des données ? | Oui, uniquement via le SDK publicitaire (Google AdMob) |
| Types de données | Identifiants (identifiant publicitaire), données d'utilisation et diagnostics des annonces, localisation approximative (IP) |
| Finalité | Publicité ou marketing ; analyse (mesure des annonces) |
| Partagées avec des tiers ? | Oui : Google (AdMob) |
| Collecte facultative ? | Oui pour l'identifiant publicitaire (choix de consentement, désactivation possible) |
| Contenu de l'utilisateur (notes, photos, fichiers, audio) | Non collecté, non partagé |
| Données chiffrées en transit ? | Oui (AdMob) ; certains flux radio choisis par l'utilisateur sont en HTTP |
| Suppression des données | Via les réglages de l'appli ou la désinstallation ; l'identifiant publicitaire se réinitialise dans les réglages Android |
| Achats intégrés | Oui : « Supprimer les publicités » (produit géré unique) |
| Déclaration « contient des annonces » | Oui |

À vérifier avant envoi : les bibliothèques ML Kit (reconnaissance de texte)
fonctionnent sur l'appareil ; contrôlez dans la console que la déclaration
reste cohérente avec les dernières versions des dépendances.

## Justification `MANAGE_EXTERNAL_STORAGE`

« La fonction centrale d'All-in-One inclut un gestionnaire de fichiers :
parcourir, copier, déplacer, compresser et chercher dans tous les dossiers de
l'appareil, ainsi qu'un nettoyeur de stockage. Le sélecteur de fichiers système
ne permet pas de parcourir l'arborescence complète ni d'opérer en lot. »
