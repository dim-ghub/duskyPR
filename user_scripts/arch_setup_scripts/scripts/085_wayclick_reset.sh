#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Script: reinstall_wayclick.sh
# Description: Safely resets the 'wayclick' environment.
#              1. Nukes ALL instances (Python runner + Wrapper).
#              2. Removes the container directory.
#              3. Triggers the setup script.
# Environment: Arch Linux (Hyprland + UWSM)
# Author: Elite DevOps (Updated for Platinum Edition)
# -----------------------------------------------------------------------------

set -euo pipefail

# 1. Aesthetics & Logging
if [[ -t 1 ]]; then
    readonly C_RESET=$'\033[0m'
    readonly C_GREEN=$'\033[1;32m'
    readonly C_BLUE=$'\033[1;34m'
    readonly C_RED=$'\033[1;31m'
    readonly C_YELLOW=$'\033[1;33m'
else
    readonly C_RESET='' C_GREEN='' C_BLUE='' C_RED='' C_YELLOW=''
fi

log_info()    { printf "%s[INFO]%s %s\n" "${C_BLUE}" "${C_RESET}" "$1"; }
log_success() { printf "%s[OK]%s %s\n" "${C_GREEN}" "${C_RESET}" "$1"; }
log_warn()    { printf "%s[WARN]%s %s\n" "${C_YELLOW}" "${C_RESET}" "$1"; }
log_error()   { printf "%s[ERROR]%s %s\n" "${C_RED}" "${C_RESET}" "$1" >&2; }

# 2. Cleanup Trap
cleanup() {
    local exit_code=$?
    [[ -n "${C_RESET}" ]] && printf "%s" "${C_RESET}"
    exit "${exit_code}"
}
trap cleanup EXIT

# 3. Configuration
readonly APP_NAME="wayclick"
# Matches the BASE_DIR in your Platinum script
readonly DIR_TO_DELETE="${HOME}/contained_apps/uv/${APP_NAME}"
# ! IMPORTANT: Verify this path matches your actual setup script location !
readonly SETUP_SCRIPT="${HOME}/user_scripts/arch_setup_scripts/scripts/081_key_sound_wayclick_setup.sh"

# 4. Core Logic
main() {
    if (( EUID == 0 )); then
        log_error "Do NOT run with sudo. Run as your regular user."
        exit 1
    fi

    log_info "Initializing ${APP_NAME} reset procedure..."

    # -- Pre-flight: Validation --
    if [[ ! -f "${SETUP_SCRIPT}" ]]; then
        log_error "Setup script missing. Cannot proceed with reinstall."
        log_error "File expected: ${SETUP_SCRIPT}"
        exit 1
    fi

    if [[ ! -x "${SETUP_SCRIPT}" ]]; then
        chmod +x "${SETUP_SCRIPT}"
    fi

    # -- Step 1: Nuclear Process Kill --
    # We target 'runner.py' specifically because that is the audio engine.
    # We also target 'wayclick' just in case.
    log_info "Stopping active instances..."

    # Kill the Python Audio Engine (The real culprit)
    if pgrep -f "runner.py" >/dev/null 2>&1; then
        pkill -TERM -f "runner.py" 2>/dev/null || true
        log_warn "killed active audio engine (runner.py)"
    fi

    # Kill the Shell Wrapper
    if pgrep -x "wayclick" >/dev/null 2>&1; then
        pkill -x "wayclick" 2>/dev/null || true
    fi

    # Wait for death (max 3 seconds)
    local wait_count=0
    while (pgrep -f "runner.py" >/dev/null 2>&1 || pgrep -x "wayclick" >/dev/null 2>&1) && (( wait_count++ < 30 )); do
        sleep 0.1
    done

    # Force Kill if still alive
    pkill -KILL -f "runner.py" 2>/dev/null || true
    pkill -KILL -x "wayclick" 2>/dev/null || true

    log_success "All processes stopped."

    # -- Step 2: Delete Directory --
    # Standard safety checks for rm -rf
    if [[ -z "${DIR_TO_DELETE}" ]] || [[ "${DIR_TO_DELETE}" == "${HOME}" ]]; then
         log_error "Invalid delete target."
         exit 1
    fi

    if [[ -d "${DIR_TO_DELETE}" ]]; then
        log_info "Removing environment: ${DIR_TO_DELETE}"
        rm -rf "${DIR_TO_DELETE}"
        log_success "Cleaned up old installation."
    else
        log_info "Directory already clean."
    fi

    # -- Step 3: Execute Setup --
    log_info "Triggering setup script..."
    log_info "---------------------------------------------------"
    
    "${SETUP_SCRIPT}"

    log_info "---------------------------------------------------"
    log_success "Reset sequence complete."
}

main "$@"
