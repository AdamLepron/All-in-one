# Questionnaire « Sécurité des données » (Google Play)

| Question | Réponse proposée |
|---|---|
| L'application collecte-t-elle des données ? | Non (rien n'est envoyé à un serveur du développeur) |
| L'application partage-t-elle des données ? | Non |
| Données chiffrées en transit ? | Oui, sauf certains flux radio en HTTP choisis par l'utilisateur |
| Suppression des données | Via les réglages de l'app ou la désinstallation |
| Publicité / SDK de suivi | Aucun |

À vérifier avant envoi : les bibliothèques ML Kit (reconnaissance de texte)
fonctionnent sur l'appareil ; contrôlez dans la console que la déclaration
reste cohérente avec les dernières versions des dépendances.

## Justification `MANAGE_EXTERNAL_STORAGE`

« La fonction centrale d'All-in-One inclut un gestionnaire de fichiers :
parcourir, copier, déplacer, compresser et chercher dans tous les dossiers de
l'appareil, ainsi qu'un nettoyeur de stockage. Le sélecteur de fichiers système
ne permet pas de parcourir l'arborescence complète ni d'opérer en lot. »
