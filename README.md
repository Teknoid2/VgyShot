<div align="center">

  <h1>📸 vGyShot</h1>
  <p align="center">
    <b>Solution complète et légère de capture d'écran, capture défilante (scrolling) et enregistrement vidéo pour Linux.</b>
  </p>

  <p align="center">
    <a href="#-fonctionnalités">Fonctionnalités</a> •
    <a href="#-installation">Installation</a> •
    <a href="#-utilisation">Utilisation</a> •
    <a href="#-configuration">Configuration</a> •
    <a href="#-dépendances">Dépendances</a> •
    <a href="#-structure-du-projet">Structure</a>
  </p>

  <p align="center">
    <img src="https://img.shields.io/badge/Platform-Linux%20%2F%20X11-blue?style=for-the-badge&logo=linux" alt="Platform Linux" />
    <img src="https://img.shields.io/badge/Bash-4EAA25?style=for-the-badge&logo=gnu-bash&logoColor=white" alt="Bash" />
    <img src="https://img.shields.io/badge/Python-3.x-3776AB?style=for-the-badge&logo=python&logoColor=white" alt="Python" />
    <img src="https://img.shields.io/badge/UI-YAD-orange?style=for-the-badge" alt="YAD" />
    <img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" alt="License MIT" />
  </p>

</div>

---
  <p align="center"><b>N'oubliez pas d'insérer votre clé API vgy.me & vos identifiants streamable avant toute chose.  </b></p>


## 🚀 Présentation

**vGyShot** est un outil puissant et polyvalent conçu pour les environnements Linux (Cinnamon, GNOME, XFCE, MATE, KDE). Il combine la capture d'écran de précision, l'assemblage dynamique de captures défilantes (scrolling screenshots) et l'enregistrement vidéo avec capture audio multicanale, le tout couplé à un système de téléversement automatique vers le cloud et de copie instantanée du lien dans le presse-papiers.

### 💾 Sauvegarde locale automatique
Le fichier est conservé instantanément sur votre ordinateur dans :  
👉 `~/Images/Capture d'écran`

* **Détection du logiciel :** Les images identifient automatiquement l'application capturée (ex: `google-chrome_aBc123XyZ.png`, `code_xYz987AbC.png`).
* **Noms uniques :** Une clé aléatoire de 9 caractères est ajoutée à chaque fichier pour éviter tout conflit ou écrasement.
* **Sécurité :** Vos captures restent stockées sur votre disque dur, même en cas de coupure réseau.

### ☁️ Téléversement en direct & Lien copié
Pendant que le fichier est sauvegardé en local, vGyShot l'envoie immédiatement sur les services cloud :
* 📸 **Images :** Envoyées en direct sur **[vgy.me](https://vgy.me)** via votre clé API.
* 🎥 **Vidéos :** Envoyées directement sur **[Streamable.com](https://streamable.com)** (ou anonymement sur **Catbox.moe**).
* 📋 **Presse-papiers :** Une fois le transfert terminé, **l'URL publique est automatiquement copiée dans votre presse-papiers**, prête à être collée (`Ctrl+V`) dans un tchat ou document !

---

## ✨ Fonctionnalités

### 📸 Captures d'écran
* **Capture de zone (`region`) :** Sélection précise à la souris via `maim` et `slop`.
* **Capture de fenêtre (`window`) :** Sélection native et automatique de la fenêtre ciblée.
* **Écran complet (`screen`) :** Capture globale de l'espace de travail.
* **Capture défilante intelligente (`scroll`) :**
  * Détection automatique de la zone de défilement (viewport).
  * Algorithme d'assemblage d'images (stitching) développé en Python (`Pillow`).
  * Recadrage automatique des en-têtes fixes et barres d'outils du navigateur.

### 🎥 Enregistrement Vidéo & Audio
* Enregistrement haute performance via `ffmpeg` (codec H.264 / MP4).
* **Gestion audio dynamique :**
  * Microphone seul
  * Son système (Loopback / Monitor)
  * Combinaison Microphone + Son système
  * Mode muet
* **Widget de contrôle :** Fenêtre flottante discrète avec chronomètre en temps réel et bouton d'arrêt rapide, positionnée intelligemment pour éviter le chevauchement de la zone capturée.

### ☁️ Téléversement Cloud & Intégration
* **Images :** Téléversement automatique vers **[vgy.me](https://vgy.me)** avec clé API.
* **Vidéos :** Téléversement sécurisé vers **Streamable** (si identifiants renseignés) ou téléversement anonyme vers **Catbox.moe**.
* Copie automatique du lien final dans le presse-papiers (`xclip`).
* Notifications système enrichies (`notify-send`).
* Icône dans la barre d'état (System Tray) avec menu contextuel complet (`YAD`).

---

## 🛠️ Dépendances

L'installateur automatique vérifie et installe les paquets nécessaires via `apt`. Si vous êtes sur une autre distribution, assurez-vous de disposer des éléments suivants :

| Dépendance | Rôle |
| :--- | :--- |
| `yad` | Interface graphique (systray, menus, fenêtres de dialogue) |
| `maim` / `slop` | Sélection et capture de zones graphiques sous X11 |
| `xdotool` / `xprop` | Simulation d'actions clavier/souris et détection de fenêtres |
| `xclip` | Gestion du presse-papiers système |
| `jq` | Parsing et manipulation des données JSON |
| `curl` | Requêtes HTTP pour les téléversements API |
| `ffmpeg` | Enregistrement du flux vidéo et mixage audio |
| `imagemagick` | Manipulation d'images en ligne de commande |
| `python3` & `python3-pil` | Algorithme d'assemblage (stitching) pour les captures défilantes |

---

## 📦 Installation

Un script d'installation `install_vgyshot.sh` est disponible dans la section release du dépot.
# Lancer l'installateur
./install_vgyshot.sh
