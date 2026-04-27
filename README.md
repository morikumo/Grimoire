# Grimoire 🔮

Interactive terminal cheatsheet — trouve la bonne commande au bon moment.

---

## Le problème

Tu connais les outils mais tu ne t'en souviens plus au bon moment. Surtout en CTF quand tu as un fichier inconnu devant toi et que tu ne sais pas par où commencer.

## La solution

Un cheatsheet interactif dans ton terminal. Tu tapes un mot, Grimoire te liste les commandes adaptées.

```bash
grimoire image      → exiftool, binwalk, steghide...
grimoire réseau     → nmap, netcat, curl...
grimoire ctf        → toutes les commandes CTF
grimoire            → mode interactif fuzzy search
```

---

## Installation

```bash
git clone https://github.com/morikumo/grimoire.git
cd grimoire
chmod +x grimoire.sh
sudo ./install.sh
```

## Usage

```bash
# Recherche par mot-clé
grimoire image
grimoire réseau
grimoire password

# Mode interactif
grimoire

# Aide
grimoire --help
```

---

## Structure

```
grimoire/
├── grimoire.sh        ← script principal
├── install.sh         ← installation commande système
├── db/
│   └── commands.json  ← base de données des commandes
└── README.md
```

## Dépendances

```bash
sudo apt install jq fzf
```

---

## Licence

MIT
