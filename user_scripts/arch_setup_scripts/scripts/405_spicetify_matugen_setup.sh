#!/usr/bin/env bash
# ==============================================================================
# Script: 405_spicetify_matugen_setup.sh
# Description: "Golden" Spicetify setup with Matugen protection and self-healing.
#              - Auto-fixes /opt/spotify permissions
#              - Protects Matugen symlinks from being overwritten
#              - Smartly detects if Spotify config exists
#              - Guards against root execution
# ==============================================================================

set -euo pipefail

# --- Visual Feedback ---
if [[ -t 1 ]]; then
    readonly COLOR_RESET=$'\033[0m'
    readonly COLOR_INFO=$'\033[1;34m'    # Blue
    readonly COLOR_SUCCESS=$'\033[1;32m' # Green
    readonly COLOR_WARN=$'\033[1;33m'    # Yellow
    readonly COLOR_ERR=$'\033[1;31m'     # Red
else
    readonly COLOR_RESET=''
    readonly COLOR_INFO=''
    readonly COLOR_SUCCESS=''
    readonly COLOR_WARN=''
    readonly COLOR_ERR=''
fi

log_info()    { printf '%s[INFO]%s %s\n' "${COLOR_INFO}" "${COLOR_RESET}" "$*"; }
log_success() { printf '%s[OK]%s %s\n' "${COLOR_SUCCESS}" "${COLOR_RESET}" "$*"; }
log_warn()    { printf '%s[WARN]%s %s\n' "${COLOR_WARN}" "${COLOR_RESET}" "$*" >&2; }
log_err()     { printf '%s[ERROR]%s %s\n' "${COLOR_ERR}" "${COLOR_RESET}" "$*" >&2; }
die()         { log_err "$*"; exit 1; }

# --- Root Guard ---
if ((EUID == 0)); then
    die "Do not run this script as root. Spicetify operates on user-level config (~/.config/spicetify), and AUR helpers refuse to run as root."
fi

# --- Dependency Management ---
detect_pm() {
    # Check if spicetify-cli is available via pacman (e.g., chaotic-aur)
    if command -v pacman &>/dev/null && pacman -Si spicetify-cli &>/dev/null; then
        echo "pacman"
        return 0
    fi
    if command -v paru &>/dev/null; then echo "paru"; return 0; fi
    if command -v yay &>/dev/null; then echo "yay"; return 0; fi
    die "No suitable package manager found (need paru or yay)."
}

install_package() {
    local pkg="$1"
    local pm
    pm=$(detect_pm)
    log_info "Installing $pkg using $pm..."
    case "$pm" in
        pacman) sudo pacman -S --needed --noconfirm "$pkg" ;;
        paru|yay) "$pm" -S --needed --noconfirm "$pkg" ;;
    esac
}

# --- Checks & Fixes ---

check_requirements() {
    if ((BASH_VERSINFO[0] < 5)); then die "Bash 5.0+ required."; fi

    if command -v spotify &>/dev/null; then
        log_success "Spotify binary detected."
    elif command -v spotify-launcher &>/dev/null; then
        log_success "Spotify-launcher detected."
    else
        die "Spotify is not installed! Install 'spotify' or 'spotify-launcher' first."
    fi
}

fix_spotify_permissions() {
    # Spicetify needs write access to the Spotify install directory.
    # On Arch, this is usually /opt/spotify or /opt/spotify-launcher/....
    local spotify_path="/opt/spotify"
    
    # Attempt to detect path via Spicetify if installed, else default to /opt/spotify
    if command -v spicetify &>/dev/null; then
        local detected_path
        detected_path=$(spicetify path 2>/dev/null || echo "/opt/spotify")
        [[ -d "$detected_path" ]] && spotify_path="$detected_path"
    fi

    if [[ -d "$spotify_path" && ! -w "$spotify_path" ]]; then
        log_warn "Spotify directory ($spotify_path) is not writable. Fixing permissions..."
        # We assume sudo rights are available (Dusky Updater keeps sudo alive)
        # Note: chmod options must precede the path for POSIX compliance
        if sudo chmod a+wr "$spotify_path" && sudo chmod -R a+wr "$spotify_path/Apps" 2>/dev/null; then
            log_success "Permissions fixed."
        else
            log_warn "Could not automatically fix permissions. Spicetify backup might fail."
        fi
    fi
}

smart_user_confirmation() {
    # If the prefs file exists, Spotify has been run and generated config.
    # We can skip the nagging prompt.
    local prefs_file="${HOME}/.config/spotify/prefs"
    
    if [[ -f "$prefs_file" ]]; then
        log_info "Spotify config detected ($prefs_file). Proceeding..."
        return 0
    fi

    # Check for auto-confirm flag BEFORE printing the banner
    if [[ "${1:-}" == "--yes" || "${1:-}" == "-y" ]]; then
        log_info "Auto-confirm enabled."
        return 0
    fi

    # Fallback to prompt if no config found
    log_warn "--- USER ATTENTION REQUIRED ---"
    printf "%s" "Spotify config not found. Please ensure you have:
  1. Opened Spotify at least once.
  2. Logged in (optional but recommended).
  3. Closed Spotify (so we can patch it).
"

    read -r -p "Ready to proceed? [y/N]: " confirm
    [[ "${confirm,,}" =~ ^y ]] || die "Setup aborted by user."
}

# --- Core Logic ---

setup_spicetify() {
    if ! command -v spicetify &>/dev/null; then
        install_package "spicetify-cli"
    fi

    # Fix permissions before attempting backup
    fix_spotify_permissions

    log_info "Initializing Spicetify..."
    spicetify > /dev/null 2>&1 || true

    log_info "Applying backup and enabling devtools..."
    # We ignore errors here because 'backup apply' fails if backup already exists, which is fine.
    spicetify backup apply enable-devtools 2>/dev/null || log_info "Backup/Patch step passed (likely already patched)."
}

install_marketplace() {
    local spicetify_config_dir
    spicetify_config_dir="$(dirname "$(spicetify -c)")"
    local marketplace_dir="$spicetify_config_dir/CustomApps/marketplace"

    if [[ -d "$marketplace_dir" ]]; then
        log_info "Marketplace already installed."
    else
        log_info "Installing Spicetify Marketplace..."
        curl -fsSL "https://raw.githubusercontent.com/spicetify/spicetify-marketplace/main/resources/install.sh" | sh
    fi
}

setup_theme() {
    local config_dir
    config_dir="$(dirname "$(spicetify -c)")"
    local themes_dir="$config_dir/Themes"
    local comfy_dir="$themes_dir/Comfy"

    mkdir -p "$themes_dir"

    if [[ -d "$comfy_dir" ]]; then
        # === CRITICAL MATUGEN CHECK ===
        # If color.ini is a symlink, Matugen is managing it. DO NOT TOUCH IT.
        if [[ -L "$comfy_dir/color.ini" ]]; then
            log_success "Matugen symlink detected in Comfy theme."
            log_info "Skipping git pull to preserve your generated colors."
        else
            log_info "Updating Comfy theme..."
            git -C "$comfy_dir" pull --ff-only || log_warn "Git pull failed (local changes?). Skipping update."
        fi
    else
        log_info "Cloning Comfy theme..."
        git clone https://github.com/Comfy-Themes/Spicetify "$comfy_dir"
    fi

    log_info "Configuring theme (Comfy)..."
    spicetify config current_theme Comfy color_scheme Comfy

    log_info "Applying changes..."
    # -n (no backup) is faster and safe for theme updates
    spicetify apply -n
}

main() {
    check_requirements
    smart_user_confirmation "${1:-}"
    setup_spicetify
    install_marketplace
    setup_theme

    echo ""
    log_success "Spicetify setup complete!"
}

main "$@"
