#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# SwayNC Position Controller - TUI v4.0 (Hardened)
# -----------------------------------------------------------------------------
# Target: Arch Linux / Hyprland / UWSM / Wayland
#
# Interactive TUI for setting SwayNC notification panel position (X and Y axis)
# and synchronizing the Hyprland slide animation direction.
# -----------------------------------------------------------------------------

set -euo pipefail
shopt -s extglob

# =============================================================================
# ▼ CONFIGURATION ▼
# =============================================================================

readonly SWAYNC_CONFIG="${HOME:?HOME is not set}/.config/swaync/config.json"
readonly HYPR_RULES="${HOME}/.config/hypr/source/window_rules.conf"

readonly APP_TITLE="SwayNC Position Controller"
readonly APP_VERSION="v4.0 (Stable)"

# Dimensions & Layout
declare -ri BOX_INNER_WIDTH=52
declare -ri MAX_DISPLAY_ROWS=10
declare -ri ITEM_PADDING=24

declare -ri HEADER_ROWS=5
declare -ri TAB_ROW=3
declare -ri ITEM_START_ROW=$((HEADER_ROWS + 1))

# =============================================================================
# ▲ END OF CONFIGURATION ▲
# =============================================================================

# --- Pre-computed Constants ---
declare _h_line_buf
printf -v _h_line_buf '%*s' "$BOX_INNER_WIDTH" ''
declare -r H_LINE="${_h_line_buf// /─}"
unset _h_line_buf

# --- ANSI Constants ---
declare -r C_RESET=$'\033[0m'
declare -r C_CYAN=$'\033[1;36m'
declare -r C_GREEN=$'\033[1;32m'
declare -r C_MAGENTA=$'\033[1;35m'
declare -r C_RED=$'\033[1;31m'
declare -r C_YELLOW=$'\033[1;33m'
declare -r C_WHITE=$'\033[1;37m'
declare -r C_GREY=$'\033[1;30m'
declare -r C_BLUE=$'\033[1;34m'
declare -r C_INVERSE=$'\033[7m'
declare -r CLR_EOL=$'\033[K'
declare -r CLR_EOS=$'\033[J'
declare -r CLR_SCREEN=$'\033[2J'
declare -r CURSOR_HOME=$'\033[H'
declare -r CURSOR_HIDE=$'\033[?25l'
declare -r CURSOR_SHOW=$'\033[?25h'
declare -r MOUSE_ON=$'\033[?1000h\033[?1002h\033[?1006h'
declare -r MOUSE_OFF=$'\033[?1000l\033[?1002l\033[?1006l'

declare -r ESC_READ_TIMEOUT=0.10

# --- State Management ---
declare -i SELECTED_ROW=0
declare -i SCROLL_OFFSET=0
declare ORIGINAL_STTY=""
declare CURRENT_POSITION_X=""
declare CURRENT_POSITION_Y=""
declare STATUS_MSG=""
declare STATUS_COLOR=""
declare -i NEEDS_REDRAW=1
declare -i TUI_RUNNING=0
declare _TMPFILE=""

# Tab management
declare -i CURRENT_TAB=0
declare -i TAB_SCROLL_START=0
declare -ra TABS=("Position" "Margins")
declare -ri TAB_COUNT=${#TABS[@]}
declare -a TAB_ZONES=()
declare LEFT_ARROW_ZONE=""
declare RIGHT_ARROW_ZONE=""

# Position options
declare -ra POS_X_OPTIONS=("left" "center" "right")
declare -ra POS_Y_OPTIONS=("bottom" "top")

# Margin values
declare -i MARGIN_TOP=0
declare -i MARGIN_BOTTOM=0
declare -i MARGIN_LEFT=0
declare -i MARGIN_RIGHT=0

# Menu items
declare -ra MENU_ITEMS=(
    "Set Position X:"
    "Set Position Y:"
    "Refresh Status"
    "Quit"
)
declare -ri MENU_COUNT=${#MENU_ITEMS[@]}

# Menu items for Margins tab
declare -ra MARGIN_MENU_ITEMS=(
    "Margin Top:"
    "Margin Bottom:"
    "Margin Left:"
    "Margin Right:"
    "Reset Margins"
    "Back"
)
declare -ri MARGIN_MENU_COUNT=${#MARGIN_MENU_ITEMS[@]}

# Icons mapped to each menu item
declare -ra MENU_ICONS=(
    "↔"
    "↕"
    "↻"
    "✕"
)

# Icons for margins menu
declare -ra MARGIN_MENU_ICONS=(
    "▲"
    "▼"
    "◀"
    "▶"
    "↺"
    "←"
)

# --- System Helpers ---

log_err() {
    printf '%s[ERROR]%s %s\n' "$C_RED" "$C_RESET" "$1" >&2
}

cli_die() {
    if ((TUI_RUNNING)); then
        set_status "ERROR" "$1" "red"
    else
        printf '%s[ERROR]%s %s\n' "${C_RED}" "$C_RESET" "$1" >&2
        exit 1
    fi
}
cli_info() { printf '%s[INFO]%s %s\n' "${C_CYAN}" "$C_RESET" "$1"; }
cli_warn() { printf '%s[WARN]%s %s\n' "${C_YELLOW}" "$C_RESET" "$1" >&2; }
cli_success() { printf '%s[SUCCESS]%s %s\n' "${C_GREEN}" "$C_RESET" "$1"; }

cleanup() {
    printf '%s%s%s' "$MOUSE_OFF" "$CURSOR_SHOW" "$C_RESET" 2>/dev/null || :
    if [[ -n "${ORIGINAL_STTY:-}" ]]; then
        stty "$ORIGINAL_STTY" 2>/dev/null || :
    fi
    if [[ -n "${_TMPFILE:-}" && -f "$_TMPFILE" ]]; then
        rm -f "$_TMPFILE" 2>/dev/null || :
    fi
    printf '\n' 2>/dev/null || :
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# --- String Helpers ---

strip_ansi() {
    local v="$1"
    v="${v//$'\033'\[*([0-9;:?<=>])@([@A-Z\[\\\]^_\`a-z\{|\}~])/}"
    REPLY="$v"
}

# --- Pre-flight Checks ---

check_dependencies() {
    command -v jq &>/dev/null || cli_die "'jq' is not installed"

    [[ -f "$SWAYNC_CONFIG" ]] || cli_die "SwayNC config not found: $SWAYNC_CONFIG"
    [[ -r "$SWAYNC_CONFIG" ]] || cli_die "SwayNC config not readable: $SWAYNC_CONFIG"
    [[ -w "$SWAYNC_CONFIG" ]] || cli_die "SwayNC config not writable: $SWAYNC_CONFIG"

    [[ -f "$HYPR_RULES" ]] || cli_die "Hyprland rules not found: $HYPR_RULES"
    [[ -r "$HYPR_RULES" ]] || cli_die "Hyprland rules not readable: $HYPR_RULES"
    [[ -w "$HYPR_RULES" ]] || cli_die "Hyprland rules not writable: $HYPR_RULES"
}

# --- Safe File Operations ---

atomic_jq_update() {
    local config_file="$1"
    shift
    
    if [[ -z "${_TMPFILE:-}" ]]; then
        _TMPFILE=$(mktemp "${config_file}.tmp.XXXXXXXXXX")
    fi

    if ! jq "$@" "$config_file" > "$_TMPFILE" 2>/dev/null; then
        rm -f "$_TMPFILE" 2>/dev/null || :
        _TMPFILE=""
        return 1
    fi

    # Protect against 0-byte file truncation on failure
    if [[ ! -s "$_TMPFILE" ]]; then
        rm -f "$_TMPFILE" 2>/dev/null || :
        _TMPFILE=""
        return 1
    fi

    cat "$_TMPFILE" > "$config_file"
    rm -f "$_TMPFILE"
    _TMPFILE=""
    return 0
}

# --- Core Logic ---

get_current_position() {
    local pos
    pos=$(jq -re '.positionX // empty' "$SWAYNC_CONFIG" 2>/dev/null) || {
        if ((TUI_RUNNING)); then
            set_status "ERROR" "Failed to read positionX from config" "red"
            CURRENT_POSITION_X="unknown"
            return 1
        else
            cli_die "Failed to read 'positionX' from $SWAYNC_CONFIG"
        fi
    }
    CURRENT_POSITION_X="$pos"

    pos=$(jq -re '.positionY // empty' "$SWAYNC_CONFIG" 2>/dev/null) || {
        if ((TUI_RUNNING)); then
            set_status "ERROR" "Failed to read positionY from config" "red"
            CURRENT_POSITION_Y="unknown"
            return 1
        else
            cli_die "Failed to read 'positionY' from $SWAYNC_CONFIG"
        fi
    }
    CURRENT_POSITION_Y="$pos"
}

read_margins() {
    MARGIN_TOP=$(jq -re '.["control-center-margin-top"] // 0' "$SWAYNC_CONFIG" 2>/dev/null) || MARGIN_TOP=0
    MARGIN_BOTTOM=$(jq -re '.["control-center-margin-bottom"] // 0' "$SWAYNC_CONFIG" 2>/dev/null) || MARGIN_BOTTOM=0
    MARGIN_LEFT=$(jq -re '.["control-center-margin-left"] // 0' "$SWAYNC_CONFIG" 2>/dev/null) || MARGIN_LEFT=0
    MARGIN_RIGHT=$(jq -re '.["control-center-margin-right"] // 0' "$SWAYNC_CONFIG" 2>/dev/null) || MARGIN_RIGHT=0
}

apply_margin_change() {
    local margin_key="$1"
    local -i delta=$2

    local margin_name
    case "$margin_key" in
        "control-center-margin-top") margin_name="top" ;;
        "control-center-margin-bottom") margin_name="bottom" ;;
        "control-center-margin-left") margin_name="left" ;;
        "control-center-margin-right") margin_name="right" ;;
        *) return 1 ;;
    esac

    local current_val
    current_val=$(jq -r '."'"$margin_key"'" // 0' "$SWAYNC_CONFIG" 2>/dev/null)

    local -i new_val=$((current_val + delta))
    if ((new_val < 0)); then new_val=0; fi

    if ! atomic_jq_update "$SWAYNC_CONFIG" --argjson val "$new_val" '."'"$margin_key"'" = $val'; then
        if ((TUI_RUNNING)); then set_status "ERROR" "Failed to update margin" "red"; fi
        return 1
    fi

    read_margins

    local new_val_display
    case "$margin_key" in
        "control-center-margin-top") new_val_display=$MARGIN_TOP ;;
        "control-center-margin-bottom") new_val_display=$MARGIN_BOTTOM ;;
        "control-center-margin-left") new_val_display=$MARGIN_LEFT ;;
        "control-center-margin-right") new_val_display=$MARGIN_RIGHT ;;
    esac

    if ((TUI_RUNNING)); then
        set_status "OK" "Margin ${margin_name}: ${new_val_display}" "green"
    fi

    reload_services "${margin_name}"
    return 0
}

reset_margins() {
    if atomic_jq_update "$SWAYNC_CONFIG" '. | ."control-center-margin-top" = 0 | ."control-center-margin-bottom" = 0 | ."control-center-margin-left" = 0 | ."control-center-margin-right" = 0'; then
        read_margins
        reload_services "margins"
        if ((TUI_RUNNING)); then set_status "OK" "Margins reset to default" "green"; fi
    else
        if ((TUI_RUNNING)); then set_status "ERROR" "Failed to reset margins" "red"; fi
    fi
}

reload_services() {
    local target_side="$1"
    local -a warnings=()

    if command -v swaync-client &>/dev/null; then
        swaync-client --reload-config &>/dev/null || warnings+=("SwayNC config reload failed")
        swaync-client --reload-css &>/dev/null || warnings+=("SwayNC CSS reload failed")
    else
        warnings+=("swaync-client not found")
    fi

    if command -v hyprctl &>/dev/null; then
        hyprctl reload &>/dev/null || warnings+=("Hyprland reload failed")
    else
        warnings+=("hyprctl not found")
    fi

    if ((${#warnings[@]} > 0)); then
        if ((TUI_RUNNING)); then
            set_status "WARN" "${warnings[0]}" "yellow"
        else
            local w
            for w in "${warnings[@]}"; do
                cli_warn "$w"
            done
        fi
    fi

    if ((!TUI_RUNNING)); then
        cli_success "Position updated to ${target_side^^}"
    fi
}

apply_changes() {
    local axis="${1:-}"
    local target_value="${2:-}"

    if [[ "$axis" == "x" ]]; then
        if [[ ! "$target_value" =~ ^(left|center|right)$ ]]; then
            if ((TUI_RUNNING)); then set_status "ERROR" "Invalid X position: '$target_value'" "red"; return 1
            else cli_die "Invalid X position: '$target_value'. Use 'left', 'center', or 'right'"; fi
        fi
    elif [[ "$axis" == "y" ]]; then
        if [[ ! "$target_value" =~ ^(top|bottom)$ ]]; then
            if ((TUI_RUNNING)); then set_status "ERROR" "Invalid Y position: '$target_value'" "red"; return 1
            else cli_die "Invalid Y position: '$target_value'. Use 'top' or 'bottom'"; fi
        fi
    else
        if ((TUI_RUNNING)); then set_status "ERROR" "Invalid axis: '$axis'" "red"; return 1
        else cli_die "Invalid axis: '$axis'. Use 'x' or 'y'"; fi
    fi

    get_current_position >/dev/null 2>&1 || return 1
    local current
    if [[ "$axis" == "x" ]]; then current="$CURRENT_POSITION_X"
    else current="$CURRENT_POSITION_Y"; fi
    
    if [[ "$current" == "$target_value" ]]; then
        if ((TUI_RUNNING)); then set_status "INFO" "Already set to ${target_value^}" "cyan"; return 0
        else cli_info "Already set to ${target_value^}"; return 0; fi
    fi

    if ((!TUI_RUNNING)); then cli_info "Switching to ${target_value^^}..."; fi

    # 1. Update SwayNC config
    local json_key="position${axis^^}"
    
    if ! atomic_jq_update "$SWAYNC_CONFIG" --arg val "$target_value" '."'"$json_key"'" = $val'; then
        if ((TUI_RUNNING)); then set_status "ERROR" "Failed to update SwayNC config" "red"; return 1
        else cli_die "Failed to update SwayNC config"; fi
    fi

    # 2. Verify the change
    local actual
    if [[ "$axis" == "x" ]]; then
        actual=$(jq -re '.positionX // empty' "$SWAYNC_CONFIG" 2>/dev/null) || actual=""
    else
        actual=$(jq -re '.positionY // empty' "$SWAYNC_CONFIG" 2>/dev/null) || actual=""
    fi
    if [[ "$actual" != "$target_value" ]]; then
        if ((TUI_RUNNING)); then set_status "ERROR" "Verification failed! Config did not update" "red"; return 1
        else cli_die "Verification failed! Config did not update."; fi
    fi

    # 3. Update Hyprland animation rules (Awk replaces risky sed substitution)
    get_current_position >/dev/null 2>&1 || true
    local final_x="${CURRENT_POSITION_X}"
    local final_y="${CURRENT_POSITION_Y}"
    [[ "$axis" == "x" ]] && final_x="$target_value" || true
    [[ "$axis" == "y" ]] && final_y="$target_value" || true

    if grep -q 'name = swaync_slide' "$HYPR_RULES" 2>/dev/null; then
        local anim_dir="$final_x"
        [[ "$final_y" == "top" ]] && anim_dir="$anim_dir in-t"
        [[ "$final_y" == "bottom" ]] && anim_dir="$anim_dir in-b"
        
        _TMPFILE=$(mktemp "${HYPR_RULES}.tmp.XXXXXXXXXX")
        awk -v new_anim="animation = slide $anim_dir" '
            /name = swaync_slide/ { in_block = 1 }
            in_block && /animation = slide .*/ {
                sub(/animation = slide .*/, new_anim)
            }
            /}/ && in_block { in_block = 0 }
            { print }
        ' "$HYPR_RULES" > "$_TMPFILE"

        if [[ -s "$_TMPFILE" ]]; then
            cat "$_TMPFILE" > "$HYPR_RULES"
        else
            if ((TUI_RUNNING)); then set_status "WARN" "Failed to update Hyprland rules" "yellow"
            else cli_warn "Failed to generate Hyprland rules update"; fi
        fi
        rm -f "$_TMPFILE" 2>/dev/null || :
        _TMPFILE=""
    else
        if ((TUI_RUNNING)); then set_status "WARN" "swaync_slide block not found in rules" "yellow"
        else cli_warn "Block 'swaync_slide' not found in $HYPR_RULES. Animation not updated."; fi
    fi

    # 4. Update cached state
    if [[ "$axis" == "x" ]]; then CURRENT_POSITION_X="$target_value"
    else CURRENT_POSITION_Y="$target_value"; fi

    # 5. Reload services
    reload_services "$target_value"

    if ((TUI_RUNNING)); then
        set_status "OK" "Position ${axis^^} set to ${target_value^}" "green"
    fi

    return 0
}

cycle_position() {
    local axis="$1"
    local -i dir=$2

    local -a options
    local current

    if [[ "$axis" == "x" ]]; then
        options=("${POS_X_OPTIONS[@]}")
        current="$CURRENT_POSITION_X"
    else
        options=("${POS_Y_OPTIONS[@]}")
        current="$CURRENT_POSITION_Y"
    fi

    local -i current_idx=-1
    local -i i
    for ((i = 0; i < ${#options[@]}; i++)); do
        if [[ "${options[i]}" == "$current" ]]; then
            current_idx=$i
            break
        fi
    done

    if ((current_idx == -1)); then current_idx=0; fi

    local -i new_idx=$(((current_idx + dir + ${#options[@]}) % ${#options[@]}))
    local new_value="${options[new_idx]}"

    apply_changes "$axis" "$new_value"
}

# --- TUI Status Management ---

set_status() {
    local level="$1" msg="$2" color="${3:-cyan}"
    case "$color" in
        red) STATUS_COLOR="$C_RED" ;;
        green) STATUS_COLOR="$C_GREEN" ;;
        yellow) STATUS_COLOR="$C_YELLOW" ;;
        cyan) STATUS_COLOR="$C_CYAN" ;;
        *) STATUS_COLOR="$C_WHITE" ;;
    esac
    STATUS_MSG="${level}: ${msg}"
    NEEDS_REDRAW=1
}

# --- TUI Rendering Engine ---

compute_scroll_window() {
    local -i count=$1
    if ((count == 0)); then
        SELECTED_ROW=0; SCROLL_OFFSET=0; _vis_start=0; _vis_end=0
        return
    fi

    if ((SELECTED_ROW < 0)); then SELECTED_ROW=0; fi
    if ((SELECTED_ROW >= count)); then SELECTED_ROW=$((count - 1)); fi

    if ((SELECTED_ROW < SCROLL_OFFSET)); then
        SCROLL_OFFSET=$SELECTED_ROW
    elif ((SELECTED_ROW >= SCROLL_OFFSET + MAX_DISPLAY_ROWS)); then
        SCROLL_OFFSET=$((SELECTED_ROW - MAX_DISPLAY_ROWS + 1))
    fi

    local -i max_scroll=$((count - MAX_DISPLAY_ROWS))
    if ((max_scroll < 0)); then max_scroll=0; fi
    if ((SCROLL_OFFSET > max_scroll)); then SCROLL_OFFSET=$max_scroll; fi

    _vis_start=$SCROLL_OFFSET
    _vis_end=$((SCROLL_OFFSET + MAX_DISPLAY_ROWS))
    if ((_vis_end > count)); then _vis_end=$count; fi
}

draw_ui() {
    local buf="" pad_buf=""
    local -i left_pad right_pad vis_len pad_needed
    local -i _vis_start _vis_end

    buf+="${CURSOR_HOME}"

    # ┌─ Top border ─┐
    buf+="${C_MAGENTA}┌${H_LINE}┐${C_RESET}${CLR_EOL}"$'\n'

    # │ Title + Version │
    strip_ansi "$APP_TITLE"; local -i t_len=${#REPLY}
    strip_ansi "$APP_VERSION"; local -i v_len=${#REPLY}
    vis_len=$((t_len + v_len + 1))
    left_pad=$(((BOX_INNER_WIDTH - vis_len) / 2))
    right_pad=$((BOX_INNER_WIDTH - vis_len - left_pad))

    printf -v pad_buf '%*s' "$left_pad" ''
    buf+="${C_MAGENTA}│${pad_buf}${C_WHITE}${APP_TITLE} ${C_CYAN}${APP_VERSION}${C_MAGENTA}"
    printf -v pad_buf '%*s' "$right_pad" ''
    buf+="${pad_buf}│${C_RESET}${CLR_EOL}"$'\n'

    # --- Scrollable Tab Rendering ---
    if (( TAB_SCROLL_START > CURRENT_TAB )); then TAB_SCROLL_START=$CURRENT_TAB; fi

    local tab_line
    local -i max_tab_width=$(( BOX_INNER_WIDTH - 6 ))
    
    LEFT_ARROW_ZONE=""
    RIGHT_ARROW_ZONE=""

    while true; do
        tab_line="${C_MAGENTA}│ "
        local -i current_col=3
        TAB_ZONES=()
        local -i used_len=0

        # Left Arrow
        if (( TAB_SCROLL_START > 0 )); then
            tab_line+="${C_YELLOW}«${C_RESET} "
            LEFT_ARROW_ZONE="$current_col:$((current_col+1))"
            used_len=$(( used_len + 2 ))
            current_col=$(( current_col + 2 ))
        else
            tab_line+="  "
            used_len=$(( used_len + 2 ))
            current_col=$(( current_col + 2 ))
        fi

        local -i i zone_start
        for (( i = TAB_SCROLL_START; i < TAB_COUNT; i++ )); do
            local name="${TABS[i]}"
            local t_len=${#name}
            local chunk_len=$(( t_len + 4 ))
            local reserve=0
            
            if (( i < TAB_COUNT - 1 )); then reserve=2; fi

            if (( used_len + chunk_len + reserve > max_tab_width )); then
                if (( i <= CURRENT_TAB )); then
                    TAB_SCROLL_START=$(( TAB_SCROLL_START + 1 ))
                    continue 2
                fi
                tab_line+="${C_YELLOW}» ${C_RESET}"
                RIGHT_ARROW_ZONE="$current_col:$((current_col+1))"
                used_len=$(( used_len + 2 ))
                break
            fi

            zone_start=$current_col
            if (( i == CURRENT_TAB )); then
                tab_line+="${C_CYAN}${C_INVERSE} ${name} ${C_RESET}${C_MAGENTA}│ "
            else
                tab_line+="${C_GREY} ${name} ${C_MAGENTA}│ "
            fi
            
            TAB_ZONES+=("${zone_start}:$(( zone_start + t_len + 1 ))")
            used_len=$(( used_len + chunk_len ))
            current_col=$(( current_col + chunk_len ))
        done

        local pad=$(( BOX_INNER_WIDTH - used_len - 1 ))
        if (( pad > 0 )); then
            printf -v pad_buf '%*s' "$pad" ''
            tab_line+="$pad_buf"
        fi
        
        tab_line+="${C_MAGENTA}│${C_RESET}"
        break
    done
    
    buf+="${tab_line}${CLR_EOL}"$'\n'
    # -----------------------------------------------------------------

    # │ Current info based on tab │
    # FIX: Precise padding logic mimicking Title block
    local line_content=""
    if ((CURRENT_TAB == 0)); then
        local pos_color_x pos_color_y
        case "$CURRENT_POSITION_X" in
            left) pos_color_x="$C_CYAN" ;;
            center) pos_color_x="$C_YELLOW" ;;
            right) pos_color_x="$C_GREEN" ;;
            *) pos_color_x="$C_RED" ;;
        esac
        case "$CURRENT_POSITION_Y" in
            top) pos_color_y="$C_MAGENTA" ;;
            bottom) pos_color_y="$C_BLUE" ;;
            *) pos_color_y="$C_RED" ;;
        esac
        # String exactly as it will appear inside the border
        line_content=" X:${pos_color_x}${CURRENT_POSITION_X^}${C_WHITE}  Y:${pos_color_y}${CURRENT_POSITION_Y^}${C_RESET}"
    else
        read_margins >/dev/null 2>&1 || true
        # String exactly as it will appear inside the border
        line_content=" T:${C_YELLOW}${MARGIN_TOP}${C_WHITE} B:${C_YELLOW}${MARGIN_BOTTOM}${C_WHITE} L:${C_YELLOW}${MARGIN_LEFT}${C_WHITE} R:${C
