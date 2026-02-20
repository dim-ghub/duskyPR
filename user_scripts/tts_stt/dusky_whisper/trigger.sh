#!/usr/bin/env bash
# Dusky STT Trigger (nvidia edition)
# Toggle behavior: First run starts recording. Second run stops recording and transcribes.

readonly APP_DIR="/home/dusk/contained_apps/uv/dusky_stt"
readonly PID_FILE="/tmp/dusky_stt.pid"
readonly READY_FILE="/tmp/dusky_stt.ready"
readonly FIFO_PATH="/tmp/dusky_stt.fifo"
readonly DAEMON_LOG="/tmp/dusky_stt.log"
readonly DEBUG_LOG="$APP_DIR/dusky_stt_debug.log"
readonly INSTALL_MODE="nvidia"

# Recording vars
readonly RECORD_PID_FILE="/tmp/dusky_stt_record.pid"
readonly YAD_PID_FILE="/tmp/dusky_stt_yad.pid"
readonly AUDIO_TMP_FILE="/tmp/dusky_stt_capture.wav"
DEFAULT_MODEL="distil-large-v3"

# --- Helpers ---
get_libs() {
    if [[ "$INSTALL_MODE" == "nvidia" ]]; then
        local SITE_PACKAGES
        SITE_PACKAGES=$(find "$APP_DIR/.venv" -type d -name "site-packages" 2>/dev/null | head -n 1)
        if [[ -n "$SITE_PACKAGES" && -d "$SITE_PACKAGES/nvidia" ]]; then
            # Extract paths for cublas, cudnn, and cudart injected via uv
            find "$SITE_PACKAGES/nvidia" -type d -name "lib" | tr '\n' ':' | sed 's/:$//'
        fi
    fi
}

notify() { notify-send "$@" 2>/dev/null || true; }

is_running() { [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; }

stop_daemon() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE" 2>/dev/null)
        if [[ -n "$pid" ]]; then
            kill "$pid" 2>/dev/null || true
            sleep 1
            kill -9 "$pid" 2>/dev/null || true
        fi
    fi
    rm -f "$PID_FILE" "$FIFO_PATH" "$READY_FILE" "$RECORD_PID_FILE" "$YAD_PID_FILE"
}

start_daemon() {
    local debug_mode="${1:-false}"
    
    local EXTRA_LIBS=$(get_libs)
    if [[ -n "$EXTRA_LIBS" ]]; then
        export LD_LIBRARY_PATH="${EXTRA_LIBS}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    fi

    cd "$APP_DIR"
    if [[ "$debug_mode" == "true" ]]; then
        export DUSKY_STT_LOG_LEVEL="DEBUG"
        export DUSKY_STT_LOG_FILE="$DEBUG_LOG"
        nohup uv run dusky_stt_main.py --daemon --mode "$INSTALL_MODE" --debug-file "$DEBUG_LOG" > "$DAEMON_LOG" 2>&1 &
    else
        nohup uv run dusky_stt_main.py --daemon --mode "$INSTALL_MODE" > "$DAEMON_LOG" 2>&1 &
    fi

    local daemon_pid=$!
    echo "$daemon_pid" > "$PID_FILE"

    for _ in {1..150}; do
        if [[ -f "$READY_FILE" ]]; then return 0; fi
        if ! kill -0 "$daemon_pid" 2>/dev/null; then return 1; fi
        sleep 0.2
    done
    return 1
}

show_help() {
    cat << 'HELP'
Dusky STT — Trigger Script
USAGE:
    ./trigger.sh                   (Toggle record/transcribe)
    ./trigger.sh --model <name>    (Use specific model)
    ./trigger.sh --kill            (Stop the background daemon)
    ./trigger.sh --restart         (Restart the background daemon)
    ./trigger.sh --debug           (Start daemon in debug mode)
    ./trigger.sh --logs            (Tail daemon logs)

MODELS: tiny.en, base.en, small.en, medium.en, distil-large-v3
HELP
}

# --- CLI Logic ---
MODEL="$DEFAULT_MODEL"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h) show_help; exit 0 ;;
        --kill) stop_daemon; echo ":: Daemon stopped."; exit 0 ;;
        --model|-m) MODEL="$2"; shift 2 ;;
        --logs) tail -f "$DAEMON_LOG"; exit 0 ;;
        --debug) 
            stop_daemon; 
            echo ":: Starting Daemon in Debug Mode..."
            start_daemon "true"; 
            tail -f "$DEBUG_LOG"; 
            exit $? ;;
        --restart) 
            stop_daemon; 
            echo ":: Restarting Daemon..."
            start_daemon "false"; 
            exit $? ;;
        *) echo "Unknown flag: $1"; exit 1 ;;
    esac
done

# Ensure daemon is running
if ! is_running; then
    rm -f "$FIFO_PATH" "$PID_FILE" "$READY_FILE"
    echo ":: Daemon not running. Booting it up..."
    if ! start_daemon "false"; then echo ":: ERROR: Daemon failed to start"; exit 1; fi
fi

# --- Audio Toggle Logic ---
if [[ -f "$RECORD_PID_FILE" ]] && kill -0 "$(cat "$RECORD_PID_FILE")" 2>/dev/null; then
    # WE ARE RECORDING -> STOP & TRANSCRIBE (Second Hotkey Press)
    REC_PID=$(cat "$RECORD_PID_FILE")
    kill -INT "$REC_PID" 2>/dev/null || true
    rm -f "$RECORD_PID_FILE"
    
    # Gracefully tear down the YAD UI Subshell
    if [[ -f "$YAD_PID_FILE" ]]; then
        kill "$(cat "$YAD_PID_FILE")" 2>/dev/null || true
        rm -f "$YAD_PID_FILE"
    fi
    pkill -f "yad --title=Dusky STT" 2>/dev/null || true
    
    echo -e ":: 🟢 Stopping recording. Transcribing with ${MODEL}..."
    
    # Send payload to FIFO
    printf "%s|%s\n" "$AUDIO_TMP_FILE" "$MODEL" > "$FIFO_PATH" &
else
    # NOT RECORDING -> START CAPTURE
    rm -f "$AUDIO_TMP_FILE"
    echo -e ":: 🔴 Recording Started! Use hotkey again or click popup to stop."
    
    # Use Pipewire native recorder
    pw-record --target auto "$AUDIO_TMP_FILE" &
    REC_PID=$!
    echo $REC_PID > "$RECORD_PID_FILE"

    # Launch elegant, non-blocking YAD popup in a subshell
    (
        yad_exit=0
        yad --title="Dusky STT" \
            --text="<span font='13' foreground='#ff4a4a'><b>🎙️ Recording Audio</b></span>\n<span font='10' foreground='#999999'>Press shortcut again or click below</span>" \
            --button="Transcribe:0" \
            --button="Cancel:1" \
            --width=280 \
            --borders=16 \
            --undecorated --on-top --fixed --center --skip-taskbar 2>/dev/null || yad_exit=$?
        
        # Guard: Only evaluate button clicks if the main hotkey didn't already cancel this subshell
        if [[ -f "$RECORD_PID_FILE" ]] && kill -0 "$(cat "$RECORD_PID_FILE")" 2>/dev/null; then
            if [ $yad_exit -eq 0 ]; then
                # User clicked 'Transcribe' -> Feed back into script logic
                "$0" --model "$MODEL"
            else
                # User pressed ESC or 'Cancel' -> Abort completely
                kill -INT "$(cat "$RECORD_PID_FILE")" 2>/dev/null || true
                rm -f "$RECORD_PID_FILE" "$AUDIO_TMP_FILE" "$YAD_PID_FILE"
                notify -t 1500 "Dusky STT" "Recording Cancelled."
            fi
        fi
    ) &
    YAD_PID=$!
    echo $YAD_PID > "$YAD_PID_FILE"
fi
