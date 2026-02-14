#!/usr/bin/env bash
# ==============================================================================
#  ARCH LINUX UPDATE ORCHESTRATOR (v6.0 - File-Based Backup/Restore)
#  Description: Manages dotfile/system updates while preserving user tweaks.
#               Uses file-based backup instead of git stash to prevent config
#               corruption from conflict markers.
#  Target:      Arch Linux / Hyprland / UWSM / Bash 5.0+
#  Repo Type:   Git Bare Repository (--git-dir=~/dusky --work-tree=~)
# ==============================================================================

set -euo pipefail
shopt -s inherit_errexit 2>/dev/null || true

if ((BASH_VERSINFO[0] < 5)); then
    printf 'Error: Bash 5.0+ required (found %s)\n' "$BASH_VERSION" >&2
    exit 1
fi

# ==============================================================================
# CONFIGURATION — Core paths and repository settings
# ==============================================================================
declare -r DOTFILES_GIT_DIR="${HOME}/dusky"
declare -r WORK_TREE="${HOME}"
declare -r SCRIPT_DIR="${HOME}/user_scripts/arch_setup_scripts/scripts"
declare -r LOG_BASE_DIR="${HOME}/Documents/logs"
declare -r LOCK_FILE="/tmp/arch-orchestrator.lock"
declare -r REPO_URL="https://github.com/dusklinux/dusky"
declare -r BRANCH="main"

# ==============================================================================
# USER CONFIGURATION — Custom script paths and update sequence
# ==============================================================================

# ------------------------------------------------------------------------------
# CUSTOM SCRIPT PATHS
# ------------------------------------------------------------------------------
# DO NOT REMOVE THESE COMMENTS, THESE ARE INSTRUCTIONS FOR ADDING SCRIPTS WITH CUSTOM PATH
# Map specific scripts to custom paths relative to ${HOME}.
# If a script in UPDATE_SEQUENCE matches a key here, this path is used.
# Format: ["script_name.sh"]="path/from/home/script_name.sh"

# ⚠️ IMPORTANT INSTRUCTIONS:
# 1. DEFINITION ONLY: This array ONLY maps the script name to a custom file location.
#    Adding a script here DOES NOT cause it to run automatically.
#
# 2. EXECUTION REQUIRED: To actually run the script, you MUST also add it to the
#    'UPDATE_SEQUENCE' list further down in this file.
#
# Format: ["script_name.sh"]="path/relative/to/home/script_name.sh"

declare -A CUSTOM_SCRIPT_PATHS=(
    # Example:
    # ["warp_toggle.sh"]="user_scripts/networking/warp_toggle.sh"
    # Then in UPDATE_SEQUENCE add: "S | warp_toggle.sh"

    ["warp_toggle.sh"]="user_scripts/networking/warp_toggle.sh"
    ["waypaper_config_reset.sh"]="user_scripts/desktop_apps/waypaper_config_reset.sh"
    ["fix_theme_dir.sh"]="user_scripts/misc_extra/fix_theme_dir.sh"
    ["package_installation.sh"]="user_scripts/misc_extra/package_installation.sh"
    ["copy_service_files.sh"]="user_scripts/misc_extra/copy_service_files.sh"
    ["update_checker.sh"]="user_scripts/update_dusky/update_checker/update_checker.sh"
)

# ------------------------------------------------------------------------------
# PLAYLIST (sub Scripts)
# ------------------------------------------------------------------------------
declare -ra UPDATE_SEQUENCE=(
#    "U | 000_configure_uwsm_gpu.sh"
#    "U | 001_long_sleep_timeout.sh"
#    "S | 002_battery_limiter.sh"
#    "S | 003_pacman_config.sh"
#    "S | 004_pacman_reflector.sh"
#    "S | 005_package_installation.sh"
#    "U | 006_enabling_user_services.sh"
#    "S | 007_openssh_setup.sh"
#    "U | 008_changing_shell_zsh.sh"
#    "S | 009_aur_paru_fallback_yay.sh"
#    "S | 010_warp.sh"
#    "U | 011_paru_packages_optional.sh"
#    "S | 012_battery_limiter_again_dusk.sh"
#    "U | 013_paru_packages.sh"
#    "S | 014_aur_packages_sudo_services.sh"
#    "U | 015_aur_packages_user_services.sh"
#    "S | 016_create_mount_directories.sh"
#    "S | 017_pam_keyring.sh"
    "U | 018_copy_service_files.sh --default"
#    "U | 019_battery_notify_service.sh"
#    "U | 020_fc_cache_fv.sh"
#    "U | 021_matugen_directories.sh"
#    "U | 022_wallpapers_download.sh"
#    "U | 023_blur_shadow_opacity.sh"
    "U | 024_theme_ctl.sh set --defaults"
#    "U | 025_qtct_config.sh"
#    "U | 026_waypaper_config_reset.sh"
    "U | 027_animation_default.sh"
#    "S | 028_udev_usb_notify.sh"
#    "U | 029_terminal_default.sh"
#    "S | 030_dusk_fstab.sh"
#    "S | 031_firefox_symlink_parition.sh"
#    "S | 032_tlp_config.sh"
#    "S | 033_zram_configuration.sh"
#    "S | 034_zram_optimize_swappiness.sh"
#    "S | 035_powerkey_lid_close_behaviour.sh"
#    "S | 036_logrotate_optimization.sh"
#    "S | 037_faillock_timeout.sh"
    "U | 038_non_asus_laptop.sh --auto"
#    "U | 039_file_manager_switch.sh"
#    "U | 040_swaync_dgpu_fix.sh --disable"
#    "S | 041_asusd_service_fix.sh"
#    "S | 042_ftp_arch.sh"
#    "U | 043_tldr_update.sh"
#    "U | 044_spotify.sh"
#    "U | 045_mouse_button_reverse.sh --right"
#    "U | 046_neovim_clean.sh"
#    "U | 047_neovim_lazy_sync.sh"
#    "U | 048_dusk_clipboard_errands_delete.sh --delete"
#    "S | 049_tty_autologin.sh"
#    "S | 050_system_services.sh"
#    "S | 051_initramfs_optimization.sh"
#    "U | 052_git_config.sh"
#    "U | 053_new_github_repo_to_backup.sh"
#    "U | 054_reconnect_and_push_new_changes_to_github.sh"
#    "S | 055_grub_optimization.sh"
#    "S | 056_systemdboot_optimization.sh"
#    "S | 057_hosts_files_block.sh"
#    "S | 058_gtk_root_symlink.sh"
#    "S | 059_preload_config.sh"
#    "U | 060_kokoro_cpu.sh"
#    "U | 061_faster_whisper_cpu.sh"
#    "S | 062_dns_systemd_resolve.sh"
#    "U | 063_hyprexpo_plugin.sh"
#    "U | 064_obsidian_pensive_vault_configure.sh"
#    "U | 065_cache_purge.sh"
#    "S | 066_arch_install_scripts_cleanup.sh"
#    "U | 067_cursor_theme_bibata_classic_modern.sh"
#    "S | 068_nvidia_open_source.sh"
#    "S | 069_waydroid_setup.sh"
#    "U | 070_reverting_sleep_timeout.sh"
#    "U | 071_clipboard_persistance.sh"
#    "S | 072_intel_media_sdk_check.sh"
    "U | 073_desktop_apps_username_setter.sh --quiet"
#    "U | 074_firefox_matugen_pywalfox.sh"
#    "U | 075_spicetify_matugen_setup.sh"
    "U | 076_waybar_swap_config.sh --toggle"
#    "U | 077_mpv_setup.sh"
#    "U | 078_kokoro_gpu_setup.sh"
#    "U | 079_parakeet_gpu_setup.sh"
#    "S | 080_btrfs_zstd_compression_stats.sh"
#    "U | 081_key_sound_wayclick_setup.sh"
#    "U | 082_config_bat_notify.sh --default"
    "U | 083_set_thunar_terminal_kitty.sh"
    "U | 084_package_removal.sh --auto"
#    "U | 085_wayclick_reset.sh"
#    "U | 086_generate_colorfiles_for_current_wallpaer.sh"
    "U | 087_hypr_custom_config_setup.sh"
    "U | 088_hyprctl_reload.sh"
    "U | 090_switch_clipboard.sh --terminal"
#    "S | 091_sddm_setup.sh --auto"
    "U | 092_vesktop_matugen.sh"



    "U | warp_toggle.sh --disconnect"
    "U | waypaper_config_reset.sh"
    "U | fix_theme_dir.sh"
    "U | copy_service_files.sh --default"
    "U | update_checker.sh --num"
    "S | package_installation.sh"
)

# ==============================================================================
# END OF USER CONFIGURATION — Do not edit below unless you know what you're doing
# ==============================================================================

# Centralized timestamp (Separate declaration for SC2155 compliance)
declare RUN_TIMESTAMP
RUN_TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
readonly RUN_TIMESTAMP

# Resolve self path with fallbacks
declare SELF_PATH
SELF_PATH="$(realpath -- "$0" 2>/dev/null || readlink -f -- "$0" 2>/dev/null || printf '%s' "$0")"
readonly SELF_PATH

# Binary validation (Separate declaration for SC2155 compliance)
declare GIT_BIN BASH_BIN
GIT_BIN="$(command -v git 2>/dev/null)" || GIT_BIN=""
BASH_BIN="$(command -v bash 2>/dev/null)" || BASH_BIN=""

if [[ -z "$GIT_BIN" || ! -x "$GIT_BIN" ]]; then
    printf 'Error: git not found\n' >&2
    exit 1
fi
if [[ -z "$BASH_BIN" || ! -x "$BASH_BIN" ]]; then
    printf 'Error: bash not found\n' >&2
    exit 1
fi
readonly GIT_BIN BASH_BIN

# Runtime state
declare SUDO_PID="" LOG_FILE="" ORIGINAL_EXIT_CODE=0
declare USER_MODS_BACKUP="" PRE_UPDATE_HEAD=""
declare -a GIT_CMD=() FAILED_SCRIPTS=() MODIFIED_FILES=()

# ------------------------------------------------------------------------------
# DEPENDENCY CHECK
# ------------------------------------------------------------------------------
check_dependencies() {
    local -a missing=()
    local cmd

    for cmd in flock sha256sum comm timeout; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done

    if ((${#missing[@]} > 0)); then
        printf 'Error: Missing required commands: %s\n' "${missing[*]}" >&2
        printf 'Install with: sudo pacman -S coreutils util-linux\n' >&2
        exit 1
    fi
}

# ------------------------------------------------------------------------------
# TERMINAL COLORS
# ------------------------------------------------------------------------------
if [[ -t 1 ]]; then
    declare -r CLR_RED=$'\e[1;31m' CLR_GRN=$'\e[1;32m' CLR_YLW=$'\e[1;33m'
    declare -r CLR_BLU=$'\e[1;34m' CLR_CYN=$'\e[1;36m' CLR_RST=$'\e[0m'
else
    declare -r CLR_RED="" CLR_GRN="" CLR_YLW="" CLR_BLU="" CLR_CYN="" CLR_RST=""
fi

# ------------------------------------------------------------------------------
# LOGGING
# ------------------------------------------------------------------------------
setup_logging() {
    if mkdir -p "$LOG_BASE_DIR" 2>/dev/null; then
        LOG_FILE="${LOG_BASE_DIR}/dusky_update_${RUN_TIMESTAMP}.log"
    else
        LOG_FILE="/tmp/dusky_update_${RUN_TIMESTAMP}.log"
    fi

    if ! touch "$LOG_FILE" 2>/dev/null; then
        LOG_FILE="/tmp/dusky_update_${RUN_TIMESTAMP}.log"
        touch "$LOG_FILE" || { printf 'Error: Cannot create log\n' >&2; exit 1; }
    fi

    {
        printf '================================================================================\n'
        printf ' DUSKY UPDATE LOG - %s\n' "$RUN_TIMESTAMP"
        printf ' Kernel: %s | User: %s\n' "$(uname -r)" "${USER:-$(id -un)}"
        printf '================================================================================\n'
    } >> "$LOG_FILE"
}

# Strip ANSI escape sequences for log file (Optimized pattern)
strip_ansi() {
    local text="$1" i=0
    local -r ansi_pattern=$'\e\[[0-9;]*[a-zA-Z]'
    while [[ "$text" =~ $ansi_pattern ]] && ((++i < 100)); do
        text="${text//"${BASH_REMATCH[0]}"/}"
    done
    printf '%s' "$text"
}

log() {
    (($# >= 2)) || return 1
    local -r level="$1" msg="$2"
    local timestamp prefix=""
    timestamp=$(date +%H:%M:%S)

    case "$level" in
        INFO)    prefix="${CLR_BLU}[INFO ]${CLR_RST}" ;;
        OK)      prefix="${CLR_GRN}[OK   ]${CLR_RST}" ;;
        WARN)    prefix="${CLR_YLW}[WARN ]${CLR_RST}" ;;
        ERROR)   prefix="${CLR_RED}[ERROR]${CLR_RST}" ;;
        SECTION) prefix=$'\n'"${CLR_CYN}═══════${CLR_RST}" ;;
        RAW)     prefix="" ;;
        *)       prefix="[$level]" ;;
    esac

    if [[ "$level" == "RAW" ]]; then
        printf '%s\n' "$msg"
    else
        printf '%s %s\n' "$prefix" "$msg"
    fi

    [[ -n "${LOG_FILE:-}" && -w "$LOG_FILE" ]] && \
        printf '[%s] [%-5s] %s\n' "$timestamp" "$level" "$(strip_ansi "$msg")" >> "$LOG_FILE"
}

# ------------------------------------------------------------------------------
# CORE ENGINE
# ------------------------------------------------------------------------------
trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

cleanup() {
    # Capture exit code IMMEDIATELY - this is critical
    ORIGINAL_EXIT_CODE=$?

    # Stop sudo keepalive
    if [[ -n "${SUDO_PID:-}" ]] && kill -0 "$SUDO_PID" 2>/dev/null; then
        kill "$SUDO_PID" 2>/dev/null || true
        wait "$SUDO_PID" 2>/dev/null || true
    fi

    # Inform user about backed-up modifications (if any)
    if [[ -n "${USER_MODS_BACKUP:-}" && -d "${USER_MODS_BACKUP:-}" ]]; then
        local backup_file_count
        # FIX: protect pipeline from set -e + pipefail crash if find fails
        backup_file_count=$(find "$USER_MODS_BACKUP" -type f 2>/dev/null | wc -l) || backup_file_count=0
        if ((backup_file_count > 0)); then
            printf '\n'
            log WARN "Update was interrupted. Your modified files are safely backed up at:"
            printf '    %s\n' "$USER_MODS_BACKUP"
            log INFO "You can restore them manually by copying files from that directory."
        fi
    fi

    # Clean up any partial atomic writes from interrupted restore
    if ((${#MODIFIED_FILES[@]} > 0)); then
        local tmp_file
        for tmp_file in "${MODIFIED_FILES[@]}"; do
            rm -f "${WORK_TREE}/${tmp_file}.dusky_tmp" 2>/dev/null || true
        done
    fi

    # Release lock (close fd first, then remove file)
    exec 9>&- 2>/dev/null || true
    rm -f "$LOCK_FILE" 2>/dev/null || true

    printf '\n'
    if ((${#FAILED_SCRIPTS[@]} > 0)); then
        log WARN "Completed with ${#FAILED_SCRIPTS[@]} failure(s)"
        local script
        for script in "${FAILED_SCRIPTS[@]}"; do
            printf '    • %s\n' "$script"
        done
    elif [[ -n "${LOG_FILE:-}" ]]; then
        log OK "Complete. Log: $LOG_FILE"
    fi

    # Preserve original exit code
    exit "$ORIGINAL_EXIT_CODE"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

init_sudo() {
    log INFO "Acquiring sudo privileges..."
    sudo -v || { log ERROR "Sudo auth failed."; exit 1; }

    ( trap 'exit 0' TERM
      while kill -0 $$ 2>/dev/null; do sleep 55; sudo -n true 2>/dev/null || exit 0; done
    ) &
    SUDO_PID=$!
    disown "$SUDO_PID" 2>/dev/null || true
}

# Clean up any broken git state
cleanup_git_state() {
    local rebase_dir="${DOTFILES_GIT_DIR}/rebase-merge"
    local rebase_apply="${DOTFILES_GIT_DIR}/rebase-apply"

    # Abort any in-progress rebase
    if [[ -d "$rebase_dir" || -d "$rebase_apply" ]]; then
        log WARN "Detected stale rebase. Aborting..."
        "${GIT_CMD[@]}" rebase --abort >> "$LOG_FILE" 2>&1 || true
        rm -rf "$rebase_dir" "$rebase_apply" 2>/dev/null || true
    fi

    # Clean any conflict markers from working tree
    if "${GIT_CMD[@]}" diff --check 2>&1 | grep -q "leftover conflict marker"; then
        log WARN "Conflict markers detected. Cleaning working tree..."
        "${GIT_CMD[@]}" checkout HEAD -- . >> "$LOG_FILE" 2>&1 || true
    fi
}

# ------------------------------------------------------------------------------
# BACKUP TRACKED FILES (Pre-Reset Safety Net)
# ------------------------------------------------------------------------------
backup_tracked_files() {
    local backup_dir="${HOME}/Documents/dusky_pre_reset_backup_${RUN_TIMESTAMP}"
    local tracked_files file_count=0
    local src dest file  # Declare outside loop

    log INFO "Backing up tracked files before reset..."

    tracked_files=$("${GIT_CMD[@]}" ls-files 2>/dev/null) || {
        log WARN "Could not get tracked file list. Skipping backup."
        return 1
    }

    if [[ -z "$tracked_files" ]]; then
        log WARN "No tracked files found. Skipping backup."
        return 0
    fi

    if ! mkdir -p "$backup_dir"; then
        log ERROR "Failed to create backup directory: $backup_dir"
        return 1
    fi

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        src="${WORK_TREE}/${file}"
        dest="${backup_dir}/${file}"

        if [[ -e "$src" ]]; then
            mkdir -p "$(dirname "$dest")" 2>/dev/null || true
            if cp -a -- "$src" "$dest" 2>/dev/null; then
                # FIX BUG 1: ((0)) returns exit code 1, crashes under set -e
                ((file_count++)) || true
            fi
        fi
    done <<< "$tracked_files"

    if ((file_count > 0)); then
        log OK "Backed up $file_count tracked files to: $backup_dir"
    else
        log WARN "No files were backed up."
        rmdir "$backup_dir" 2>/dev/null || true
    fi

    return 0
}

# ------------------------------------------------------------------------------
# BACKUP USER MODIFICATIONS (File-Based — Replaces Git Stash)
# ------------------------------------------------------------------------------
# Copies user-modified tracked files to a backup directory BEFORE reset --hard.
# Called immediately before every reset --hard in pull_updates().
# Sets USER_MODS_BACKUP on success. Returns 1 on failure (caller MUST abort).
# Idempotent: safe to call multiple times (returns 0 if already done).
backup_user_modifications() {
    # Idempotency guard: if backup already exists, skip
    if [[ -n "$USER_MODS_BACKUP" && -d "$USER_MODS_BACKUP" ]]; then
        return 0
    fi

    # Nothing to back up
    if ((${#MODIFIED_FILES[@]} == 0)); then
        return 0
    fi

    local backup_dir="${HOME}/Documents/dusky_user_mods_${RUN_TIMESTAMP}"
    local src dest file
    local file_count=0

    if ! mkdir -p "$backup_dir"; then
        log ERROR "Failed to create backup directory: $backup_dir"
        return 1
    fi

    # FIX MINOR 4: Set immediately after mkdir so cleanup() can report this
    # directory if we crash midway through the copy loop
    USER_MODS_BACKUP="$backup_dir"

    for file in "${MODIFIED_FILES[@]}"; do
        [[ -z "$file" ]] && continue

        src="${WORK_TREE}/${file}"

        # User deleted a tracked file — nothing on disk to copy, skip
        if [[ ! -e "$src" ]]; then
            continue
        fi

        dest="${backup_dir}/${file}"

        if ! mkdir -p "$(dirname "$dest")"; then
            log ERROR "Failed to create directory for: $file"
            return 1
        fi

        if ! cp -a -- "$src" "$dest"; then
            log ERROR "Failed to back up modified file: $file"
            return 1
        fi

        # FIX BUG 1: ((0)) returns exit code 1, crashes under set -e
        ((file_count++)) || true
    done

    if ((file_count > 0)); then
        log OK "Backed up $file_count modified file(s) to: $backup_dir"
    else
        log INFO "No modified files needed backing up (all were deletions)."
    fi

    return 0
}

# ------------------------------------------------------------------------------
# RESTORE USER MODIFICATIONS (File-Based — Replaces Stash Pop)
# ------------------------------------------------------------------------------
# After reset --hard, selectively restores user modifications:
#   - Files upstream DIDN'T change: auto-restored via atomic write (rename)
#   - Files upstream DID change: saved to merge directory for manual review
# Uses atomic writes (cp to .dusky_tmp then mv) to prevent inotify-triggered
# applications from seeing partial content.
restore_user_modifications() {
    # Nothing to restore if no backup was made
    if [[ -z "${USER_MODS_BACKUP:-}" || ! -d "${USER_MODS_BACKUP:-}" ]]; then
        return 0
    fi

    if ((${#MODIFIED_FILES[@]} == 0)); then
        return 0
    fi

    log INFO "Restoring your modifications..."

    # ---- Determine which files upstream changed ----
    # Compare PRE_UPDATE_HEAD (before reset) to current HEAD (after reset)
    local -A upstream_changed=()
    local uc_file
    local diff_failed=false

    if [[ -n "${PRE_UPDATE_HEAD:-}" ]]; then
        local current_head
        current_head=$("${GIT_CMD[@]}" rev-parse HEAD 2>/dev/null) || current_head=""

        if [[ -n "$current_head" && "$PRE_UPDATE_HEAD" != "$current_head" ]]; then
            # FIX BUG 2: Process substitution swallows git diff exit code.
            # Use a temp file to properly capture both the exit code and
            # null-delimited output (command substitution strips null bytes).
            local diff_tmpfile
            diff_tmpfile=$(mktemp 2>/dev/null) || diff_tmpfile=""

            if [[ -n "$diff_tmpfile" ]]; then
                if "${GIT_CMD[@]}" diff -z --name-only "$PRE_UPDATE_HEAD" HEAD -- >"$diff_tmpfile" 2>/dev/null; then
                    while IFS= read -r -d '' uc_file; do
                        [[ -n "$uc_file" ]] && upstream_changed["$uc_file"]=1
                    done < "$diff_tmpfile"
                else
                    diff_failed=true
                fi
                rm -f "$diff_tmpfile" 2>/dev/null || true
            else
                diff_failed=true
            fi
        fi
        # If PRE_UPDATE_HEAD == current_head, upstream changed nothing — all files auto-restore
    else
        # Cannot determine what upstream changed — treat ALL as changed (safe fallback)
        diff_failed=true
    fi

    if [[ "$diff_failed" == true ]]; then
        log WARN "Cannot determine upstream changes. All modified files will go to merge directory."
        for uc_file in "${MODIFIED_FILES[@]}"; do
            [[ -n "$uc_file" ]] && upstream_changed["$uc_file"]=1
        done
    fi

    # ---- Restore or redirect each file ----
    local merge_dir=""
    local restored_count=0 merge_count=0
    local all_ok=true
    local file backup_src target tmp merge_dest

    for file in "${MODIFIED_FILES[@]}"; do
        [[ -z "$file" ]] && continue

        backup_src="${USER_MODS_BACKUP}/${file}"

        # Nothing was backed up for this file (was a deletion), skip
        if [[ ! -e "$backup_src" ]]; then
            continue
        fi

        if [[ -v "upstream_changed[$file]" ]]; then
            # Upstream changed this file — save to merge directory for manual review
            if [[ -z "$merge_dir" ]]; then
                merge_dir="${HOME}/Documents/dusky_needs_merge_${RUN_TIMESTAMP}"
                if ! mkdir -p "$merge_dir"; then
                    log ERROR "Failed to create merge directory: $merge_dir"
                    all_ok=false
                    continue
                fi
            fi

            merge_dest="${merge_dir}/${file}"
            if ! mkdir -p "$(dirname "$merge_dest")"; then
                log ERROR "Failed to create directory for merge file: $file"
                all_ok=false
                continue
            fi

            if cp -a -- "$backup_src" "$merge_dest" 2>/dev/null; then
                # FIX BUG 1: ((0)) returns exit code 1, crashes under set -e
                ((merge_count++)) || true
                log RAW "  → Upstream changed: $file (your version saved for merge)"
            else
                log ERROR "Failed to copy to merge dir: $file"
                all_ok=false
            fi
        else
            # Upstream didn't change this file — auto-restore with atomic write
            target="${WORK_TREE}/${file}"
            tmp="${target}.dusky_tmp"

            if ! mkdir -p "$(dirname "$target")" 2>/dev/null; then
                log ERROR "Failed to create directory for restore: $file"
                all_ok=false
                continue
            fi

            # Atomic write: cp to temp file, then rename (same filesystem = instant)
            if cp -a -- "$backup_src" "$tmp" 2>/dev/null && mv -f -- "$tmp" "$target" 2>/dev/null; then
                # FIX BUG 1: ((0)) returns exit code 1, crashes under set -e
                ((restored_count++)) || true
                log RAW "  → Restored: $file"
            else
                log ERROR "Failed to restore: $file"
                rm -f "$tmp" 2>/dev/null || true
                all_ok=false
            fi
        fi
    done

    # ---- Summary ----
    if ((restored_count > 0)); then
        log OK "Auto-restored $restored_count file(s) (upstream hadn't changed them)"
    fi

    if ((merge_count > 0)); then
        log WARN "$merge_count file(s) need manual merge — upstream changed them too"
        log INFO "Your versions saved to:"
        printf '    %s\n' "$merge_dir"
        log INFO "Compare with current configs and merge your changes when ready."
    fi

    if ((restored_count == 0 && merge_count == 0)); then
        log INFO "No modifications needed restoring."
    fi

    # Clean up backup directory only if ALL files were processed successfully
    if [[ "$all_ok" == true ]]; then
        rm -rf "$USER_MODS_BACKUP" 2>/dev/null || true
        USER_MODS_BACKUP=""
    else
        log WARN "Some files could not be processed. Backup preserved at:"
        printf '    %s\n' "$USER_MODS_BACKUP"
    fi

    return 0
}

# ------------------------------------------------------------------------------
# PULL UPDATES — Sync local repo to upstream
# ------------------------------------------------------------------------------
pull_updates() {
    log SECTION "Synchronizing Dotfiles Repository"

    if [[ ! -d "$DOTFILES_GIT_DIR" ]]; then
        log ERROR "Bare repo not found: $DOTFILES_GIT_DIR"
        return 1
    fi

    GIT_CMD=("$GIT_BIN" --git-dir="$DOTFILES_GIT_DIR" --work-tree="$WORK_TREE")
    "${GIT_CMD[@]}" config status.showUntrackedFiles no 2>/dev/null || true

    # Clean any broken state from previous runs
    cleanup_git_state

    # --------------------------------------------------------------------------
    # DETECT LOCAL MODIFICATIONS (record for later backup/restore)
    # --------------------------------------------------------------------------
    log INFO "Checking for local modifications..."

    if ! "${GIT_CMD[@]}" diff-index --quiet HEAD -- 2>/dev/null; then
        log WARN "Local modifications detected. These will be preserved."

        PRE_UPDATE_HEAD=$("${GIT_CMD[@]}" rev-parse HEAD 2>/dev/null) || PRE_UPDATE_HEAD=""

        if [[ -z "$PRE_UPDATE_HEAD" ]]; then
            log ERROR "Cannot determine current HEAD. Aborting."
            return 1
        fi

        # Build list of modified files using null-byte delimiter for filename safety
        # FIX MINOR 5: declare file as local before first use
        # FIX MINOR 6: pipe through sort -zu to deduplicate (diff-index can
        #              list a file twice if it has both staged and unstaged changes)
        MODIFIED_FILES=()
        local file
        while IFS= read -r -d '' file; do
            MODIFIED_FILES+=("$file")
        done < <("${GIT_CMD[@]}" diff-index -z --name-only HEAD -- 2>/dev/null | sort -zu)

        if ((${#MODIFIED_FILES[@]} > 0)); then
            log INFO "Found ${#MODIFIED_FILES[@]} modified file(s). Will back up before sync."
        else
            log INFO "No modified files detected (index-only changes)."
        fi
    fi

    # --------------------------------------------------------------------------
    # FIX REMOTE URL
    # --------------------------------------------------------------------------
    local current_url
    current_url=$("${GIT_CMD[@]}" remote get-url origin 2>/dev/null) || current_url=""

    if [[ -z "$current_url" ]]; then
        log WARN "No origin remote. Adding..."
        "${GIT_CMD[@]}" remote add origin "$REPO_URL"
    # URL Normalization: Ignore .git suffix difference as they are functionally identical
    elif [[ "${current_url%.git}" != "${REPO_URL%.git}" ]]; then
        log WARN "Remote mismatch: $current_url"
        log INFO "Setting to: $REPO_URL"
        "${GIT_CMD[@]}" remote set-url origin "$REPO_URL"
    fi

    # --------------------------------------------------------------------------
    # FETCH LATEST (With Exponential Backoff)
    # --------------------------------------------------------------------------
    log INFO "Fetching from upstream..."

    local fetch_success="false"
    local attempt=1
    local -r max_attempts=5
    local wait_time=2

    while ((attempt <= max_attempts)); do
        if timeout 60s "${GIT_CMD[@]}" fetch origin "+refs/heads/${BRANCH}:refs/remotes/origin/${BRANCH}" >> "$LOG_FILE" 2>&1; then
            fetch_success="true"
            break
        fi

        if ((attempt < max_attempts)); then
            log WARN "Fetch attempt $attempt/$max_attempts failed. Retrying in ${wait_time}s..."
            sleep "$wait_time"
            ((wait_time *= 2))
        fi
        ((attempt++))
    done

    if [[ "$fetch_success" == "false" ]]; then
        log ERROR "Fetch failed after $max_attempts attempts. Check network."
        return 1
    fi

    log OK "Fetch complete."

    # --------------------------------------------------------------------------
    # HANDLE UNTRACKED FILE COLLISIONS
    # --------------------------------------------------------------------------
    local remote_files untracked_files collision_list
    remote_files=$("${GIT_CMD[@]}" ls-tree -r --name-only "origin/${BRANCH}" 2>/dev/null) || remote_files=""
    untracked_files=$("${GIT_CMD[@]}" ls-files --others --exclude-standard 2>/dev/null) || untracked_files=""

    if [[ -n "$remote_files" && -n "$untracked_files" ]]; then
        collision_list=$(comm -12 <(printf '%s\n' "$remote_files" | sort) \
                                  <(printf '%s\n' "$untracked_files" | sort) 2>/dev/null) || collision_list=""
    else
        collision_list=""
    fi

    if [[ -n "$collision_list" ]]; then
        local backup_dir="${HOME}/Documents/dusky_backup_${RUN_TIMESTAMP}"
        log WARN "Untracked collisions found. Backing up..."
        mkdir -p "$backup_dir"

        while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            [[ -e "${WORK_TREE}/${file}" ]] || continue
            mkdir -p "$backup_dir/$(dirname "$file")"
            mv -- "${WORK_TREE}/${file}" "$backup_dir/${file}"
            log RAW "  → Backed up: $file"
        done <<< "$collision_list"

        log OK "Collisions backed up to: $backup_dir"
    fi

    # --------------------------------------------------------------------------
    # SYNC STRATEGY: RESET TO UPSTREAM
    # --------------------------------------------------------------------------
    log INFO "Checking sync status..."

    local local_head remote_head base_commit
    local_head=$("${GIT_CMD[@]}" rev-parse HEAD 2>/dev/null) || local_head=""
    remote_head=$("${GIT_CMD[@]}" rev-parse "origin/${BRANCH}" 2>/dev/null) || remote_head=""

    if [[ -z "$local_head" || -z "$remote_head" ]]; then
        log ERROR "Cannot determine HEAD commits"
        log ERROR "local_head='$local_head' remote_head='$remote_head'"
        return 1
    fi

    if [[ "$local_head" == "$remote_head" ]]; then
        log OK "Already up to date."
    else
        base_commit=$("${GIT_CMD[@]}" merge-base "$local_head" "$remote_head" 2>/dev/null) || base_commit=""

        if [[ "$base_commit" == "$local_head" ]]; then
            log INFO "Fast-forwarding to upstream..."
            # Back up user modifications before reset --hard
            if ((${#MODIFIED_FILES[@]} > 0)); then
                if ! backup_user_modifications; then
                    log ERROR "Backup failed. Aborting update to protect your files."
                    return 1
                fi
            fi
            if "${GIT_CMD[@]}" reset --hard "origin/${BRANCH}" >> "$LOG_FILE" 2>&1; then
                log OK "Updated to latest."
                restore_user_modifications
            else
                log ERROR "Reset failed"
                return 1
            fi
        else
            log WARN "Local history diverged from upstream."
            printf '\n'
            printf '%s[DIVERGED HISTORY]%s Choose sync method:\n' "$CLR_YLW" "$CLR_RST"
            printf '  1) Abort (keep current state)\n'
            printf '  %s2) Reset to upstream [RECOMMENDED]%s\n' "$CLR_GRN" "$CLR_RST"
            printf '     Your uncommitted tweaks will be backed up and auto-restored where safe.\n'
            printf '  3) Attempt rebase (may fail)\n'
            printf '\n'

            local sync_choice
            if [[ -t 0 ]]; then
                read -r -t 60 -p "Choice [1-3] (default: 2): " sync_choice 2>/dev/null || sync_choice="2"
            else
                sync_choice="2"
            fi
            sync_choice="${sync_choice:-2}"

            case "$sync_choice" in
                1)
                    log INFO "Aborted."
                    return 1
                    ;;
                2)
                    backup_tracked_files || log WARN "Backup failed, but continuing..."
                    # Back up user modifications before reset --hard
                    if ((${#MODIFIED_FILES[@]} > 0)); then
                        if ! backup_user_modifications; then
                            log ERROR "Backup failed. Aborting update to protect your files."
                            return 1
                        fi
                    fi
                    log INFO "Resetting to upstream..."
                    if "${GIT_CMD[@]}" reset --hard "origin/${BRANCH}" >> "$LOG_FILE" 2>&1; then
                        log OK "Reset complete."
                        restore_user_modifications
                    else
                        log ERROR "Reset failed"
                        return 1
                    fi
                    ;;
                3)
                    backup_tracked_files || log WARN "Backup failed, but continuing..."
                    # Back up user modifications before rebase (rebase can write conflict markers)
                    if ((${#MODIFIED_FILES[@]} > 0)); then
                        if ! backup_user_modifications; then
                            log ERROR "Backup failed. Aborting update to protect your files."
                            return 1
                        fi
                    fi
                    # FIX BUG 3: git rebase refuses to run on a dirty working tree.
                    # Now that modifications are safely backed up, clean the working
                    # tree so rebase can proceed. reset --hard HEAD stays on the same
                    # commit — it only cleans the index and working tree.
                    "${GIT_CMD[@]}" reset --hard HEAD >> "$LOG_FILE" 2>&1 || true
                    log INFO "Attempting rebase..."
                    local rebase_output rebase_rc=0
                    rebase_output=$("${GIT_CMD[@]}" rebase "origin/${BRANCH}" 2>&1) || rebase_rc=$?
                    printf '%s\n' "$rebase_output" >> "$LOG_FILE"

                    if ((rebase_rc != 0)); then
                        log ERROR "Rebase failed."
                        log INFO "Aborting and resetting..."
                        "${GIT_CMD[@]}" rebase --abort >> "$LOG_FILE" 2>&1 || true

                        if "${GIT_CMD[@]}" reset --hard "origin/${BRANCH}" >> "$LOG_FILE" 2>&1; then
                            log OK "Fallback reset complete."
                            restore_user_modifications
                        else
                            log ERROR "Reset also failed."
                            return 1
                        fi
                    else
                        log OK "Rebase successful."
                        restore_user_modifications
                    fi
                    ;;
                *)
                    log INFO "Invalid. Aborting."
                    return 1
                    ;;
            esac
        fi
    fi

    log OK "Repository synchronized."
    return 0
}

# ------------------------------------------------------------------------------
# SCRIPT EXECUTION
# ------------------------------------------------------------------------------
run_script() {
    (($# >= 2)) || { log ERROR "run_script: need mode and script"; return 1; }

    local -r mode="$1" script="$2"
    shift 2
    local -a args=("$@")
    local script_path

    # Check for custom path override using -v (valid in Bash 4.3+)
    if [[ -v "CUSTOM_SCRIPT_PATHS[$script]" && -n "${CUSTOM_SCRIPT_PATHS[$script]}" ]]; then
        script_path="${HOME}/${CUSTOM_SCRIPT_PATHS[$script]}"
    else
        script_path="${SCRIPT_DIR}/${script}"
    fi

    [[ -f "$script_path" ]] || { log WARN "Not found: $script"; return 0; }
    [[ -r "$script_path" ]] || { log WARN "Not readable: $script"; return 0; }

    printf '%s→%s %s %s\n' "$CLR_BLU" "$CLR_RST" "$script" "${args[*]:-}"

    local rc=0
    case "$mode" in
        S) sudo "$BASH_BIN" "$script_path" "${args[@]}" || rc=$? ;;
        U) "$BASH_BIN" "$script_path" "${args[@]}" || rc=$? ;;
        *) log WARN "Unknown mode: $mode"; return 0 ;;
    esac

    ((rc == 0)) || { log ERROR "$script failed (exit $rc)"; FAILED_SCRIPTS+=("$script"); }
    return 0
}

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------
main() {
    # Check dependencies first (before any logging)
    check_dependencies

    # --------------------------------------------------------------------------
    # USER INTERACTION SAFETY CHECK
    # --------------------------------------------------------------------------
    if [[ -t 0 ]]; then
        printf '\n%s⚠️  WARNING: DO NOT INTERRUPT THE UPDATE WHILE ITS RUNNING! ⚠️%s\n' "${CLR_RED}" "${CLR_RST}"
        printf 'Interrupting the process causes Git locks and inconsistent states.\n'
        printf 'Please allow the update to complete fully before closing.\n\n'
        
        local start_confirm
        read -r -p "Do you understand and wish to start the update? [y/N] " start_confirm
        if [[ ! "$start_confirm" =~ ^[Yy]$ ]]; then
            printf 'Update cancelled. You can run it later.\n'
            exit 0
        fi
    fi

    setup_logging

    # Exclusive lock with proper error handling
    if ! : >"$LOCK_FILE" 2>/dev/null; then
        printf 'Error: Cannot create lock file: %s\n' "$LOCK_FILE" >&2
        exit 1
    fi
    exec 9>"$LOCK_FILE"
    flock -n 9 || { log ERROR "Another instance running"; exit 1; }

    # Self-update check hash
    local self_hash_before=""
    [[ -r "$SELF_PATH" ]] && self_hash_before=$(sha256sum "$SELF_PATH" 2>/dev/null | cut -d' ' -f1)

    init_sudo

    if ! pull_updates; then
        log WARN "Sync failed."
        local cont=""
        if [[ -t 0 ]]; then
            read -r -t 30 -p "Continue with local scripts? [y/N] " cont || cont="n"
        else
            cont="n"
        fi
        [[ "$cont" =~ ^[Yy]$ ]] || exit 1
    else
        # Self-update re-exec
        if [[ -n "$self_hash_before" && -r "$SELF_PATH" ]]; then
            local self_hash_after
            self_hash_after=$(sha256sum "$SELF_PATH" 2>/dev/null | cut -d' ' -f1) || self_hash_after=""
            if [[ -n "$self_hash_after" && "$self_hash_before" != "$self_hash_after" ]]; then
                log SECTION "Self-Update Detected"
                log OK "Reloading..."
                exec 9>&-
                rm -f "$LOCK_FILE"
                USER_MODS_BACKUP=""
                exec "$SELF_PATH" "$@"
            fi
        fi
    fi

    [[ -d "$SCRIPT_DIR" ]] || { log ERROR "Script dir missing: $SCRIPT_DIR"; exit 1; }

    log SECTION "Executing Update Sequence"

    local entry mode script_part script
    local -a parts args

    for entry in "${UPDATE_SEQUENCE[@]}"; do
        [[ "$entry" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${entry//[[:space:]]/}" ]] && continue

        mode=$(trim "${entry%%|*}")
        script_part=$(trim "${entry#*|}")
        read -ra parts <<< "$script_part"
        script="${parts[0]:-}"
        args=("${parts[@]:1}")

        [[ -n "$script" ]] || { log WARN "Malformed: $entry"; continue; }
        run_script "$mode" "$script" "${args[@]}"
    done
}

main "$@"
