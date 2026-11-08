# Nikaos

Nikaos est un shell de bureau complet pour Linux, écrit en QML avec
[Quickshell](https://quickshell.outfoxxed.me/) et pensé pour Hyprland. Il
remplace la barre, le lanceur, les notifications, l'écran de verrouillage et
les panneaux système par une interface unique dont les couleurs suivent le
fond d'écran. Tout se règle depuis les paramètres (Super+H), sans éditer de
fichier.

C'est un fork de [Serpantinum](https://github.com/ilyamiro/serpantinum) par
**ilyamiro**, sous licence AGPL-3.0.

*Nikaos is a complete Quickshell desktop shell for Hyprland, forked from Serpantinum by ilyamiro. Everything is set from the settings.*

**Version actuelle : voir [les releases](https://github.com/oberflach/nikaos/releases).**

## Fonctionnalités principales

### L'interface
- **Barre** configurable : bureaux, musique, météo, horloge, moniteur système
  (CPU, GPU, RAM, température, disque), réseau, Bluetooth, volume, batterie,
  zone de notification. Modules et ordre réglables, plusieurs styles.
- **Lanceur d'applications** (Super+D) avec calculatrice, convertisseur,
  recherche de fichiers et recherche web (`?`).
- **Panneau système** (Super+B) : luminosité, volume, profils d'énergie,
  caféine, lumière bleue, Wi-Fi, Bluetooth, mode avion.
- **Popups** : musique avec paroles et égaliseur, calendrier, réseau, volume,
  notifications, presse-papiers.
- **Panneau qui glisse du bord de l'écran** : utilisation système, notes,
  calculatrice, minuteur, dessin.
- **Écran de verrouillage** personnalisable, avec son propre éditeur.
- **Widgets de bureau** (horloges, musique, météo, système, GPU, batterie,
  notes, texte, images, GIF…) à placer dans l'éditeur de widgets.
- **Bien-être numérique** : temps d'écran par application et limites.
- **Captures et enregistrements d'écran**, avec OCR pour copier du texte.

### Couleurs dynamiques
- Les couleurs de toute l'interface sont **tirées du fond d'écran**
  (Material You), et peuvent s'appliquer à d'autres applications
  (Paramètres → Thème → Applis).
- Elles **changent en même temps que le fond**, pendant sa transition
  (image, GIF ou vidéo).
- **Nuance de chaque icône de la barre** (Paramètres → Thème) et **de chaque
  widget** (clic droit dans l'éditeur de widgets).
- Opacité du fond des widgets, verre liquide, flou.

### Fonds d'écran
- Images, **GIF** et **vidéos**, avec transitions réglables.
- **Diaporama** aléatoire ou trié par couleur, favoris, recherche en ligne.
- **Fonds vidéo allégés** (Paramètres → Fonds d'écran) pour économiser le GPU.

### Super+G : l'overlay
Des cartes à afficher, déplacer, redimensionner et épingler : enregistreur,
volume par application, ressources, viseur, notes, applications ouvertes,
**transparence par application** avec interrupteur de flou, **image
flottante**, **mode jeu** et VPN.

### Mode jeu
Super+Shift+G, ou automatique quand un jeu choisi est ouvert. Il décharge le
fond et les widgets, met les fenêtres en opaque, coupe le flou et les
animations, active le direct scanout et le VRR, peut passer en profil
performance et lancer des commandes personnalisées. Chaque réglage peut
s'appliquer « en jeu » ou « toujours ».

### Fenêtres et écrans
- Espacements des fenêtres réglables, mode sans bordure (Super+U).
- Position des écrans secondaires (Paramètres → Affichage).
- Liste des raccourcis clavier : Super+/.

### Matériel (Paramètres → Général → Matériel)
Désactivé par défaut, détecté automatiquement, configuré en un clic :
- **Mode tablette** pour les PC convertibles : rotation de l'écran, clavier
  virtuel, boutons tactiles.
- **Conservation de batterie** (Lenovo IdeaPad / Yoga).
- **Connexion VPN** activable depuis Super+G.
- **Transparence de Kitty et de Vesktop** depuis Super+G.

## Versions et mises à jour

Chaque version est publiée comme une
[release GitHub](https://github.com/oberflach/nikaos/releases), avec des
notes qui expliquent ce qui change. Les mêmes notes sont dans
[CHANGELOG.md](CHANGELOG.md).

Les numéros suivent la forme **MAJEURE.MINEURE.CORRECTIF**, par exemple
`2.5.1` :

| Chiffre qui change | Signification | Exemple |
|---|---|---|
| Le dernier (correctif) | Corrections de bugs, rien ne change dans l'usage | 2.5.0 → 2.5.1 |
| Celui du milieu (mineure) | Nouvelles fonctions ou options | 2.5.1 → 2.6.0 |
| Le premier (majeure) | Grand changement, à lire avant de mettre à jour | 2.6.0 → 3.0.0 |

Nikaos prévient quand une nouvelle release est disponible. La mise à jour se
lance depuis Paramètres → À propos, ou en relançant l'installateur.

## Installation

Arch Linux, Fedora, Void Linux et leurs dérivées :

```bash
git clone https://github.com/oberflach/nikaos.git
cd nikaos
bash install/install.sh
```

L'installateur met en place les dépendances, Quickshell et les programmes
[serpantinum-core](https://github.com/ilyamiro/serpantinum-core),
[serpantinum-audio](https://github.com/ilyamiro/serpantinum-audio) et
[serpantinum-gamma](https://github.com/ilyamiro/serpantinum-gamma), qui restent
ceux de Serpantinum. La commande `nikaos` pilote le shell, par exemple
`nikaos restart`.

Pour rester compatible avec ces trois programmes, Nikaos garde en interne les
noms de Serpantinum : il s'installe dans `~/.local/share/serpantinum` et garde
ses réglages dans `~/.config/serpantinum`. Un Serpantinum déjà installé est
mis à jour sur place, avec ses réglages.

## Modifier Nikaos avec une IA

Le fichier [AGENTS.md](AGENTS.md) explique à un assistant de code (Claude
Code, Codex, Cursor…) comment Nikaos est construit et comment le modifier
proprement. Ces outils le lisent tout seuls : ouvre-en un dans le dossier du
dépôt et décris ce que tu veux changer.

## Licence et crédits

Nikaos est distribué sous licence **GNU AGPL-3.0**, comme Serpantinum (voir
[LICENSE.md](LICENSE.md)). Il est basé sur Serpantinum, © ilyamiro et ses
contributeurs : <https://github.com/ilyamiro/serpantinum>. Les modifications
propres à Nikaos sont © oberflach, sous la même licence.
