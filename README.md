# Nikaos

Nikaos est un shell de bureau écrit en QML avec
[Quickshell](https://quickshell.outfoxxed.me/), pensé pour Hyprland. C'est un
fork de [Serpantinum](https://github.com/ilyamiro/serpantinum) par **ilyamiro** :
il en garde toutes les fonctions (barre, paramètres, widgets, lanceur, écran de
verrouillage, notifications, thème Material You tiré du fond d'écran…) et y
ajoute les siennes. Tout se règle depuis les paramètres, sans éditer de
fichier.

*Nikaos is a Quickshell desktop shell for Hyprland, forked from Serpantinum by ilyamiro. Everything is set from the settings, no config file to edit.*

## Ce que Nikaos ajoute

### Couleurs dynamiques
- La barre et les widgets **changent de couleur en même temps que le fond
  d'écran**, pendant sa transition (image, GIF ou vidéo).
- **Nuance de chaque icône de la barre** (teinte et luminosité) :
  Paramètres → Thème → Nuances des icônes.
- **Nuance de chaque widget** : clic droit sur un widget dans l'éditeur de
  widgets. Les textes restent lisibles sur les fonds assombris.
- **Opacité du fond des widgets** seule, le texte reste net.

### Super+G : l'overlay
Un panneau de cartes à afficher, déplacer, redimensionner et épingler :
- **Enregistreur** : captures et vidéos, d'une zone ou de l'écran entier.
- **Volume** : sortie, entrée et mixage par application.
- **Ressources** : courbes du processeur, de la RAM, de la température, du GPU
  et de la mémoire d'échange.
- **Viseur** : réticule au centre de l'écran (croix, point ou cercle).
- **Notes**, **Applications ouvertes** (avec fermeture).
- **Transparence par application**, mémorisée, et interrupteur **Flou** :
  seules les fenêtres transparentes sont floutées.
- **Image flottante** : image ou GIF épinglé sur le bureau, masqué en plein
  écran.
- **Mode jeu** (voir plus bas) et bouton **VPN**.

### Mode jeu
Super+Shift+G, la carte Mode jeu de Super+G, ou automatiquement tant qu'un
jeu choisi est ouvert. Chaque réglage s'active « en jeu » ou « toujours » :
- décharger le fond, les widgets et l'image flottante ;
- mettre en pause le visualiseur de musique ;
- fenêtres opaques, pas de flou, pas d'animations ;
- direct scanout et VRR en plein écran ;
- profil d'énergie « performance » ;
- commandes personnalisées au début et à la fin.

### Fonds d'écran
- **Diaporama** (aléatoire ou trié par couleur) depuis le sélecteur de fonds.
- **Fonds vidéo allégés** : lus depuis des copies à la taille de l'écran
  (Paramètres → Fonds d'écran), pour économiser le GPU.
- **GIF** en fond d'écran, thème tiré de l'aperçu des vidéos.

### Barre et système
- **Charge du GPU** dans la barre, le panneau qui glisse du bord et en widget.
- Style de moniteur système **« pills »**.
- **Position des écrans secondaires** : Paramètres → Affichage.
- **Espacements des fenêtres** Hyprland : Paramètres → Général, et Super+U
  pour un mode sans bordure.
- **Liste des raccourcis** : Super+/.
- Le lecteur choisi dans la popup musique devient le lecteur principal.

### Matériel (Paramètres → Général → Matériel)
Désactivé par défaut, détecté automatiquement, configuré en un clic :
- **Mode tablette** pour les PC convertibles : charnière, rotation de l'écran,
  clavier virtuel et boutons tactiles dans la barre.
- **Conservation de batterie** (Lenovo IdeaPad / Yoga) : le bouton
  « Configurer » donne l'autorisation nécessaire (mot de passe demandé).
- **Connexion VPN** activable depuis Super+G.
- **Transparence de Kitty et de Vesktop** depuis Super+G : un bouton
  « Configurer » prépare chaque application.

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
`nikaos restart`. Le bouton de mise à jour de la page « À propos » suit ce
dépôt.

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

L'historique des versions de Serpantinum reprises dans Nikaos se trouve dans
[CHANGELOG.md](CHANGELOG.md).
