#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APT_UPDATED=0
SUDO_KEEPALIVE_PID=""

ensure_sudo() {
    if [[ -z "$SUDO_KEEPALIVE_PID" ]]; then
        sudo -v
        while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
        SUDO_KEEPALIVE_PID=$!
        trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT
    fi
}

update_apt_cache() {
    if [[ "$APT_UPDATED" -eq 0 ]]; then
        sudo apt-get update -y
        APT_UPDATED=1
    fi
}

install_apt_package() {
    local pkg="$1"
    update_apt_cache
    if dpkg -s "$pkg" &>/dev/null; then
        echo "  [OK] $pkg est déjà installé."
    else
        echo "  [>>] Installation de $pkg..."
        sudo apt-get install -y "$pkg"
    fi
}

######################################
# Installer pour le regroupement BASE
######################################

# Fonction pour installer une liste APT
install_apt_list() {
    local list_file="$1"
    if [[ ! -f "$list_file" ]]; then
        echo "[-] Fichier non trouvé : $list_file"
        return 1
    fi

    echo "[+] Traitement de la liste : $list_file"
    update_apt_cache

    # Filtrer les commentaires (#) et les lignes vides
    while IFS= read -r pkg; do
        install_apt_package "$pkg"
    done < <(sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//' "$list_file" | grep -vE '^(#|$)')
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

# Fonction pour Espanso (installation via .deb officiel)
install_Espanso() {
    if command -v espanso &>/dev/null; then
        echo "[OK] Espanso est déjà installé."
    else
        echo "[>>] Installation de Espanso..."      
        tmp_deb=$(mktemp /tmp/espanso-XXXXXX.deb)
        wget https://github.com/espanso/espanso/releases/latest/download/espanso-debian-wayland-amd64.deb -O "$tmp_deb"
        sudo apt-get install -y "$tmp_deb"
        rm -f "$tmp_deb"
    fi
}


######################################
# Installer pour le regroupement BUREAU
######################################


# Fonction pour Citrix Workspace (via .deb direct)
############################################################################
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

######################################
# Installer pour le regroupement DEV
######################################

# Fonction pour installer le serveur web Apache et PHP
############################################################################
install_lamp_stack() {
    if dpkg -s apache2 &>/dev/null && command -v php &>/dev/null; then
        echo "[OK] Apache et PHP sont déjà installés."
        return 0
    fi

    echo "[>>] Installation du serveur web Apache et de PHP..."
    
    update_apt_cache
    sudo apt-get install -y \
        apache2 \
        php \
        libapache2-mod-php \
        php-cli \
        php-curl \
        php-mbstring \
        php-xml \
        php-zip \
        php-mysql

    # Activation du module rewrite d'Apache et redémarrage du service
    echo "[>>] Configuration des modules Apache..."
    sudo a2enmod rewrite
    sudo systemctl restart apache2
    sudo systemctl enable apache2

    echo "[OK] Apache et PHP configurés et démarrés."
}

# Fonction pour MIcorosoft Visual Studio Code (VS Code)
############################################################################
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
        update_apt_cache
        sudo apt-get install -y code
    fi
}

# Fonction pour Termius (via Snap si disponible, ou .deb direct)
############################################################################
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

######################################
# Installer pour le regroupement MEDIA
######################################


# Fonctions de regroupement par profil
############################################################################
setup_base() {
    echo "=== Profil : BASE ==="
    install_apt_list "$SCRIPT_DIR/packages/base.list"
    install_chrome
}

setup_bureau() {
    echo "=== Profil : BUREAU ==="
    install_apt_list "$SCRIPT_DIR/packages/bureau.list"
    install_citrix
}

setup_dev() {
    echo "=== Profil : DEV ==="
    install_apt_list "$SCRIPT_DIR/packages/dev.list"
    install_termius
    install_vscode
    install_lamp_stack
}

setup_media() {
    echo "=== Profil : MEDIA ==="
    [[ -f "$SCRIPT_DIR/packages/media.list" ]] && install_apt_list "$SCRIPT_DIR/packages/media.list"
}

build_options() {
    OPTIONS_LABELS=()
    OPTIONS_ACTIONS=()
    local profile function_name list_file pkg
    local -A seen_packages=()

    for profile in base bureau dev media; do
        OPTIONS_LABELS+=("Profil : $profile")
        OPTIONS_ACTIONS+=("profile:$profile")
    done

    while IFS= read -r function_name; do
        [[ "$function_name" == "install_apt_list" || "$function_name" == "install_apt_package" ]] && continue
        OPTIONS_LABELS+=("Application : ${function_name#install_}")
        OPTIONS_ACTIONS+=("function:$function_name")
    done < <(declare -F | awk '{print $3}' | grep '^install_')

    for list_file in "$SCRIPT_DIR"/packages/*.list; do
        [[ -f "$list_file" ]] || continue
        while IFS= read -r pkg; do
            [[ -n "${seen_packages[$pkg]:-}" ]] && continue
            seen_packages["$pkg"]=1
            OPTIONS_LABELS+=("Paquet : $pkg")
            OPTIONS_ACTIONS+=("package:$pkg")
        done < <(sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//' "$list_file" | grep -vE '^(#|$)')
    done
}

list_options() {
    local i
    build_options
    printf 'Options disponibles :\n'
    for i in "${!OPTIONS_LABELS[@]}"; do
        printf '  %-3s %s\n' "$((i + 1))" "${OPTIONS_LABELS[$i]}"
    done
    printf '  all  Tous les profils (également : app:<nom>, nom du paquet)\n'
}

run_action() {
    local action="$1"
    case "$action" in
        profile:base) setup_base ;;
        profile:bureau) setup_bureau ;;
        profile:dev) setup_dev ;;
        profile:media) setup_media ;;
        profile:all)
            setup_base
            setup_bureau
            setup_dev
            setup_media
            ;;
        function:*) "${action#function:}" ;;
        package:*) install_apt_package "${action#package:}" ;;
        *)
            echo "[-] Option inconnue : $action"
            return 1
            ;;
    esac
}

run_interactive() {
    local i choice index
    local -a choices
    build_options
    printf 'Que souhaitez-vous installer ? Entrez les numéros séparés par des virgules :\n'
    for i in "${!OPTIONS_LABELS[@]}"; do
        printf '  %-3s %s\n' "$((i + 1))" "${OPTIONS_LABELS[$i]}"
    done
    printf '  all  Tous les profils\n'
    read -r -p 'Sélection : ' choice
    [[ -n "$choice" ]] || return 0
    if [[ "$choice" == "all" ]]; then
        ensure_sudo
        run_action "profile:all"
        return
    fi
    IFS=',' read -r -a choices <<< "$choice"
    for index in "${choices[@]}"; do
        if [[ ! "$index" =~ ^[0-9]+$ ]] || (( index < 1 || index > ${#OPTIONS_ACTIONS[@]} )); then
            echo "[-] Sélection invalide : $index"
            return 1
        fi
    done
    ensure_sudo
    for index in "${choices[@]}"; do
        run_action "${OPTIONS_ACTIONS[$((index - 1))]}"
    done
}

run_cli_selection() {
    local selection action function_name
    build_options
    for selection in "$@"; do
        action=""
        case "$selection" in
            all)
                action="profile:all"
                ;;
            base|bureau|dev|media)
                action="profile:$selection"
                ;;
            app:*)
                function_name="install_${selection#app:}"
                if declare -F "$function_name" >/dev/null; then
                    action="function:$function_name"
                fi
                ;;
            *)
                for i in "${!OPTIONS_ACTIONS[@]}"; do
                    if [[ "${OPTIONS_ACTIONS[$i]}" == "package:$selection" ]]; then
                        action="${OPTIONS_ACTIONS[$i]}"
                        break
                    fi
                done
                ;;
        esac
        if [[ -z "$action" ]]; then
            echo "[-] Option inconnue : $selection"
            list_options
            return 1
        fi
        ensure_sudo
        run_action "$action"
    done
}

if [[ "$#" -eq 0 ]]; then
    run_interactive
    exit
fi

if [[ "$#" -eq 1 && "$1" == "--list" ]]; then
    list_options
    exit
fi

if [[ "$#" -eq 1 && "$1" == "--interactive" ]]; then
    run_interactive
    exit
fi

# Gestion des arguments
for arg in "$@"; do
    case "$arg" in
        base|dev|bureau|media|all|app:*|*)
            run_cli_selection "$arg"
            ;;
    esac
done

echo "[+] Terminé !!"
