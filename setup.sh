#!/usr/bin/env bash
set -euo pipefail

# Demande du mot de passe sudo au démarrage
sudo -v
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fonction pour installer une liste APT
install_apt_list() {
    local list_file="$1"
    if [[ ! -f "$list_file" ]]; then
        echo "[-] Fichier non trouvé : $list_file"
        return 1
    fi

    echo "[+] Traitement de la liste : $list_file"
    sudo apt-get update -y

    # Filtrer les commentaires (#) et les lignes vides
    grep -vE '^\s*#|^\s*$' "$list_file" | while read -r pkg; do
        if dpkg -s "$pkg" &>/dev/null; then
            echo "  [OK] $pkg est déjà installé."
        else
            echo "  [>>] Installation de $pkg..."
            sudo apt-get install -y "$pkg"
        fi
    done
}

# Fonction pour Google Chrome (installation .deb officiel)
install_chrome() {
    if command -v google-chrome &>/dev/null; then
        echo "[OK] Google Chrome est déjà installé."
    else
        echo "[>>] Installation de Google Chrome..."
        tmp_deb=$(mktemp /tmp/chrome-XXXXXX.deb)
        wget -q "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" -O "$tmp_deb"
        sudo apt-get install -y "$tmp_deb"
        rm -f "$tmp_deb"
    fi
}

install_vscode() {
    if command -v code &>/dev/null; then
        echo "[OK] VS Code est déjà installé."
    else
        echo "[>>] Configuration du dépôt et installation de VS Code..."
        
        # Dépendances requises pour ajouter le dépôt HTTPS
        sudo apt-get install -y wget gpg apt-transport-https

        # Clé GPG officielle Microsoft
        wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/packages.microsoft.gpg
        sudo install -D -o root -g root -m 644 /tmp/packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
        rm -f /tmp/packages.microsoft.gpg

        # Ajout de la source APT
        echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null

        # Installation du paquet
        sudo apt-get update -y
        sudo apt-get install -y code
    fi
}

# Fonction pour Termius (via Snap si disponible, ou .deb direct)
install_termius() {
    if command -v termius-app &>/dev/null || command -v termius &>/dev/null; then
        echo "[OK] Termius est déjà installé."
    elif command -v snap &>/dev/null; then
        echo "[>>] Installation de Termius via Snap..."
        sudo snap install termius-app
    else
        echo "[>>] Installation de Termius via .deb..."
        tmp_deb=$(mktemp /tmp/termius-XXXXXX.deb)
        wget -q "https://autoupdate.termius.com/linux/Termius.deb" -O "$tmp_deb"
        sudo apt-get install -y "$tmp_deb"
        rm -f "$tmp_deb"
    fi
}

# Fonction pour Citrix Workspace (via .deb direct)
install_citrix() {
    if dpkg -s icaclient &>/dev/null; then
        echo "[OK] Citrix Workspace est déjà installé."
        return 0
    fi

    echo "[>>] Récupération de la dernière version de Citrix..."
    
    # Récupérer l'URL du dernier .deb x86_64 depuis la page officielle
    LATEST_URL=$(curl -s "https://www.citrix.com/downloads/workspace-app/linux/workspace-app-for-linux-latest.html" \
        | grep -oP 'https://downloads\.citrix\.com/\d+/[^"]+\.deb' \
        | head -n 1)

    if [[ -z "$LATEST_URL" ]]; then
        echo "[-] Impossible de trouver le lien dynamique. Téléchargement manuel requis."
        return 1
    fi

    tmp_deb=$(mktemp /tmp/citrix-XXXXXX.deb)
    wget -q "$LATEST_URL" -O "$tmp_deb"
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$tmp_deb"
    rm -f "$tmp_deb"


    # Configuration non-interactive pour éviter les blocages de prompts debconf
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$tmp_deb"
    rm -f "$tmp_deb"

    # Lier les certificats SSL du système pour éviter les erreurs de certificat Citrix
    if [[ -d /opt/Citrix/ICAClient/keystore/cacerts ]]; then
        echo "[>>] Liaison des certificats racine système vers le magasin Citrix..."
        sudo ln -sf /usr/share/ca-certificates/mozilla/* /opt/Citrix/ICAClient/keystore/cacerts/ 2>/dev/null || true
        sudo c_rehash /opt/Citrix/ICAClient/keystore/cacerts/ 2>/dev/null || true
    fi
    
    echo "[OK] Installation de Citrix terminée."
}


# Menu d'options / Arguments
echo "=== Sélection des profils à installer ==="
for arg in "$@"; do
    case "$arg" in
        base)
            install_apt_list "$SCRIPT_DIR/packages/base.list"
            install_chrome
            install_termius
            ;;
        dev)
            install_apt_list "$SCRIPT_DIR/packages/dev.list"
            install_vscode
            ;;
        bureau)
            install_apt_list "$SCRIPT_DIR/packages/dev.list"
            install_vscode
            ;;
        media)
            install_apt_list "$SCRIPT_DIR/packages/media.list"
            ;;
        all)
            install_apt_list "$SCRIPT_DIR/packages/base.list"
            install_chrome
            install_termius
            install_vscode
            install_apt_list "$SCRIPT_DIR/packages/dev.list"
            [[ -f "$SCRIPT_DIR/packages/media.list" ]] && install_apt_list "$SCRIPT_DIR/packages/media.list"
            ;;
        *)
            echo "Profil inconnu : $arg"
            echo "Profils disponibles : base, dev, media, all"
            exit 1
            ;;
    esac
done

echo "[+] Terminé !!"