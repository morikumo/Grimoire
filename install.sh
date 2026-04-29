#!/usr/bin/env bash

# Grimoire — Install script

SCRIPT_DIR="$(cd "$(dirname "$(realpath "$0")")" && pwd)"
INSTALL_PATH="/usr/local/bin/grimoire"

echo -e "Installation de Grimoire..."

# Vérifier les dépendances
for dep in jq fzf; do
    if ! command -v "$dep" &>/dev/null; then
        echo "$dep est requis — installation..."
        sudo apt install "$dep" -y
    fi
done

# Créer un wrapper qui pointe vers le script
sudo tee "$INSTALL_PATH" > /dev/null << EOF
#!/usr/bin/env bash
exec "$SCRIPT_DIR/grimoire.sh" "\$@"
EOF

sudo chmod +x "$INSTALL_PATH"

echo -e "✅ Grimoire installé."
echo -e "Lance : grimoire --help"