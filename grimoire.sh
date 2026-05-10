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
    echo -e "  ${GREEN}grimoire --example <cmd>${RESET}  → ajouter des exemples à une commande"
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
        # Vérifier si le champ details est vide
        has_details=$(jq -r --arg name "$name" '
            .commands[] | select(.name == $name) | .details | length
        ' "$DB")

        if [[ "$has_details" -eq 0 ]]; then
            echo -e "${YELLOW}⚠️  '$name' existe déjà mais sans détails.${RESET}"
            read -rp "   Ajouter les détails maintenant ? (o/N) : " confirm
            if [[ "${confirm,,}" == "o" ]]; then
                update_details "$name"
            fi
        else
            echo -e "${YELLOW}⚠️  '$name' existe déjà dans le grimoire avec des détails.${RESET}"
            read -rp "   Écraser les détails existants ? (o/N) : " confirm
            [[ "${confirm,,}" == "o" ]] && update_details "$name"
        fi
        exit 0
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

    # ── Extraction des détails ────────────────────────────────
    echo -e "\n${DIM}Extraction des détails depuis --help...${RESET}"
    details_json=$(extract_details "$name")

    if [[ "$details_json" == "[]" || -z "$details_json" ]]; then
        echo -e "${DIM}Aucun détail sélectionné.${RESET}"
        details_json="[]"
    fi

    # Tags
    read -rp "Tags (séparés par virgules) : " tags_input
    tags_json=$(echo "$tags_input" | tr ',' '\n' | \
        awk '{$1=$1};1' | jq -R . | jq -s .)

    # Ajouter dans commands.json
    tmp=$(mktemp)
    jq --arg name "$name" \
       --arg desc "$description" \
       --arg usage "$usage_final" \
       --argjson tags "$tags_json" \
       --argjson details "$details_json" \
       '.commands += [{
           "name": $name,
           "description": $desc,
           "usage": $usage,
           "tags": $tags,
           "details": $details
       }]' \
       "$DB" > "$tmp" && mv "$tmp" "$DB"

    echo -e "\n${GREEN}✅ '$name' ajouté au grimoire.${RESET}"
}

add_example() {
    local name="$1"

    # Vérifier que la commande existe
    exists=$(jq -r --arg name "$name" '
        .commands[] | select(.name == $name) | .name
    ' "$DB")

    if [[ -z "$exists" ]]; then
        echo -e "${YELLOW}'$name' introuvable — ajoute-la d'abord avec : grimoire --add $name${RESET}"
        exit 1
    fi

    echo -e "${CYAN}Grimoire${RESET} — Ajout d'exemples pour ${GREEN}$name${RESET}\n"
    echo -e "${DIM}Tape tes exemples (format : Description : commande)${RESET}"
    echo -e "${DIM}Entrée vide pour terminer.${RESET}\n"

    new_examples=()
    while true; do
        read -rp "Exemple : " example
        [[ -z "$example" ]] && break
        new_examples+=("$example")
        echo -e "${GREEN}✅ Ajouté${RESET}"
    done

    if [[ ${#new_examples[@]} -eq 0 ]]; then
        echo -e "${YELLOW}Aucun exemple ajouté.${RESET}"
        exit 0
    fi

    examples_json=$(printf '%s\n' "${new_examples[@]}" | jq -R . | jq -s .)

    tmp=$(mktemp)
    jq --arg name "$name" \
       --argjson examples "$examples_json" \
       '(.commands[] | select(.name == $name) | .examples) += $examples' \
       "$DB" > "$tmp" && mv "$tmp" "$DB"

    echo -e "\n${GREEN}✅ ${#new_examples[@]} exemple(s) ajouté(s) pour '$name'.${RESET}"
}

show_command() {
    local name="$1"

    result=$(jq -r --arg name "$name" '
        .commands[] | select(.name == $name)
    ' "$DB")

    if [[ -z "$result" ]]; then
        echo -e "${YELLOW}Commande '$name' introuvable dans le grimoire.${RESET}"
        exit 1
    fi

    desc=$(echo "$result"     | jq -r '.description')
    usage=$(echo "$result"    | jq -r '.usage')
    tags=$(echo "$result"     | jq -r '.tags | join(", ")')
    details=$(echo "$result"  | jq -r '.details[]? // empty')
    examples=$(echo "$result" | jq -r '.examples[]? // empty')

    echo -e "${CYAN}Grimoire${RESET} — ${GREEN}$name${RESET}\n"
    echo -e "${DIM}Description :${RESET} $desc"
    echo -e "${DIM}Usage       :${RESET} $usage"
    echo -e "${DIM}Tags        :${RESET} $tags"

    if [[ -n "$details" ]]; then
        echo -e "\n${CYAN}Détails :${RESET}\n"
        while IFS= read -r line; do
            echo -e "  ${GREEN}→${RESET} $line"
        done <<< "$details"
    fi

    if [[ -n "$examples" ]]; then
        echo -e "\n${CYAN}Exemples :${RESET}\n"
        while IFS= read -r line; do
            label=$(echo "$line" | awk -F'→' '{print $1}' | xargs)
            cmd=$(echo "$line"   | awk -F'→' '{print $2}' | xargs)
            if [[ -n "$cmd" ]]; then
                echo -e "  ${DIM}$label${RESET}"
                echo -e "  ${YELLOW}$cmd${RESET}\n"
            else
                echo -e "  ${YELLOW}$line${RESET}\n"
            fi
        done <<< "$examples"
    else
        echo -e "\n${DIM}Aucun exemple — lance : grimoire --example $name${RESET}"
    fi

    echo ""
}

extract_details() {
    local name="$1"

    # Extraire les flags depuis --help
    raw=$("$name" --help 2>&1)

    # Parser les lignes qui ressemblent à des flags
    details=$(echo "$raw" | grep -E '^\s+(-{1,2}[a-zA-Z]|[A-Z])' | \
        sed 's/^[[:space:]]*//' | \
        grep -v "^$" | \
        head -30)

    if [[ -z "$details" ]]; then
        echo ""
        return
    fi

    # Laisser l'utilisateur sélectionner avec fzf
    selected=$(echo "$details" | fzf \
        --multi \
        --prompt="TAB pour sélectionner les détails → " \
        --height=60% \
        --border=rounded \
        --header="Sélectionne les usages à garder (TAB=sélectionner, Entrée=valider)" \
        --ansi)

    # Formater en tableau JSON
    if [[ -n "$selected" ]]; then
        echo "$selected" | jq -R . | jq -s .
    else
        echo "[]"
    fi
}

update_details() {
    local name="$1"

    echo -e "${CYAN}Grimoire${RESET} — Ajout de détails pour ${GREEN}$name${RESET}\n"
    echo -e "${DIM}Extraction depuis --help...${RESET}"

    details_json=$(extract_details "$name")

    if [[ "$details_json" == "[]" || -z "$details_json" ]]; then
        echo -e "${YELLOW}Aucun détail sélectionné.${RESET}"
        exit 0
    fi

    tmp=$(mktemp)
    jq --arg name "$name" \
       --argjson details "$details_json" \
       '(.commands[] | select(.name == $name) | .details) = $details' \
       "$DB" > "$tmp" && mv "$tmp" "$DB"

    echo -e "\n${GREEN}✅ Détails ajoutés pour '$name'.${RESET}"
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
# ── Guidance contextuelle ─────────────────────────────────
    guidance=()
    tags=()

    # Image
    if echo "$filetype" | grep -qi "png\|jpeg\|jpg\|gif\|bmp\|image"; then
        tags+=("image")
        guidance+=(
            "1. Vérifier le type réel        → file <fichier>"
            "2. Lire les métadonnées EXIF     → exiftool <fichier>"
            "3. Chercher données embarquées   → binwalk <fichier>"
            "4. Chercher stéganographie LSB   → zsteg <fichier> (PNG)"
            "5. Extraire données cachées      → steghide extract -sf <fichier>"
            "6. Inspecter en hexa             → xxd <fichier> | head -30"
        )
    fi

    # Archive / compressé
    if echo "$filetype" | grep -qi "zip\|gzip\|bzip\|xz\|archive\|compressed\|tar"; then
        tags+=("archive")
        guidance+=(
            "1. Lister le contenu             → tar -tvf <fichier> ou unzip -l <fichier>"
            "2. Extraire                       → tar -xvf <fichier> ou unzip <fichier>"
            "3. Vérifier si protégé            → zipinfo <fichier>"
            "4. Cracker le mot de passe ZIP    → john --format=zip <fichier>"
            "5. Chercher données embarquées    → binwalk <fichier>"
        )
    fi

    # ELF / binaire
    if echo "$filetype" | grep -qi "elf\|executable"; then
        tags+=("reverse" "binaire")
        guidance+=(
            "1. Infos générales               → file <fichier> && checksec <fichier>"
            "2. Extraire les chaînes          → strings <fichier> | grep -i flag"
            "3. Symboles et fonctions         → nm <fichier> ou readelf -s <fichier>"
            "4. Tracer les appels système     → strace ./<fichier>"
            "5. Tracer les appels librairie   → ltrace ./<fichier>"
            "6. Reverse engineering           → ghidra ou radare2 ou gdb"
        )
    fi

    # PCAP / capture réseau
    if echo "$filetype" | grep -qi "pcap\|tcpdump\|capture"; then
        tags+=("réseau" "pcap")
        guidance+=(
            "1. Ouvrir et analyser            → wireshark <fichier>"
            "2. Analyser en CLI               → tshark -r <fichier>"
            "3. Extraire les flux HTTP        → tshark -r <fichier> -Y http"
            "4. Extraire les fichiers         → binwalk <fichier>"
            "5. Suivre les streams TCP        → tshark -r <fichier> -z follow,tcp,ascii,0"
        )
    fi

    # PDF
    if echo "$filetype" | grep -qi "pdf"; then
        tags+=("pdf")
        guidance+=(
            "1. Lire les métadonnées          → exiftool <fichier>"
            "2. Extraire le texte             → pdftotext <fichier>"
            "3. Analyser la structure         → pdfid <fichier>"
            "4. Chercher du JS ou macros      → pdf-parser <fichier>"
            "5. Extraire les objets           → peepdf <fichier>"
        )
    fi

    # Texte / ASCII
    if echo "$filetype" | grep -qi "text\|ascii"; then
        tags+=("texte" "crypto")
        guidance+=(
            "1. Lire le contenu               → cat <fichier>"
            "2. Chercher des patterns         → grep -i 'flag\|key\|pass' <fichier>"
            "3. Détecter encodage Base64      → base64 -d <fichier>"
            "4. Détecter chiffrement César    → cat <fichier> | tr 'A-Za-z' 'N-ZA-Mn-za-m'"
            "5. Analyser avec CyberChef       → https://gchq.github.io/CyberChef"
        )
    fi

    # Audio
    if echo "$filetype" | grep -qi "audio\|mp3\|wav\|ogg\|flac"; then
        tags+=("audio")
        guidance+=(
            "1. Lire les métadonnées          → exiftool <fichier>"
            "2. Visualiser le spectrogramme   → sonic-visualiser <fichier>"
            "3. Analyser avec Audacity        → audacity <fichier>"
            "4. Chercher données embarquées   → binwalk <fichier>"
            "5. Détecter SSTV ou morse        → écouter et analyser visuellement"
        )
    fi

    # Certificat / crypto
    if echo "$filetype" | grep -qi "certificate\|x509\|pem\|rsa"; then
        tags+=("crypto")
        guidance+=(
            "1. Lire le certificat            → openssl x509 -in <fichier> -text"
            "2. Lire une clé privée           → openssl rsa -in <fichier> -text"
            "3. Factoriser un modulus faible  → rsactftool --publickey <fichier> --attack all"
            "4. Vérifier la signature         → openssl verify <fichier>"
        )
    fi

    # Base de données
    if echo "$filetype" | grep -qi "sqlite\|database"; then
        tags+=("database")
        guidance+=(
            "1. Ouvrir la base                → sqlite3 <fichier>"
            "2. Lister les tables             → sqlite3 <fichier> '.tables'"
            "3. Lire le contenu               → sqlite3 <fichier> 'SELECT * FROM <table>'"
            "4. Lire en hexa si corrompu      → xxd <fichier> | head -20"
        )
    fi

    # Données chiffrées / encodées (entropie haute)
    if echo "$filetype" | grep -qi "data\|unknown\|binary"; then
        tags+=("ctf")
        guidance+=(
            "1. Inspecter les magic bytes     → xxd <fichier> | head -5"
            "2. Extraire les chaînes          → strings <fichier>"
            "3. Chercher données embarquées   → binwalk <fichier>"
            "4. Vérifier l'entropie           → ent <fichier>"
            "5. Tester décodage Base64        → base64 -d <fichier>"
            "6. Tester si XOR                 → xortool <fichier>"
            "7. Analyser avec CyberChef       → https://gchq.github.io/CyberChef"
        )
    fi

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

    # ── Affichage guidance ────────────────────────────────────
    if [[ ${#guidance[@]} -gt 0 ]]; then
        echo -e "${CYAN}Par où commencer :${RESET}\n"
        for step in "${guidance[@]}"; do
            echo -e "  ${GREEN}→${RESET} $step"
        done
        echo ""
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
    --cmd|-c)
    [[ -z "$2" ]] && echo -e "${YELLOW}Usage : grimoire --cmd <commande>${RESET}" && exit 1
    show_command "$2"
    ;;
    --example|-e)
    [[ -z "$2" ]] && echo -e "${YELLOW}Usage : grimoire --example <commande>${RESET}" && exit 1
    add_example "$2"
    ;;
    --help|-h)
        usage
        ;;
    *)
        search "$1"
        ;;
esac