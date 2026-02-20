#!/usr/bin/env python3
import sys
import os
import subprocess
import json
import tempfile
import re
from pathlib import Path
from typing import Optional, Tuple, List

# --- Immutable Configuration ---
CONFIG_DIR = Path.home() / ".config/hypr/edit_here/source"
CONFIG_FILE = CONFIG_DIR / "monitors.conf"
NOTIFY_TAG = "hypr_scale_adjust"
MIN_LOGICAL_WIDTH = 640
MIN_LOGICAL_HEIGHT = 360

# Standard Wayland fractional/integer scaling steps
SCALE_STEPS = [
    0.5, 0.6, 0.75, 0.8, 0.9, 1.0, 1.0625, 1.1, 1.125, 1.15, 1.2, 1.25,
    1.33, 1.4, 1.5, 1.6, 1.67, 1.75, 1.8, 1.88, 2.0, 2.25, 2.4, 2.5,
    2.67, 2.8, 3.0
]

def notify(title: str, body: str, urgency: str = "low"):
    """Dispatches a notification using the canonical synchronous tag."""
    subprocess.run([
        "notify-send", 
        "-h", f"string:x-canonical-private-synchronous:{NOTIFY_TAG}",
        "-u", urgency, 
        "-t", "2000", 
        title, 
        body
    ], stderr=subprocess.DEVNULL)

def get_active_monitor() -> Tuple[str, int, int, float]:
    """Retrieves the focused monitor's name, physical dimensions, and current scale."""
    try:
        res = subprocess.run(["hyprctl", "-j", "monitors"], capture_output=True, text=True, check=True)
        monitors = json.loads(res.stdout)
    except (subprocess.CalledProcessError, json.JSONDecodeError):
        sys.exit("ERROR: Cannot communicate with Hyprland IPC.")

    if not monitors:
        sys.exit("ERROR: No active monitors found.")

    # Prioritize focused monitor, fallback to the first available
    target = next((m for m in monitors if m.get("focused")), monitors[0])
    
    return target["name"], target["width"], target["height"], target["scale"]

def compute_next_scale(current: float, direction: str, phys_w: int, phys_h: int) -> Optional[float]:
    """Calculates the nearest mathematically valid scale without fractional pixel remainders."""
    valid_scales: List[float] = []

    for s in SCALE_STEPS:
        lw, lh = phys_w / s, phys_h / s
        
        # Reject if logical resolution is too small
        if lw < MIN_LOGICAL_WIDTH or lh < MIN_LOGICAL_HEIGHT:
            continue
            
        # STRICT MATH GUARD: A valid scale must divide both width and height cleanly without decimals
        if abs(lw - round(lw)) > 0.01 or abs(lh - round(lh)) > 0.01:
            continue
            
        valid_scales.append(s)

    if not valid_scales:
        valid_scales = [1.0]

    # Find the closest matching scale in our valid array
    closest_idx = min(range(len(valid_scales)), key=lambda i: abs(valid_scales[i] - current))

    # Determine target index
    target_idx = closest_idx + 1 if direction == "+" else closest_idx - 1
    target_idx = max(0, min(target_idx, len(valid_scales) - 1))

    new_scale = valid_scales[target_idx]
    
    # Return None if the limit is reached
    if abs(new_scale - current) < 0.000001:
        return None
        
    return new_scale

def update_config_atomically(monitor_name: str, new_scale: float):
    """Parses and updates the Hyprland config using strict POSIX atomic file replacement."""
    if not CONFIG_FILE.exists():
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        CONFIG_FILE.touch()

    # Resolve symlinks to target the actual physical file
    real_path = CONFIG_FILE.resolve()
    
    with open(real_path, "r") as f:
        lines = f.readlines()

    new_lines = []
    found = False
    in_v2_block = False
    current_v2_output = ""
    
    v1_regex = re.compile(r"^(\s*monitor\s*=\s*)([^,]+)(,.*)$")

    for line in lines:
        # --- Handle V2 Syntax ---
        if "monitorv2 {" in line:
            in_v2_block = True
            new_lines.append(line)
            continue
            
        if in_v2_block:
            if "output =" in line:
                current_v2_output = line.split("=")[1].strip()
            if "}" in line:
                in_v2_block = False
                current_v2_output = ""
                
            if current_v2_output == monitor_name and "scale =" in line:
                new_lines.append(f"    scale = {new_scale:g}\n")
                found = True
                continue
                
        # --- Handle V1 Syntax ---
        else:
            match = v1_regex.match(line)
            if match:
                prefix, mon, remainder = match.groups()
                if mon.strip() == monitor_name:
                    parts = remainder.split(",")
                    # Parts: [0]="", [1]=res, [2]=pos, [3]=scale, [4+]=extra
                    if len(parts) >= 4:
                        parts[3] = f" {new_scale:g}"
                        new_lines.append(f"{prefix}{mon}{','.join(parts)}\n")
                        found = True
                        continue

        new_lines.append(line)

    if not found:
        new_lines.append(f"monitor = {monitor_name}, preferred, auto, {new_scale:g}\n")

    # Atomic Write: Create temp file in the SAME directory as the resolved target
    fd, temp_path = tempfile.mkstemp(dir=real_path.parent, prefix=".monitors.conf.tmp.")
    try:
        with os.fdopen(fd, 'w') as temp_file:
            temp_file.writelines(new_lines)
            
        # Duplicate file stats (permissions)
        os.chmod(temp_path, real_path.stat().st_mode)
        
        # Atomic POSIX replacement
        os.replace(temp_path, real_path)
    except Exception as e:
        os.remove(temp_path)
        sys.exit(f"ERROR: Atomic write failed: {e}")

def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("+", "-"):
        sys.exit(f"Usage: {sys.argv[0]} [+|-]")

    direction = sys.argv[1]
    
    mon_name, phys_w, phys_h, current_scale = get_active_monitor()
    
    new_scale = compute_next_scale(current_scale, direction, phys_w, phys_h)
    
    if new_scale is None:
        notify("Monitor Scale", f"Limit Reached: {current_scale:g}", "normal")
        return

    # 1. Atomically update the configuration file
    update_config_atomically(mon_name, new_scale)
    
    # 2. Reload Hyprland to apply state (preserves advanced args natively)
    subprocess.run(["hyprctl", "reload"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    
    logic_w = int(phys_w / new_scale)
    logic_h = int(phys_h / new_scale)
    
    notify(f"Display Scale: {new_scale:g}", f"Monitor: {mon_name}\nLogical: {logic_w}x{logic_h}")

if __name__ == "__main__":
    main()
