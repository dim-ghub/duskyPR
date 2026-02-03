"""Utility functions for the Dusky Control Center."""
from __future__ import annotations

import os
import shlex
import subprocess
import sys
from pathlib import Path
from typing import Any, Optional

import yaml

# =============================================================================
# CONSTANTS & PATHS
# =============================================================================
XDG_CACHE_HOME = os.environ.get(
    "XDG_CACHE_HOME", os.path.join(os.path.expanduser("~"), ".cache")
)
CACHE_DIR = os.path.join(XDG_CACHE_HOME, "duskycc")
KEY_LOCATION = os.path.join(os.path.expanduser("~"), ".config", "dusky", "settings")

_SYSTEM_INFO_CACHE: dict[str, str] = {}


def get_cache_dir() -> Path:
    """Get or create the cache directory."""
    path = Path(CACHE_DIR)
    path.mkdir(parents=True, exist_ok=True)
    return path


# =============================================================================
# CONFIGURATION LOADER
# =============================================================================
def load_config(config_path: Path) -> dict[str, Any]:
    """Load and parse a YAML configuration file."""
    if not config_path.is_file():
        print(f"[INFO] Config not found: {config_path}")
        return {}
    try:
        with open(config_path, "r", encoding="utf-8") as f:
            data = yaml.safe_load(f)
            if not isinstance(data, dict):
                return {}
            return data
    except yaml.YAMLError as e:
        print(f"[ERROR] YAML parse error: {e}")
        return {}
    except OSError as e:
        print(f"[ERROR] Config read error: {e}")
        return {}


# =============================================================================
# UWSM-COMPLIANT COMMAND RUNNER
# =============================================================================
# Characters that likely require shell interpretation
_SHELL_METACHARACTERS = frozenset("|&;><$`\\\"'*?[](){}!")


def execute_command(cmd_string: str, title: str, run_in_terminal: bool) -> bool:
    """Execute a command via uwsm-app, optionally in a terminal."""
    expanded_cmd = os.path.expanduser(os.path.expandvars(cmd_string)).strip()
    if not expanded_cmd:
        return False

    try:
        if run_in_terminal:
            full_cmd = [
                "uwsm-app",
                "--",
                "kitty",
                "--class",
                "dusky-term",
                "--title",
                title,
                "--hold",
                "sh",
                "-c",
                expanded_cmd,
            ]
        else:
            # Check for ANY shell char. If present, force shell mode.
            needs_shell = any(char in expanded_cmd for char in _SHELL_METACHARACTERS)

            if needs_shell:
                full_cmd = ["uwsm-app", "--", "sh", "-c", expanded_cmd]
            else:
                try:
                    parsed_args = shlex.split(expanded_cmd)
                    full_cmd = ["uwsm-app", "--"] + parsed_args
                except ValueError:
                    # Fallback if shlex fails on edge cases
                    full_cmd = ["uwsm-app", "--", "sh", "-c", expanded_cmd]

        subprocess.Popen(
            full_cmd,
            start_new_session=True,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            close_fds=True,
        )
        return True
    except FileNotFoundError:
        print("[ERROR] uwsm-app not found in PATH")
        return False
    except Exception as e:
        print(f"[ERROR] Execute failed: {e}")
        return False


# =============================================================================
# PRE-FLIGHT DEPENDENCY CHECK
# =============================================================================
def preflight_check() -> None:
    """Verify all required dependencies are installed before startup."""
    missing: list[str] = []

    try:
        import yaml  # noqa: F401
    except ImportError:
        missing.append("python-yaml")

    try:
        import gi

        gi.require_version("Gtk", "4.0")
        gi.require_version("Adw", "1")
        from gi.repository import Adw, Gtk  # noqa: F401
    except ImportError:
        missing.append("python-gobject")
    except ValueError as e:
        # Check if the error explicitly mentions which package is missing
        error_msg = str(e).lower()
        if "gtk" in error_msg:
            missing.append("gtk4")
        if "adw" in error_msg:
            missing.append("libadwaita")
        # If neither is mentioned but we got a ValueError, safe fallback
        if not missing:
            missing.append("python-gobject")

    if missing:
        unique = list(dict.fromkeys(missing))
        print(f"\n[FATAL] Missing dependencies: {', '.join(unique)}")
        print("Install with: sudo pacman -S " + " ".join(unique) + "\n")
        sys.exit(1)

    # Ensure settings directory exists
    try:
        os.makedirs(KEY_LOCATION, exist_ok=True)
    except OSError:
        pass


# =============================================================================
# SYSTEM VALUE RETRIEVAL (CACHED)
# =============================================================================
def get_system_value(key: str) -> str:
    """Retrieve system information with caching for static values."""
    # Return cached values for known-static keys
    if key in _SYSTEM_INFO_CACHE:
        return _SYSTEM_INFO_CACHE[key]

    result = "N/A"
    try:
        if key == "memory_total":
            with open("/proc/meminfo", "r") as f:
                for line in f:
                    if line.startswith("MemTotal:"):
                        kb = int(line.split()[1])
                        gb = round(kb / 1024 / 1024, 1)
                        result = f"{gb} GB"
                        break
            _SYSTEM_INFO_CACHE[key] = result

        elif key == "cpu_model":
            with open("/proc/cpuinfo", "r") as f:
                for line in f:
                    if line.startswith("model name"):
                        raw = line.split(":", 1)[1].strip()
                        result = raw.split("@")[0].strip()
                        break
            _SYSTEM_INFO_CACHE[key] = result

        elif key == "gpu_model":
            try:
                lspci_output = subprocess.check_output(
                    ["lspci"], text=True, stderr=subprocess.DEVNULL, timeout=5
                )
                for line in lspci_output.splitlines():
                    if "VGA compatible controller" in line or "3D controller" in line:
                        parts = line.split(":", 2)
                        if len(parts) > 2:
                            result = parts[2].strip()
                        break
            except (subprocess.TimeoutExpired, FileNotFoundError, subprocess.CalledProcessError):
                pass
            _SYSTEM_INFO_CACHE[key] = result

        elif key == "kernel_version":
            result = os.uname().release
            _SYSTEM_INFO_CACHE[key] = result

    except Exception as e:
        print(f"[WARN] Failed to get system value '{key}': {e}")

    return result


# =============================================================================
# SETTINGS PERSISTENCE
# =============================================================================
def _validate_key_path(key: str) -> Optional[str]:
    """Validate and return the safe path for a settings key, or None if invalid."""
    if not key:
        return None

    key_path = os.path.join(KEY_LOCATION, key)
    abs_key_path = os.path.abspath(os.path.normpath(key_path))
    abs_key_location = os.path.abspath(os.path.normpath(KEY_LOCATION))

    # Prevent path traversal attacks
    if not abs_key_path.startswith(abs_key_location + os.sep):
        print(f"[WARN] Path traversal attempt blocked: {key}")
        return None
    return abs_key_path


def save_setting(key: str, value: Any, as_int: bool = False) -> None:
    """Save a setting value to a file."""
    key_path = _validate_key_path(key)
    if key_path is None:
        return

    try:
        os.makedirs(os.path.dirname(key_path), exist_ok=True)
        with open(key_path, "w", encoding="utf-8") as f:
            if as_int and isinstance(value, bool):
                f.write(str(int(value)))
            else:
                f.write(str(value))
    except OSError as e:
        print(f"[WARN] Failed to save setting '{key}': {e}")


def load_setting(
    key: str, default: Any = None, is_inversed: bool = False
) -> Any:
    """Load a setting value from a file."""
    key_path = _validate_key_path(key)
    if key_path is None:
        return default

    if not os.path.isfile(key_path):
        return default

    try:
        with open(key_path, "r", encoding="utf-8") as f:
            value = f.read().strip()

            if isinstance(default, bool):
                try:
                    # Handle "1"/"0"
                    bool_val = int(value) != 0
                except ValueError:
                    # Handle "true"/"false" case insensitive
                    bool_val = value.lower() == "true"
                return bool_val ^ is_inversed

            if isinstance(default, int):
                return int(value)

            if isinstance(default, float):
                return float(value)

            return value
    except (OSError, ValueError) as e:
        print(f"[WARN] Failed to load setting '{key}': {e}")
        return default


# =============================================================================
# UI HELPERS
# =============================================================================
def toast(toast_overlay: Any, message: str, timeout: int = 2) -> None:
    """Display a toast notification if the overlay is available."""
    if toast_overlay is None:
        return
    
    # Import locally to avoid circular imports
    from gi.repository import Adw

    toast_obj = Adw.Toast(title=message, timeout=timeout)
    toast_overlay.add_toast(toast_obj)
