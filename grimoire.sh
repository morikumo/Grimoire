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

# Point d'entrée
case "$1" in
    "")
        interactive
        ;;
    --help|-h)
        usage
        ;;
    *)
        search "$1"
        ;;
esac