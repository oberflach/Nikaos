# Nikaos

Nikaos est un shell de bureau écrit en QML avec
[Quickshell](https://quickshell.outfoxxed.me/), pensé pour Hyprland. C'est un
fork de [Serpantinum](https://github.com/ilyamiro/serpantinum) par **ilyamiro**.

*Nikaos is a Quickshell desktop shell for Hyprland, forked from Serpantinum by ilyamiro.*

## Ce que Nikaos ajoute à Serpantinum

- **Transition des couleurs synchronisée** avec le changement de fond d'écran
  (image, GIF ou vidéo) : la barre et les widgets changent de couleur en même
  temps que le fond.
- **Nuances par widget** : clic droit sur un widget dans l'éditeur pour régler
  sa teinte et sa luminosité. Chaque icône de la barre a aussi sa nuance
  (Paramètres → Thème → Nuances des icônes).
- **Charge du GPU** dans la barre, le panneau système et en widget.
- **Super+G** : enregistreur, volume, ressources, viseur, notes, applis,
  transparence par application, image flottante (GIF compris) et mode jeu.
- **Mode jeu** (Super+Shift+G, ou automatique quand un jeu choisi est ouvert) :
  décharge le fond et les widgets, rend les fenêtres opaques, coupe le flou et
  les animations, active le direct scanout et le VRR, lance des commandes
  personnalisées.
- **Flou seulement derrière les fenêtres transparentes** : les fenêtres
  opaques ne coûtent plus de calcul de flou.
- **Position des écrans secondaires** (gauche, droite, au-dessus, en dessous)
  dans Paramètres → Affichage.
- **Espacements des fenêtres** Hyprland réglables dans Paramètres → Général.
- Style de moniteur système « pills », fonds vidéo lus depuis des copies à la
  taille de l'écran, diaporama trié par couleur, et d'autres retouches.

Les fonctions propres à Nikaos (transparence, flou, mode jeu, positions
d'écrans, espacements) ciblent Hyprland.

### Options matérielles (Paramètres → Général → Matériel)

Elles sont désactivées par défaut, pour ne rien lancer sur un PC qui n'en a
pas besoin :

- **Mode tablette**, pour les PC convertibles : charnière, rotation de
  l'écran, clavier virtuel ([wvkbd](https://github.com/jjsullivan5196/wvkbd))
  et boutons tactiles dans la barre. Il faut `iio-sensor-proxy` (rotation),
  `wvkbd`, et être dans le groupe `input`.
- **Conservation de batterie** (Lenovo IdeaPad / Yoga, pilote `ideapad_acpi`) :
  remplace le bouton lumière bleue du panneau système. Pour pouvoir changer le
  réglage, il faut une règle udev, par exemple :
  ```
  ACTION=="add", SUBSYSTEM=="platform", DRIVER=="ideapad_acpi", RUN+="/bin/chmod a+w /sys%p/conservation_mode"
  ```
- **Connexion VPN** : le nom d'une connexion NetworkManager (par exemple
  `wg0`), activable depuis Super+G.

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
ceux de Serpantinum. La commande `nikaos` (et `nikaosd` pour le démon) pilote
le shell, par exemple `nikaos restart`.

### Noms internes

serpantinum-core, -audio et -gamma ont des chemins écrits en dur. Pour rester
compatible avec eux, Nikaos garde en interne les noms de Serpantinum : il
s'installe dans `~/.local/share/serpantinum`, garde ses réglages dans
`~/.config/serpantinum`, et la commande `serpantinum` reste disponible à côté
de `nikaos`. Un Serpantinum déjà installé est donc mis à jour sur place, avec
ses réglages.

### Intégrations optionnelles

- **Transparence de Kitty** depuis Super+G : dans `kitty.conf`,
  `allow_remote_control yes`, `listen_on unix:/tmp/kitty-serpantinum` et
  `dynamic_background_opacity yes`.
- **Transparence de Vesktop** : son Quick CSS doit contenir la variable
  `--serpantinum-surface-alpha: 1.00;` utilisée par sa surface principale.

## Licence et crédits

Nikaos est distribué sous licence **GNU AGPL-3.0**, comme Serpantinum (voir
[LICENSE.md](LICENSE.md)). Il est basé sur Serpantinum, © ilyamiro et ses
contributeurs : <https://github.com/ilyamiro/serpantinum>. Les modifications
propres à Nikaos sont © oberflach, sous la même licence.

L'historique des versions de Serpantinum reprises dans Nikaos se trouve dans
[CHANGELOG.md](CHANGELOG.md).
