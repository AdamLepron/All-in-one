# Publier All-in-One sur Google Play

Ce que je ne peux pas faire à votre place : créer le compte développeur
(25 $ une fois), signer avec **votre** clé, remplir la console. Tout le reste
est prêt dans ce dossier.

## 1. Créer votre clé de signature (une seule fois — à sauvegarder !)

```
keytool -genkey -v -keystore ~/all-in-one-upload.jks -keyalg RSA -keysize 2048 \
  -validity 10000 -alias upload
```

Gardez le fichier `.jks` et ses mots de passe dans un endroit sûr (gestionnaire
de mots de passe + copie hors ligne) : sans eux, plus de mises à jour.

Créez `android/key.properties` (ignoré par git) :

```
storeFile=/chemin/complet/all-in-one-upload.jks
storePassword=…
keyAlias=upload
keyPassword=…
```

## 2. Construire le paquet

```
flutter build appbundle --release
```

Le fichier est `build/app/outputs/bundle/release/app-release.aab`. Google Play
l'exige à la place de l'APK. La clé de ce dossier (`test.keystore`) ne doit
**jamais** servir pour le store.

## 3. Console Play

1. Créer l'application (nom : All-in-One, langue par défaut : français, gratuite).
2. Fiche : textes dans `LISTING.md`, icône 512×512, image de présentation
   1024×500, au moins 2 captures d'écran téléphone (et tablette 7"/10" : l'app
   a une mise en page adaptée).
3. Politique de confidentialité : publiez `PRIVACY.md` sur une page web
   publique et donnez son adresse.
4. Sécurité des données : réponses dans `DATA_SAFETY.md`.
5. Classification du contenu, public cible (13+), déclaration « pas de publicité ».
6. Piste de test interne d'abord, puis production.

## 4. Points d'attention (à lire avant d'envoyer)

- **Accès à tous les fichiers (`MANAGE_EXTERNAL_STORAGE`)** : Google Play ne
  l'accepte que pour certaines applications (gestionnaires de fichiers,
  sauvegarde…). Le gestionnaire de fichiers d'All-in-One en a réellement
  besoin ; il faut remplir le formulaire de déclaration en expliquant ce cas
  d'usage (voir `DATA_SAFETY.md`). Risque réel de refus : prévoyez un
  plan B (retirer la permission et passer par le sélecteur de fichiers
  système, avec moins de fonctions).
- **Alarmes exactes (`USE_EXACT_ALARM`)** : accepté pour une application de
  réveil/rappels, c'est le cas du module Horloge et des rappels de tâches.
- **Notifications plein écran, microphone en service de premier plan,
  lecture média en arrière-plan** : déclarations à justifier dans la console.
- **Lecture de radios en HTTP** : `usesCleartextTraffic` est activé car
  beaucoup de flux radio ne sont pas en HTTPS.
- **Version cible** : Google exige une `targetSdk` récente ; la valeur est
  celle du Flutter installé (vérifiez-la au moment de l'envoi).
- **Calendrier et contacts du téléphone** : demandés seulement à l'usage.
- Cet APK n'a pas été testé sur un vrai téléphone : faites une période de
  test interne avant la production.
