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

    echo -e "${CYAN}Grimoire${RESET} — Analyse de fichier\n"
    echo -e "${DIM}Fichier :${RESET} $filepath\n"

    # Détecter le type avec file
    filetype=$(file -b "$filepath" | tr '[:upper:]' '[:lower:]')
    echo -e "${DIM}Type détecté :${RESET} ${GREEN}$filetype${RESET}\n"

    # Mapper le type vers des tags de recherche
    tags=()

    echo "$filetype" | grep -qi "png\|jpeg\|jpg\|gif\|bmp\|image"  && tags+=("image")
    echo "$filetype" | grep -qi "pdf"                               && tags+=("pdf")
    echo "$filetype" | grep -qi "zip\|gzip\|bzip\|xz\|archive\|compressed\|tar" && tags+=("archive")
    echo "$filetype" | grep -qi "elf\|executable"                   && tags+=("reverse" "binaire")
    echo "$filetype" | grep -qi "pcap\|tcpdump\|capture"           && tags+=("réseau" "pcap")
    echo "$filetype" | grep -qi "text\|ascii"                       && tags+=("texte")
    echo "$filetype" | grep -qi "audio\|mp3\|wav\|ogg"             && tags+=("audio")
    echo "$filetype" | grep -qi "video\|mp4\|avi"                  && tags+=("video")
    echo "$filetype" | grep -qi "certificate\|x509\|pem"           && tags+=("crypto")
    echo "$filetype" | grep -qi "sqlite\|database"                 && tags+=("database")

    # Si aucun tag trouvé
    # Commandes génériques toujours suggérées en plus
    GENERIC_TOOLS=(
        "file|Identifier le type d'un fichier|file <fichier>"
        "strings|Extraire les chaînes lisibles|strings <fichier>"
        "xxd|Afficher le hexdump|xxd <fichier> | head -50"
        "binwalk|Analyser les données embarquées|binwalk <fichier>"
        "exiftool|Lire les métadonnées|exiftool <fichier>"
        "hexedit|Editeur hexadécimal interactif|hexedit <fichier>"
        "strace|Tracer les appels système|strace ./<fichier>"
        "ltrace|Tracer les appels librairie|ltrace ./<fichier>"
    )

    if [[ ${#tags[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Type non reconnu — outils d'investigation génériques :${RESET}\n"

        echo -e "${DIM}COMMANDE         DESCRIPTION                          USAGE${RESET}"
        echo -e "${DIM}---------------- ------------------------------------ --------------------------${RESET}"

        for tool in "${GENERIC_TOOLS[@]}"; do
            IFS='|' read -r name desc usage <<< "$tool"
            if command -v "$name" &>/dev/null; then
                installed="${GREEN}✅${RESET}"
            else
                installed="${YELLOW}⚠️ ${RESET}"
            fi
            printf "$installed ${GREEN}%-16s${RESET} %-36s ${DIM}%s${RESET}\n" \
                "$name" "$desc" "$usage"
        done
        echo ""
        exit 0
    fi

    # Toujours ajouter strings et xxd en bas peu importe le type
    echo -e "\n${DIM}── Outils génériques toujours utiles ──${RESET}"
    for tool in "${GENERIC_TOOLS[@]}"; do
        IFS='|' read -r name desc usage <<< "$tool"
        [[ " ${seen[*]} " =~ " ${name} " ]] && continue
        if command -v "$name" &>/dev/null; then
            installed="${GREEN}✅${RESET}"
        else
            installed="${YELLOW}⚠️ ${RESET}"
        fi
        printf "$installed ${GREEN}%-16s${RESET} %-36s ${DIM}%s${RESET}\n" \
            "$name" "$desc" "$usage"
    done

    # Infos supplémentaires sur le fichier
    echo -e "${DIM}Taille  :${RESET} $(du -h "$filepath" | cut -f1)"
    echo -e "${DIM}Entropy :${RESET} $(ent "$filepath" 2>/dev/null | grep Entropy | awk '{print $3}' || echo 'ent non installé')"
    echo -e "${DIM}Hexdump :${RESET} $(xxd "$filepath" | head -5)\n"

    # Chercher les commandes pour chaque tag
    echo -e "${CYAN}Outils suggérés :${RESET}\n"
    echo -e "${DIM}COMMANDE         DESCRIPTION                          USAGE${RESET}"
    echo -e "${DIM}---------------- ------------------------------------ --------------------------${RESET}"

    seen=()
    for tag in "${tags[@]}"; do
        results=$(jq -r --arg kw "$tag" '
            .commands[] |
            select(.tags[] | test($kw; "i")) |
            "\(.name)|\(.description)|\(.usage)"
        ' "$DB")

        while IFS='|' read -r name desc usage; do
            # Dédupliquer
            [[ -z "$name" ]] && continue
            if [[ ! " ${seen[*]} " =~ " ${name} " ]]; then
                seen+=("$name")
                # Vérifier si installé
                if command -v "$name" &>/dev/null; then
                    installed="${GREEN}✅${RESET}"
                else
                    installed="${YELLOW}⚠️ ${RESET}"
                fi
                printf "$installed ${GREEN}%-16s${RESET} %-36s ${DIM}%s${RESET}\n" \
                    "$name" "$desc" "$usage"
            fi
        done <<< "$results"
    done

    echo ""
    echo -e "${DIM}✅ installé   ⚠️  non installé${RESET}"
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