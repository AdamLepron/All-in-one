# Fiche de publication — Google Play Store

**Application** : All-in-One · **Identifiant** : `com.wargheadstudio.allinone` · **Version** : 3.2.1 (code 28)
Tout ce qui suit est à copier-coller dans la Play Console. Les fichiers graphiques sont dans `docs/store/assets/`.

---

## 1. Avant de commencer (à faire une seule fois)

| Étape | Détail |
|---|---|
| Compte développeur | https://play.google.com/console — 25 $ une fois. Compte « personnel » : **12 testeurs pendant 14 jours minimum** avant de pouvoir publier en production (règle Google pour les nouveaux comptes personnels). Compte « organisation » : pas de cette règle, mais il faut un numéro D-U-N-S. |
| Clé de signature | Voir `PUBLICATION.md` §1 (keystore personnel, **à sauvegarder**). La clé de test du dépôt ne doit jamais servir. |
| Fichier à envoyer | `flutter build appbundle --release` → `app-release.aab` (le .aab, pas l'APK). |
| AdMob + produit d'achat | `PUBLICATION.md` §3 bis : identifiants AdMob réels, produit `remove_ads`. |
| Page de confidentialité | Publier `PRIVACY.md` sur une page web publique (GitHub Pages, site perso…) : Google exige une **adresse web**. Y mettre votre contact. |

---

## 2. Fiche principale

**Nom de l'application** (30 car. max) :
`All-in-One : notes et outils`

**Description courte** (80 car. max) :
`Notes, fichiers, musique, photos, vidéo, scanner… 21 applis en une seule.`

**Description complète** (4000 car. max) :

```
All-in-One remplace vos applications du quotidien par une seule, rapide, en français, qui garde vos données sur votre téléphone. Pas de compte à créer.

MÉDIAS
• Galerie : photos, vidéos, albums, recherche, diaporama, dossier protégé chiffré par code.
• Lecteur de musique : playlists, égaliseur, minuterie de sommeil, paroles, lecture en arrière-plan.
• Lecteur vidéo : reprise de lecture, vitesse, image dans l'image.
• Radios et podcasts : annuaire ouvert, favoris, abonnements, téléchargement d'épisodes.
• Retouche photo : recadrer, filtres, réglages, texte.
• Éditeur vidéo façon montage : plusieurs pistes (vidéo, image, texte, sons), découpe et segments, vitesse de 0,1× à 8×, filtres, effets, transitions, titres animés, autocollants, musique et voix off, formats 16:9 / 9:16 / 1:1, annuler et rétablir, export MP4.

DOCUMENTS
• Notes (Markdown, étiquettes, couleurs), documents, tâches avec rappels et agenda (récurrences, rappels, événements du téléphone).
• Lecteur de PDF : table des matières, recherche, annotations, mode lecture.
• Scanner de documents : détection des bords, PDF multi-pages, texte reconnu.

OUTILS
• Gestionnaire de fichiers complet : copier, déplacer, compresser (zip), rechercher, catégories, nettoyeur de stockage.
• QR codes : lecture (caméra ou image), création, connexion Wi-Fi, contacts.
• Convertisseur d'unités et de devises, calculatrice.
• Horloge, réveils, minuteur, chronomètre.
• Enregistreur vocal, sonomètre, loupe, boussole, lampe torche.
• Transfert Wi-Fi vers l'ordinateur, sauvegarde et restauration de toutes vos données.

POUR VOUS
• Adapté aux tablettes et au mode paysage.
• Français et anglais.
• Thème clair, sombre ou automatique.
• Vos données restent sur l'appareil. Les publicités sont discrètes (une bannière fine et quelques annonces dans les listes, jamais dans l'éditeur, le dossier protégé ou les alarmes) et peuvent être supprimées définitivement par un achat unique.

Aucune inscription, aucune donnée envoyée à nos serveurs : nous n'en avons pas.
```

**Notes de version** (500 car. max, « Nouveautés ») :
```
• Éditeur vidéo entièrement refait : plusieurs pistes, découpe, segments, vitesse, filtres, transitions, textes et sons.
• Radios et podcasts.
• Widgets : tâches du jour et note rapide.
• Dossier protégé chiffré.
• Publicités discrètes, supprimables par un achat unique.
• Corrections et améliorations de stabilité.
```

---

## 3. Paramètres de l'application

| Champ | Valeur |
|---|---|
| Application ou jeu | Application |
| Gratuite ou payante | Gratuite (achat intégré : « Supprimer les publicités ») |
| Catégorie | **Outils** (alternative : Productivité) |
| Étiquettes (tags) | Outils, Éditeur vidéo, Gestionnaire de fichiers, Notes (à choisir parmi la liste Google) |
| Langue par défaut | Français (France) — fr-FR. Ajouter anglais (en-US) avec la traduction ci-dessous |
| E-mail de contact | **à renseigner** (public sur la fiche) |
| Site web | facultatif |
| Politique de confidentialité | **adresse web** de la page publiée à partir de `PRIVACY.md` |
| Contient des annonces | **Oui** |
| Achats intégrés | **Oui** (produit géré `remove_ads`, prix à choisir, ex. 2,99 €) |

### Traduction anglaise (en-US)
- Nom : `All-in-One: notes & tools`
- Courte : `Notes, files, music, photos, video, scanner… 21 everyday apps in one.`
- Complète : reprendre le texte français, traduit (je peux la fournir sur demande).

---

## 4. Éléments graphiques

| Élément | Taille | Fichier / consigne |
|---|---|---|
| Icône | 512 × 512 PNG | `docs/store/assets/icone-512.png` |
| Image de présentation | 1024 × 500 | `docs/store/assets/image-de-presentation-1024x500.png` |
| Captures d'écran téléphone | 2 à 8, 16:9 ou 9:16, 320–3840 px | à prendre sur un vrai téléphone. Écrans conseillés : Accueil · Notes · Éditeur vidéo (paysage, frise visible) · Galerie · Gestionnaire de fichiers · Scanner · Lecteur de musique · Réglages |
| Captures tablette 7" et 10" | 1 à 8 chacune (recommandé) | mêmes écrans sur une tablette ou un émulateur : l'application a une mise en page adaptée |

> L'icône de l'application elle-même (écran d'accueil du téléphone) a été remplacée dans la version en cours : elle utilisait encore l'icône Flutter par défaut, que Google déconseille.

---

## 5. Classification du contenu (questionnaire IARC)

Réponses proposées (à vérifier au moment du remplissage) :
- Violence, sexe, langage grossier, drogue, jeux d'argent : **Non**.
- Contenu généré par les utilisateurs / partage entre utilisateurs : **Non** (aucun réseau social, aucun chat). Le « transfert Wi-Fi » est local, vers l'ordinateur de l'utilisateur.
- Partage de la localisation : **Non**. Achats numériques : **Oui**. Publicités : **Oui**.
- Résultat attendu : **PEGI 3 / Tous publics**.

**Public cible** : 13 ans et plus (ne pas cocher « enfants » : cela imposerait la politique « Famille », incompatible avec les annonces personnalisées).

---

## 6. Sécurité des données

À reprendre de `DATA_SAFETY.md` :
- Données collectées via le SDK publicitaire (Google AdMob) : identifiant publicitaire, données d'utilisation et diagnostics des annonces, localisation approximative (IP). Finalités : publicité, analyses. Partagées avec Google. Collecte facultative (consentement).
- Contenu de l'utilisateur (notes, photos, fichiers, audio, dossier protégé) : **non collecté, non partagé**.
- Chiffrement en transit : oui. Suppression : désinstallation ou réglages de l'appli.

---

## 7. Autorisations sensibles — justifications à fournir

| Autorisation | Justification (à coller si Google la demande) |
|---|---|
| **Accès à tous les fichiers** (`MANAGE_EXTERNAL_STORAGE`) | « La fonction centrale d'All-in-One inclut un gestionnaire de fichiers : parcourir, copier, déplacer, compresser et chercher dans tous les dossiers de l'appareil, ainsi qu'un nettoyeur de stockage. Le sélecteur de fichiers du système ne permet ni de parcourir toute l'arborescence ni d'opérer en lot. » **Risque réel de refus** : prévoir le plan B (voir `PUBLICATION.md` §4). |
| Alarmes exactes (`USE_EXACT_ALARM`) | Réveils et rappels de tâches : fonction principale du module Horloge et de l'agenda. |
| Notification plein écran (`USE_FULL_SCREEN_INTENT`) | Affichage d'un réveil qui sonne, écran verrouillé. |
| Microphone au premier plan (`FOREGROUND_SERVICE_MICROPHONE`) | Enregistreur vocal : l'enregistrement continue écran éteint. |
| Lecture média au premier plan | Lecteur de musique : lecture en arrière-plan avec commandes sur l'écran verrouillé. |
| Calendrier (lecture/écriture) | Afficher et créer des événements du calendrier du téléphone dans l'agenda. |
| Appareil photo | Scanner de documents et lecteur de QR codes. |
| Photos, vidéos, musique | Galerie, lecteur de musique, éditeur vidéo. |
| Accès réseau | Radios, podcasts, taux de change, transfert Wi-Fi, publicités. |
| Démarrage de l'appareil (`RECEIVE_BOOT_COMPLETED`) | Réarmer les réveils et rappels après un redémarrage. |
| Identifiant publicitaire (`AD_ID`) | Publicités (Google AdMob). |

---

## 8. Publier : ordre conseillé

1. Créer l'application dans la console (nom, langue, gratuite, déclarations).
2. Remplir : fiche principale (§2–4), classification (§5), sécurité des données (§6), annonces, public cible, accès à l'appli (aucun compte nécessaire : « aucune instruction particulière »).
3. Créer le produit `remove_ads` (Monétiser → Produits).
4. **Test interne** : envoyer le `.aab`, ajouter vos e-mails comme testeurs, installer depuis le lien Play. Vérifier : démarrage, achat (compte testeur), restauration, formulaire de consentement.
5. **Test fermé** (comptes personnels neufs) : 12 testeurs pendant 14 jours.
6. **Production** : demander l'accès, publier. L'examen prend de quelques heures à quelques jours.

## 9. Ce que je ne peux pas faire à votre place
Créer le compte et payer les 25 $, fournir votre e-mail de contact et l'adresse de la page de confidentialité, créer la clé de signature, prendre les captures sur un vrai appareil, cliquer sur « Publier ».
