#!/usr/bin/env bash
# ==============================================================================
# WAYCLICK INSTALLER - ARCH LINUX / UV OPTIMIZED
# ==============================================================================
# This script performs the "Build & Setup" phase only.
# It compiles dependencies, generates the runner, and verifies config.
# It does NOT start the application.
# ==============================================================================

set -euo pipefail
trap cleanup EXIT INT TERM

# --- CONFIGURATION ---
readonly APP_NAME="wayclick"
readonly BASE_DIR="$HOME/contained_apps/uv/$APP_NAME"
readonly VENV_DIR="$BASE_DIR/.venv"
readonly PYTHON_BIN="$VENV_DIR/bin/python"
readonly RUNNER_SCRIPT="$BASE_DIR/runner.py"
readonly CONFIG_DIR="$HOME/.config/wayclick"
readonly STATE_FILE="$HOME/.config/dusky/settings/wayclick"

# --- ANSI COLORS ---
readonly C_RED=$'\033[1;31m'
readonly C_GREEN=$'\033[1;32m'
readonly C_BLUE=$'\033[1;34m'
readonly C_CYAN=$'\033[1;36m'
readonly C_YELLOW=$'\033[1;33m'
readonly C_DIM=$'\033[2m'
readonly C_RESET=$'\033[0m'

# --- STATE MANAGEMENT ---
update_state() {
    local status="$1"
    local dir state_tmp
    dir="${STATE_FILE%/*}"
    state_tmp="${STATE_FILE}.tmp.$$"
    
    mkdir -p "$dir" 2>/dev/null || true
    printf '%s\n' "$status" > "$state_tmp" && mv -f "$state_tmp" "$STATE_FILE"
}

cleanup() {
    # Ensure state is False (Installed, not running)
    update_state "False"
}

# --- CHECKS ---

# 0. Root Check
if (( EUID == 0 )); then
    printf "%b[CRITICAL]%b Do not run this script as root.\n" "${C_RED}" "${C_RESET}"
    exit 1
fi

# 1. Interactive Mode Detection
[[ -t 0 ]] && INTERACTIVE=true || INTERACTIVE=false

notify_user() {
    command -v notify-send >/dev/null 2>&1 && notify-send --app-name="WayClick" "WayClick Setup" "$1"
}

# 2. Dependency Check
declare -a NEEDED_DEPS=()
command -v uv >/dev/null 2>&1 || NEEDED_DEPS+=("uv")
command -v notify-send >/dev/null 2>&1 || NEEDED_DEPS+=("libnotify")

# Check for build tools required for source installation
if [[ ! -f "$BASE_DIR/.build_marker_v5" ]]; then
    command -v gcc >/dev/null 2>&1 || NEEDED_DEPS+=("gcc")
    if ! pacman -Qq sdl2 >/dev/null 2>&1; then
        NEEDED_DEPS+=("sdl2" "sdl2_mixer" "sdl2_image" "sdl2_ttf")
    fi
fi

if (( ${#NEEDED_DEPS[@]} > 0 )); then
    if $INTERACTIVE; then
        printf "%b[SETUP]%b Missing system dependencies:%b %s%b\n" "${C_YELLOW}" "${C_RESET}" "${C_CYAN}" "${NEEDED_DEPS[*]}" "${C_RESET}"
        if sudo pacman -S --needed --noconfirm "${NEEDED_DEPS[@]}"; then
            printf "%b[SUCCESS]%b Dependencies installed.\n" "${C_GREEN}" "${C_RESET}"
        else
            printf "%b[ERROR]%b Installation failed.\n" "${C_RED}" "${C_RESET}"
            exit 1
        fi
    else
        # In non-interactive mode (Orchestra), fail if deps are missing and let the user handle it,
        # OR rely on Orchestra's earlier steps.
        notify_user "Missing dependencies (${NEEDED_DEPS[*]})."
        exit 1
    fi
fi

# 3. Group Permission Check
if ! id -nG "$USER" | grep -qw input; then
    if $INTERACTIVE; then
        printf "%b[PERM]%b User '%s' is not in the 'input' group.\n" "${C_RED}" "${C_RESET}" "$USER"
        read -rp "Run 'sudo usermod -aG input $USER'? [Y/n] " -n 1
        echo
        if [[ ${REPLY:-Y} =~ ^[Yy]$ ]]; then
            sudo usermod -aG input "$USER"
            printf "%b[INFO]%b Group added. %bLOGOUT REQUIRED%b for changes to apply.\n" "${C_GREEN}" "${C_RESET}" "${C_RED}" "${C_RESET}"
        fi
    else
        # Attempt silent fix in Orchestra mode if sudo is available without password (via Orchestra's keepalive)
        if sudo -n true 2>/dev/null; then
             sudo usermod -aG input "$USER"
        else
             notify_user "Permission error: User not in 'input' group."
             exit 1
        fi
    fi
fi

# 4. Sound Files Check
check_sounds() {
    [[ -d "$CONFIG_DIR" && -f "${CONFIG_DIR}/config.json" ]]
}

if ! check_sounds; then
    mkdir -p "$CONFIG_DIR" 2>/dev/null || true
    # Create a dummy config if it doesn't exist to prevent crash, 
    # but warn user they need assets.
    if [[ ! -f "${CONFIG_DIR}/config.json" ]]; then
        printf "%b[WARN]%b No config.json found in %s. Please populate assets.\n" "${C_YELLOW}" "${C_RESET}" "$CONFIG_DIR"
    fi
fi

# --- ENVIRONMENT SETUP ---

mkdir -p "$BASE_DIR" 2>/dev/null || true

if [[ ! -d "$VENV_DIR" ]]; then
    printf "%b[BUILD]%b Initializing UV environment...\n" "${C_BLUE}" "${C_RESET}"
    uv venv "$VENV_DIR" --python 3.14 --quiet
fi

MARKER_FILE="$BASE_DIR/.build_marker_v5"

if [[ ! -f "$MARKER_FILE" ]]; then
    printf "%b[BUILD]%b Compiling dependencies with NATIVE CPU FLAGS (AVX2+ / LTO)...\n" "${C_YELLOW}" "${C_RESET}"
    
    export CFLAGS="-march=native -mtune=native -O3 -pipe -fno-plt -flto=auto -ffat-lto-objects"
    export CXXFLAGS="$CFLAGS"
    export LDFLAGS="-Wl,-O1,--sort-common,--as-needed,-z,now,--relax -flto=auto"
    
    uv pip install --python "$PYTHON_BIN" \
        --no-binary :all: \
        --compile-bytecode \
        evdev pygame-ce

    touch "$MARKER_FILE"
    printf "%b[SUCCESS]%b Native build complete.\n" "${C_GREEN}" "${C_RESET}"
fi

# --- PYTHON RUNNER GENERATION ---
# We regenerate this every time to ensure updates to the script logic propagate
cat > "$RUNNER_SCRIPT" << 'PYTHON_EOF'
import asyncio
import os
import sys
import signal
import random
import json

# === STARTUP OPTIMIZATION ===
os.environ['PYGAME_HIDE_SUPPORT_PROMPT'] = '1'
os.environ['SDL_BUFFER_CHUNK_SIZE'] = '512'
os.environ['SDL_AUDIODRIVER'] = 'pipewire,pulseaudio,alsa'

import pygame
import evdev

C_GREEN, C_YELLOW, C_BLUE, C_RED, C_RESET = "\033[1;32m", "\033[1;33m", "\033[1;34m", "\033[1;31m", "\033[0m"

ASSET_DIR = sys.argv[1]
ENABLE_TRACKPADS = os.environ.get('ENABLE_TRACKPADS', 'false').lower() == 'true'

# === DYNAMIC IDENTIFIERS ===
raw_identifiers = os.environ.get('WC_TRACKPAD_IDS', 'touchpad,trackpad')
TRACKPAD_KEYWORDS = [x.strip().lower() for x in raw_identifiers.split(',') if x.strip()]

# === AUDIO INIT ===
try:
    pygame.mixer.pre_init(frequency=48000, size=-16, channels=2, buffer=512)
    pygame.mixer.init()
    pygame.mixer.set_num_channels(32)
except pygame.error as e:
    sys.exit(f"{C_RED}[AUDIO ERROR]{C_RESET} {e}")

# === CONFIG LOADING ===
CONFIG_FILE = os.path.join(ASSET_DIR, "config.json")
print(f"{C_BLUE}[INFO]{C_RESET} Loading assets from {ASSET_DIR}...")

try:
    with open(CONFIG_FILE, 'r') as f:
        config_data = json.load(f)
        RAW_KEY_MAP = {int(k): v for k, v in config_data.get("mappings", {}).items()}
        DEFAULTS = config_data.get("defaults", [])
except Exception as e:
    sys.exit(f"{C_RED}[CONFIG ERROR]{C_RESET} Failed to load {CONFIG_FILE}: {e}")

# === SOUND LOADING ===
SOUND_FILES = set(RAW_KEY_MAP.values()) | set(DEFAULTS)
SOUNDS = {}

for filename in SOUND_FILES:
    path = os.path.join(ASSET_DIR, filename)
    if os.path.exists(path):
        try:
            SOUNDS[filename] = pygame.mixer.Sound(path)
        except pygame.error:
            print(f"{C_YELLOW}[WARN]{C_RESET} Failed to load wav: {filename}")
    else:
        print(f"{C_YELLOW}[WARN]{C_RESET} File not found: {filename}")

if not SOUNDS:
    sys.exit("ERROR: No sounds loaded! Check your config.json and .wav files.")

# === PERFORMANCE: LIST CACHE LOOKUP ===
MAX_KEYCODE = 65536
SOUND_CACHE = [None] * MAX_KEYCODE
DEFAULT_SOUND_OBJS = tuple(SOUNDS[f] for f in DEFAULTS if f in SOUNDS)

for code, filename in RAW_KEY_MAP.items():
    if code < MAX_KEYCODE and filename in SOUNDS:
        SOUND_CACHE[code] = SOUNDS[filename]

# === HOT PATH PRE-BINDING ===
_random_choice = random.choice
_sound_cache = SOUND_CACHE
_max_keycode = MAX_KEYCODE
_defaults = DEFAULT_SOUND_OBJS
_has_defaults = bool(DEFAULT_SOUND_OBJS)

def play_sound(code):
    if code < _max_keycode:
        sound = _sound_cache[code]
        if sound is not None:
            sound.play()
            return
    if _has_defaults:
        _random_choice(_defaults).play()

async def read_device(dev, stop_event):
    _play = play_sound
    _is_stopped = stop_event.is_set
    
    print(f"{C_GREEN}[+] Connected:{C_RESET} {dev.name}")
    try:
        async for event in dev.async_read_loop():
            if _is_stopped():
                break
            if event.type == 1 and event.value == 1:
                _play(event.code)
                
    except (OSError, IOError):
        print(f"{C_YELLOW}[-] Disconnected:{C_RESET} {dev.path}")
    except asyncio.CancelledError:
        pass
    finally:
        dev.close()

async def main():
    print(f"{C_BLUE}[CORE]{C_RESET} Engine started. Monitoring devices...")
    
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, stop.set)
    
    monitored_tasks = {}
    _list_devices = evdev.list_devices

    while not stop.is_set():
        try:
            all_paths = _list_devices()
            
            for path in all_paths:
                if path in monitored_tasks:
                    continue
                
                try:
                    dev = evdev.InputDevice(path)
                    
                    if not ENABLE_TRACKPADS:
                        # GENERIC CHECK: Compare device name against user list
                        name_lower = dev.name.lower()
                        is_trackpad = any(k in name_lower for k in TRACKPAD_KEYWORDS)
                        
                        if is_trackpad:
                            dev.close()
                            continue

                    caps = dev.capabilities()
                    if 1 in caps:  # EV_KEY
                        task = asyncio.create_task(read_device(dev, stop))
                        monitored_tasks[path] = task
                    else:
                        dev.close()
                except (OSError, IOError):
                    continue

        except Exception as e:
            print(f"Discovery Loop Error: {e}")

        dead_paths = [p for p, t in monitored_tasks.items() if t.done()]
        for p in dead_paths:
            del monitored_tasks[p]

        try:
            await asyncio.wait_for(stop.wait(), timeout=3.0)
        except asyncio.TimeoutError:
            continue
    
    print("\nStopping...")
    for t in monitored_tasks.values():
        t.cancel()
    if monitored_tasks:
        await asyncio.gather(*monitored_tasks.values(), return_exceptions=True)
    pygame.mixer.quit()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
PYTHON_EOF

# --- COMPLETION ---
printf "%b[SETUP]%b WayClick Elite installation complete.\n" "${C_GREEN}" "${C_RESET}"
printf "       Run 'wayclick' to toggle the service.\n"

# Ensure state file says False
update_state "False"
exit 0
