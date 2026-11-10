# StreamDock 293SV3 — notes de protocole

État au 2026-11-10. Chaque point porte son niveau de preuve :
**décompilé** (lu dans le code MiraBox), **essayé** (envoyé au boîtier),
**vu** (résultat constaté sur l'écran ou par un appui), **à vérifier**.

## Le boîtier

- Modèle : MiraBox StreamDock 293SV3 (nom donné par l'application MiraBox elle-même).
- USB : vendeur `0x6603`, produit `0x1014`, nom « HOTSPOTEKUSB HID DEMO ».
- Deux interfaces HID :
  - canal fabricant, usage page `0xFFA0`, usage `1` : rapports d'entrée de 512 octets,
    rapports de sortie de 1024 octets, pas de rapport de fonction. C'est le canal de pilotage.
  - clavier standard (usage page 1, usage 6).
- Disposition : grille 6 × 3. 15 touches à écran qui s'enfoncent, plus un second
  écran de 3 cases d'affichage seul, sans appui (SDK officiel : touches 1 à 15,
  cases 16 à 18).

## Sources

- Application MiraBox : `/Applications/StreamDock.app` (Qt 6, C++), version 3.10.205.0918.
- SDK officiel : `MiraboxSpace/StreamDock-Device-SDK`. Le dialogue USB passe par une
  bibliothèque fermée, `CPP-SDK/src/Transport/TransportDLL/libtransport.dylib`
  (SHA-256 `29be8e61…ced60`), décompilée avec REA et Ghidra 12.1.4 (tranche arm64).
- Projets libres : `4ndv/mirajazz` (protocole, Rust) et `4ndv/opendeck-akp153`
  (liste le 293SV3, `6603:1014`, protocole version 3).

## Trame

Chaque commande est un rapport de sortie de 1024 octets, identifiant de rapport `0`,
complété par des zéros (**décompilé** : `TransportSession::transact` ajoute l'identifiant
en tête puis complète à la taille du rapport ; **essayé** : `IOHIDDeviceSetReport` de
1024 octets est accepté sans erreur).

Le SDK règle les tailles à 513 / 1025 / 0 (entrée / sortie / fonction), identifiant compris.

## Commandes (décompilées dans `libtransport.dylib`)

Toutes commencent par `CRT\0\0`, sauf le changement de page.

| Fonction du SDK | Octets après `CRT\0\0` | Effet |
|---|---|---|
| `wakeupScreen` | `DIS` | allume l'écran |
| `setKeyBrightness` | `LIG` `00 00` + pourcentage (0–100) | luminosité |
| `setKeyImgFileStream` | `BAT` + taille (4 octets, poids fort d'abord) + numéro de case | annonce une image JPEG ; les données suivent par blocs de 1024 octets |
| `refresh` | `STP` | affiche les images envoyées |
| `clearKey` | `CLE` `00 00 00` + numéro de case | efface une case |
| `clearAllKeys` | `CLE` `00 00 00 FF` | efface tout |
| `sleep` | `HAN` | veille |
| `heartbeat` | `CONNECT` | maintien, toutes les 10 s dans le SDK |
| `disconnected` | `CLE` `00 00` `DC` | fin de session, efface l'affichage |
| `setBackgroundImgStream` | `LOG` + taille (4 octets) + `01` | logo de démarrage, **écrit en mémoire permanente** : jamais essayé, à n'envoyer qu'à la demande |
| `changeMode` | `MOD` `00 00` + (mode + `'1'`) | change de mode (rôle exact à vérifier) |
| `setDeviceConfig` | `QUCMD` + octets de configuration | à vérifier |
| `setBackgroundFrameStream` | `BGPIC` + taille (4) + largeur (2) + hauteur (2) + x (2) + y (2) + … + couche | image de fond par zone ; le SDK ne la déclare pas pour ce modèle |
| `clearBackgroundFrameStream` | `BGCLE` + position | idem |
| `changePage` | `M_V` + page, sans préfixe `CRT` | autres modèles |

Les commandes de LED et de clavier (`SETLB`, `LBLIG`, `COLOR`, `DELED`, `LLUM`, `LMOD`)
concernent d'autres modèles.

## Appuis

Rapport d'entrée de 512 octets (**vu** le 2026-11-10) :

- octets 0–2 `ACK`, octets 5–6 `OK` ;
- octet 9 : numéro de touche (1 à 15) ; `0xFF` = accusé d'écriture, à ignorer (SDK) ;
- octet 10 : `1` = appui, `0` = relâchement.

Le relâchement n'arrive pas toujours. Appui et relâchement arrivent tous deux après la
séquence complète d'ouverture (`DIS`, `LIG`, `CLE FF`, images, `STP`) ; pendant un essai où
seul `CONNECT` était envoyé après une réouverture, seuls les appuis sont arrivés. Lien de
cause à effet non établi. L'application n'agit que sur l'appui et oublie un appui resté
sans relâchement au bout de 0,3 s (`PressTracker`).

## Numérotation (**vue** sur photo et par appuis)

Les cases se numérotent de haut en bas, colonne par colonne, en partant de la droite :

```
13 10  7  4  1 | 16
14 11  8  5  2 | 17
15 12  9  6  3 | 18
```

Les numéros d'appui sont les mêmes que les numéros d'image. 16 à 18 forment la bande
d'affichage de droite, sans appui.

## Images

- Format : JPEG 96 × 96, tourné d'un quart de tour dans le sens inverse des aiguilles
  d'une montre avant envoi (**vu** : les numéros d'essai s'affichent à l'endroit, cadre complet).
- Bande de droite (16 à 18), **mesurée** sur photo : la vitre montre les 82 pixels de droite
  d'une image de 96 × 96 (les 14 pixels de gauche sont masqués), sur toute la hauteur, puis
  7 pixels de vitre noire au-delà du bord droit de l'image. Pour paraître centré dans la
  vitre, le contenu est donc décalé de 21 pixels vers la droite.
- Pas d'animation côté boîtier pour ce modèle : une animation se fait en renvoyant
  les images une à une depuis le Mac (12 images par seconde dans l'application).

## Version du micrologiciel

`getFirmwareVesion` lit un rapport d'entrée par `hid_get_input_report` (identifiant 0,
taille du rapport d'entrée). Pas encore essayé.

## Avant tout essai

L'application MiraBox doit être quittée : sinon elle redessine les cases et
les deux programmes se marchent dessus.

## Essais du 2026-11-10

- Ouverture du canal `0xFFA0` par IOKit, application MiraBox quittée : réussie.
  Le numéro de série se lit dans les propriétés HID.
- `DIS`, `CONNECT`, `LIG`, `CLE`, `BAT` + JPEG, `STP` : acceptés, images affichées (**vu**).
  Le boîtier ne renvoie aucun rapport en réponse à ces commandes.
- `CONNECT` toutes les 10 s pendant 9 minutes : aucun refus, aucun débranchement.
- DeckPilot affiche ses touches, l'heure et la date (**vu** sur photo à 12 h 16) ; un appui
  sur la touche 13 est arrivé avec son relâchement 190 ms plus tard.
- Un incident non expliqué : lors du premier essai, trois `CONNECT` de suite ont été
  refusés (`0xE00002C2`, argument invalide) alors qu'une nouvelle ouverture du boîtier
  fonctionnait aussitôt. `HIDDeck` rouvre donc le boîtier après un envoi refusé.
