#!/usr/bin/env bash

# Grimoire — Terminal Command Helper
# Usage: ./grimoire.sh [mot-clé]

DB="$(dirname "$(realpath "$0")")/db/commands.json"

# Couleurs
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
DIM='\033[2m'
RESET='\033[0m'

# Vérifier que jq est installé
if ! command -v jq &>/dev/null; then
    echo "jq est requis : sudo apt install jq"
    exit 1
fi

usage() {
    echo -e "${CYAN}Grimoire${RESET} — Terminal Command Helper"
    echo ""
    echo "Usage: ./grimoire.sh [mot-clé]"
    echo ""
    echo -e "  ${GREEN}./grimoire.sh image${RESET}     → commandes liées à 'image'"
    echo -e "  ${GREEN}./grimoire.sh réseau${RESET}    → commandes liées au réseau"
    echo -e "  ${GREEN}./grimoire.sh ctf${RESET}       → commandes CTF"
    echo -e "  ${GREEN}./grimoire.sh --add${RESET}     → ajouter une commande"
    echo -e "  ${GREEN}grimoire --file <fichier>${RESET}  → analyser un fichier et suggérer les outils"
    echo ""
}

search() {
    local keyword="${1,,}"  # lowercase

    results=$(jq -r --arg kw "$keyword" '
        .commands[] |
        select(.tags[] | test($kw; "i")) |
        "\(.name)|\(.description)|\(.usage)"
    ' "$DB")

    if [[ -z "$results" ]]; then
        echo -e "${YELLOW}Aucune commande trouvée pour :${RESET} $1"
        exit 0
    fi

    echo -e "${CYAN}Grimoire${RESET} — résultats pour '${YELLOW}$1${RESET}'\n"
    echo -e "${DIM}COMMANDE         DESCRIPTION                          USAGE${RESET}"
    echo -e "${DIM}---------------- ------------------------------------ --------------------------${RESET}"

    while IFS='|' read -r name desc usage; do
        printf "${GREEN}%-16s${RESET} %-36s ${DIM}%s${RESET}\n" "$name" "$desc" "$usage"
    done <<< "$results"

    echo ""
}

interactive() {
    echo -e "${CYAN}Grimoire${RESET} — Mode interactif ${DIM}(Ctrl+C pour quitter)${RESET}\n"

    selected=$(jq -r '
        .commands[] |
        "\(.name) | \(.description) | \(.usage) | \(.tags | join(", "))"
    ' "$DB" | fzf \
        --prompt="🔮 Recherche : " \
        --height=50% \
        --border=rounded \
        --preview='echo -e "Commande : $(echo {} | cut -d"|" -f1)\nUsage    : $(echo {} | cut -d"|" -f3)\nTags     : $(echo {} | cut -d"|" -f4)"' \
        --preview-window=down:3:wrap \
        --ansi
    )

    if [[ -n "$selected" ]]; then
        name=$(echo "$selected"  | cut -d'|' -f1 | xargs)
        usage=$(echo "$selected" | cut -d'|' -f3 | xargs)
        echo -e "\n${GREEN}Commande :${RESET} $name"
        echo -e "${DIM}Usage    :${RESET} $usage"
    fi
}

add_command() {
    echo -e "${CYAN}Grimoire${RESET} — Ajouter une commande\n"

    # Nom
    read -rp "Nom de la commande : " name
    [[ -z "$name" ]] && echo -e "${YELLOW}Nom vide — annulé.${RESET}" && exit 1

    # Vérifier si déjà dans la base
    exists=$(jq -r --arg name "$name" '
        .commands[] | select(.name == $name) | .name
    ' "$DB")

    if [[ -n "$exists" ]]; then
        echo -e "${YELLOW}⚠️  '$name' existe déjà dans le grimoire.${RESET}"
        exit 1
    fi

    # Vérifier si installée sur la machine
    bin_path=$(command -v "$name" 2>/dev/null)
    if [[ -n "$bin_path" ]]; then
        echo -e "${GREEN}✅ '$name' trouvé :${RESET} $bin_path"
    else
        echo -e "${YELLOW}⚠️  '$name' non trouvé sur cette machine.${RESET}"
        read -rp "   Ajouter quand même ? (o/N) : " confirm
        [[ "${confirm,,}" != "o" ]] && echo "Annulé." && exit 0
    fi

    # Description
    read -rp "Description        : " description
    [[ -z "$description" ]] && echo -e "${YELLOW}Description vide — annulé.${RESET}" && exit 1

    # Usage
    read -rp "Usage              : " usage
    [[ -z "$usage" ]] && echo -e "${YELLOW}Usage vide — annulé.${RESET}" && exit 1

    # Tags
    read -rp "Tags (séparés par virgules) : " tags_input
    tags_json=$(echo "$tags_input" | tr ',' '\n' | \
        awk '{$1=$1};1' | jq -R . | jq -s .)

    # Ajouter dans commands.json
    tmp=$(mktemp)
    jq --arg name "$name" \
       --arg desc "$description" \
       --arg usage "$usage" \
       --argjson tags "$tags_json" \
       '.commands += [{"name": $name, "description": $desc, "usage": $usage, "tags": $tags}]' \
       "$DB" > "$tmp" && mv "$tmp" "$DB"

    echo -e "\n${GREEN}✅ '$name' ajouté au grimoire.${RESET}"
}

analyze_file() {
    local filepath="$1"

    # Vérifier que le fichier existe
    if [[ ! -f "$filepath" ]]; then
        echo -e "${YELLOW}Fichier introuvable :${RESET} $filepath"
        exit 1
    fi
}

# Point d'entrée
case "$1" in
    "")
        interactive
        ;;
    --file|-f)
    [[ -z "$2" ]] && echo -e "${YELLOW}Usage : grimoire --file <fichier>${RESET}" && exit 1
    analyze_file "$2"
    ;;
    --add|-a)
        add_command
        ;;
    --help|-h)
        usage
        ;;
    *)
        search "$1"
        ;;
esac