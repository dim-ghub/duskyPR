#!/usr/bin/env bash
# ==============================================================================
# WAYCLICK RESET PROTOCOL - FACTORY RESET & REBUILD (GOLDEN COPY)
# ==============================================================================
# "Chaos isn't a pit. Chaos is a ladder."
#
# ARCHITECTURE:
# 1. Pre-Flight Checks (Verify compilers/libs EXIST before deleting anything)
# 2. Termination (Ruthless process killing)
# 3. Sanitation (Deep clean of artifacts)
# 4. Reconstruction (Native AVX2 compilation)
# ==============================================================================

set -euo pipefail

# --- CONFIGURATION (SYNCED WITH MAIN) ---
readonly APP_NAME="wayclick"
readonly BASE_DIR="$HOME/contained_apps/uv/$APP_NAME"
readonly VENV_DIR="$BASE_DIR/.venv"
readonly PYTHON_BIN="$VENV_DIR/bin/python"
readonly RUNNER_SCRIPT="$BASE_DIR/runner.py"
readonly MARKER_FILE="$BASE_DIR/.build_marker_v5"
readonly STATE_FILE="$HOME/.config/dusky/settings/wayclick"
readonly CONFIG_DIR="$HOME/.config/wayclick"

# --- ANSI COLORS ---
readonly C_RED=$'\033[1;31m'
readonly C_GREEN=$'\033[1;32m'
readonly C_BLUE=$'\033[1;34m'
readonly C_YELLOW=$'\033[1;33m'
readonly C_CYAN=$'\033[1;36m'
readonly C_DIM=$'\033[2m'
readonly C_RESET=$'\033[0m'

# --- UTILS ---
log() { printf "%b[%s]%b %s\n" "$1" "$2" "${C_RESET}" "$3"; }
die() { log "${C_RED}" "FATAL" "$1"; exit 1; }

# --- ROOT CHECK ---
(( EUID == 0 )) && die "Do not run the reset protocol as root."

printf "%b
╔══════════════════════════════════════════════════════════════╗
║  %bWAYCLICK FACTORY RESET%b                                      ║
║  %bIntegrity Check • Purge • Native Rebuild%b                    ║
╚══════════════════════════════════════════════════════════════╝
%b" "${C_RED}" "${C_YELLOW}" "${C_RED}" "${C_DIM}" "${C_RED}" "${C_RESET}"

# ==============================================================================
# PHASE 1: PRE-FLIGHT INTEGRITY CHECKS
# Do not destroy the old house until we have the bricks to build the new one.
# ==============================================================================
log "${C_BLUE}" "CHECK" "Verifying build capability..."

# 1. Check for uv
command -v uv >/dev/null 2>&1 || die "'uv' is missing. Cannot rebuild."

# 2. Check for Compilers (Required for --no-binary)
command -v gcc >/dev/null 2>&1 || die "GCC is missing. Native compilation impossible."

# 3. Check for System Libraries (Arch Names)
# We don't install them here (keep it interactive-free if possible), but we warn.
MISSING_DEPS=()
for pkg in sdl2 sdl2_mixer sdl2_image sdl2_ttf; do
    if ! pacman -Qq "$pkg" >/dev/null 2>&1; then
        MISSING_DEPS+=("$pkg")
    fi
done

if (( ${#MISSING_DEPS[@]} > 0 )); then
    log "${C_YELLOW}" "WARN" "Missing system headers: ${MISSING_DEPS[*]}"
    read -rp "       Attempt to install via sudo? [Y/n] " -n 1
    echo
    if [[ ${REPLY:-Y} =~ ^[Yy]$ ]]; then
        if ! sudo pacman -S --needed --noconfirm "${MISSING_DEPS[@]}"; then
             die "Failed to install dependencies. Aborting reset to preserve current state."
        fi
    else
        die "Cannot rebuild without system dependencies."
    fi
fi

# ==============================================================================
# PHASE 2: TERMINATION PROTOCOL
# ==============================================================================
if pgrep -f "$RUNNER_SCRIPT" >/dev/null 2>&1; then
    log "${C_YELLOW}" "KILL" "Stopping active WayClick instances..."
    
    # 1. Update State
    mkdir -p "$(dirname "$STATE_FILE")"
    echo "False" > "$STATE_FILE"

    # 2. Soft Kill
    pkill -TERM -f "$RUNNER_SCRIPT" 2>/dev/null || true
    
    # 3. Verification Loop
    for _ in {1..30}; do
        pgrep -f "$RUNNER_SCRIPT" >/dev/null 2>&1 || break
        sleep 0.1
    done
    
    # 4. Hard Kill
    pkill -KILL -f "$RUNNER_SCRIPT" 2>/dev/null || true
else
    log "${C_BLUE}" "INFO" "No active instances found."
fi

# ==============================================================================
# PHASE 3: SANITIZATION (THE PURGE)
# ==============================================================================
log "${C_RED}" "WIPE" "Purging environment and build artifacts..."

# Remove the specific Venv and Marker, but keep the parent dir structure if valid
rm -rf "$VENV_DIR"
rm -f "$MARKER_FILE"
rm -f "$RUNNER_SCRIPT"

# Clean any compiled python cache in the base dir
if [[ -d "$BASE_DIR" ]]; then
    find "$BASE_DIR" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
fi

# Optional: Nuke config if requested (Commented out for safety, usually we want to keep settings)
# rm -rf "$CONFIG_DIR" 

log "${C_GREEN}" "CLEAN" "Environment sanitized."

# ==============================================================================
# PHASE 4: RECONSTRUCTION (NATIVE COMPILE)
# ==============================================================================
log "${C_BLUE}" "BUILD" "Initializing UV Environment (Python 3.14)..."

mkdir -p "$BASE_DIR"

# Force Python 3.14. If user doesn't have it, UV will try to fetch it.
if ! uv venv "$VENV_DIR" --python 3.14 --quiet; then
    die "Failed to create virtual environment."
fi

log "${C_YELLOW}" "COMP" "Compiling Native Extensions (AVX2/LTO)..."
printf "       %bOptimization Flags:%b -march=native -O3 -flto=auto\n" "${C_DIM}" "${C_RESET}"

export CFLAGS="-march=native -mtune=native -O3 -pipe -fno-plt -flto=auto -ffat-lto-objects"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,now,--relax -flto=auto"

# We use the specific python binary to ensure we are installing INTO the venv we just made
if uv pip install --python "$PYTHON_BIN" \
    --no-binary :all: \
    --compile-bytecode \
    evdev pygame-ce >/dev/null 2>&1; then
    
    touch "$MARKER_FILE"
    log "${C_GREEN}" "SUCCESS" "Build complete. Optimization verified."
else
    # ROLLBACK / ERROR INFO
    log "${C_RED}" "FAIL" "Compilation failed."
    printf "       Run 'uv pip install ...' manually to see the error log.\n"
    exit 1
fi

# ==============================================================================
# PHASE 5: VERIFICATION
# ==============================================================================

if [[ -f "$PYTHON_BIN" && -f "$MARKER_FILE" ]]; then
    printf "%b
════════════════════════════════════════════════════════════════
   %bSYSTEM RESET SUCCESSFUL%b
   The environment has been rebuilt from source.
   Run 'wayclick' to restart the engine.
════════════════════════════════════════════════════════════════
%b" "${C_DIM}" "${C_GREEN}" "${C_DIM}" "${C_RESET}"
else
    die "Verification failed. Files missing after build."
fi
