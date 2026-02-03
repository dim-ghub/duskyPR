"""
Row widget definitions for the Dusky Control Center.
Optimized for stability (Thread Guards) and efficiency (Redraw Minimization).
"""
from __future__ import annotations

import os
import subprocess
import threading
from pathlib import Path
from typing import Any, Optional

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, GLib, Gtk, Pango

import lib.utility as utility

def _is_dynamic_icon(icon_config: Any) -> bool:
    """Check if an icon config specifies a dynamic (exec) icon."""
    return (
        isinstance(icon_config, dict)
        and icon_config.get("type") == "exec"
        and "interval" in icon_config
    )

class BaseActionRow(Adw.ActionRow):
    """Base class with automatic cleanup for intervals and thread safety."""

    def __init__(
        self,
        properties: dict[str, Any],
        on_action: Optional[dict[str, Any]] = None,
        context: Optional[dict[str, Any]] = None,
    ) -> None:
        super().__init__()
        self.add_css_class("action-row")

        self.properties = properties
        self.on_action = on_action if on_action is not None else {}
        context = context if context is not None else {}

        self.stack = context.get("stack")
        self.content_title_label = context.get("content_title_label")
        self.config = context.get("config", {})
        self.sidebar = context.get("sidebar")
        self.toast_overlay = context.get("toast_overlay")

        self.update_source_id: Optional[int] = None
        self.icon_source_id: Optional[int] = None
        self._is_destroyed = False
        self._destroy_lock = threading.Lock()
        
        # GUARD: Prevent thread pile-up if scripts take longer than interval
        self._is_icon_updating = False 

        title = str(properties.get("title", "Unnamed"))
        subtitle = str(properties.get("description", ""))
        self.set_title(GLib.markup_escape_text(title))
        if subtitle:
            self.set_subtitle(GLib.markup_escape_text(subtitle))

        icon_config = properties.get("icon", "utilities-terminal-symbolic")
        self.icon_widget = self._create_icon_widget(icon_config)
        self.add_prefix(self.icon_widget)

        self.connect("destroy", self._on_destroy)

        if _is_dynamic_icon(icon_config):
            self._start_icon_update_loop(icon_config)

    def _create_icon_widget(self, icon: Any) -> Gtk.Image:
        icon_name = "utilities-terminal-symbolic"
        if isinstance(icon, dict):
            if icon.get("type") == "file":
                path = os.path.expanduser(str(icon.get("path", "")).strip())
                img = Gtk.Image.new_from_file(path)
                img.add_css_class("action-row-prefix-icon")
                return img
            icon_name = str(icon.get("name", icon_name))
        elif isinstance(icon, str):
            icon_name = icon

        img = Gtk.Image.new_from_icon_name(icon_name)
        img.add_css_class("action-row-prefix-icon")
        return img

    def _start_icon_update_loop(self, icon_config: dict[str, Any]) -> None:
        try:
            interval = int(icon_config.get("interval", 5))
        except (ValueError, TypeError):
            interval = 5

        if interval > 0:
            cmd = str(icon_config.get("command", ""))
            self.icon_source_id = GLib.timeout_add_seconds(
                interval, self._update_icon, cmd
            )

    def _update_icon(self, command: str) -> bool:
        # GUARD CHECK
        if self._is_icon_updating:
            return GLib.SOURCE_CONTINUE

        with self._destroy_lock:
            if self._is_destroyed:
                return GLib.SOURCE_REMOVE
        
        # SET LOCK
        self._is_icon_updating = True
        
        thread = threading.Thread(
            target=self._fetch_icon_wrapper, args=(command,), daemon=True
        )
        thread.start()
        return GLib.SOURCE_CONTINUE

    def _fetch_icon_wrapper(self, command: str) -> None:
        """Wrapper to ensure the busy flag is reset even if the command fails."""
        try:
            with self._destroy_lock:
                if self._is_destroyed:
                    return
            
            res = subprocess.run(
                command, shell=True, capture_output=True, text=True, timeout=2
            )
            new_icon = res.stdout.strip()
            if new_icon:
                GLib.idle_add(self._apply_icon_update, new_icon)
        except Exception:
            pass 
        finally:
            # RELEASE LOCK
            self._is_icon_updating = False

    def _apply_icon_update(self, new_icon: str) -> bool:
        with self._destroy_lock:
            if self._is_destroyed:
                return GLib.SOURCE_REMOVE
        
        # OPTIMIZATION: Only redraw if the icon name actually changed
        if self.icon_widget and self.icon_widget.get_icon_name() != new_icon:
            self.icon_widget.set_from_icon_name(new_icon)
            
        return GLib.SOURCE_REMOVE

    def _on_destroy(self, widget: Gtk.Widget) -> None:
        with self._destroy_lock:
            self._is_destroyed = True
        if self.update_source_id is not None:
            GLib.source_remove(self.update_source_id)
            self.update_source_id = None
        if self.icon_source_id is not None:
            GLib.source_remove(self.icon_source_id)
            self.icon_source_id = None


class ButtonRow(BaseActionRow):
    def __init__(
        self,
        properties: dict[str, Any],
        on_press: Optional[dict[str, Any]] = None,
        context: Optional[dict[str, Any]] = None,
    ) -> None:
        super().__init__(properties, on_press, context)

        style = str(properties.get("style", "default")).lower()
        run_btn = Gtk.Button(label="Run")
        run_btn.add_css_class("run-btn")
        run_btn.set_valign(Gtk.Align.CENTER)

        if style == "destructive":
            run_btn.add_css_class("destructive-action")
        elif style == "suggested":
            run_btn.add_css_class("suggested-action")
        else:
            run_btn.add_css_class("default-action")

        run_btn.connect("clicked", self._on_button_clicked)
        self.add_suffix(run_btn)
        self.set_activatable_widget(run_btn)

    def _on_button_clicked(self, button: Gtk.Button) -> None:
        action_type = self.on_action.get("type")
        if action_type == "exec":
            command = str(self.on_action.get("command", "")).strip()
            title = str(self.properties.get("title", "Command"))
            if not command: return
            
            success = utility.execute_command(
                command, title, bool(self.on_action.get("terminal", False))
            )
            if success:
                utility.toast(self.toast_overlay, f"▶ Launched: {title}")
            else:
                utility.toast(self.toast_overlay, f"✖ Failed: {title}", timeout=4)

        elif action_type == "redirect":
            page_id = self.on_action.get("page")
            if page_id and self.stack and self.sidebar:
                pages = self.config.get("pages", [])
                for idx, page in enumerate(pages):
                    if isinstance(page, dict) and page.get("id") == page_id:
                        row = self.sidebar.get_row_at_index(idx)
                        if row:
                            self.sidebar.select_row(row)
                        if self.content_title_label:
                            self.content_title_label.set_label(str(page.get("title", "")))
                        break

class ToggleRow(BaseActionRow):
    def __init__(
        self,
        properties: dict[str, Any],
        on_toggle: Optional[dict[str, Any]] = None,
        context: Optional[dict[str, Any]] = None,
    ) -> None:
        super().__init__(properties, on_toggle, context)

        self.save_as_int = bool(properties.get("save_as_int", False))
        self.key_inverse = bool(properties.get("key_inverse", False))
        self._programmatic_update = False
        self.monitor_source_id: Optional[int] = None
        
        # GUARD: Prevent thread pile-up for state monitoring
        self._is_monitoring = False
        
        self.toggle_switch = Gtk.Switch()
        self.toggle_switch.set_valign(Gtk.Align.CENTER)

        if "key" in properties:
            key = str(properties.get("key", "")).strip()
            system_value = utility.load_setting(key, False, self.key_inverse)
            if isinstance(system_value, bool):
                self.toggle_switch.set_active(system_value)

        self.toggle_switch.connect("state-set", self._on_toggle_changed)
        self.add_suffix(self.toggle_switch)
        self.set_activatable_widget(self.toggle_switch)

        try:
            monitor_interval = int(properties.get("interval", 2))
        except (ValueError, TypeError):
            monitor_interval = 2

        if "key" in properties and monitor_interval > 0:
            self.monitor_source_id = GLib.timeout_add_seconds(
                monitor_interval, self._monitor_state
            )

    def _monitor_state(self) -> bool:
        # GUARD CHECK
        if self._is_monitoring:
            return GLib.SOURCE_CONTINUE
            
        with self._destroy_lock:
            if self._is_destroyed:
                return GLib.SOURCE_REMOVE

        # SET LOCK
        self._is_monitoring = True

        thread = threading.Thread(
            target=self._async_check_state_wrapper, daemon=True
        )
        thread.start()
        return GLib.SOURCE_CONTINUE

    def _async_check_state_wrapper(self) -> None:
        try:
            with self._destroy_lock:
                if self._is_destroyed: return
            
            key = str(self.properties.get("key", "")).strip()
            current_file_state = utility.load_setting(key, False, self.key_inverse)

            if isinstance(current_file_state, bool):
                GLib.idle_add(self._apply_monitor_state, current_file_state)
        finally:
            # RELEASE LOCK
            self._is_monitoring = False

    def _apply_monitor_state(self, current_file_state: bool) -> bool:
        with self._destroy_lock:
            if self._is_destroyed:
                return GLib.SOURCE_REMOVE
        
        # OPTIMIZATION: Only change state if different
        if current_file_state != self.toggle_switch.get_active():
            self._programmatic_update = True
            self.toggle_switch.set_active(current_file_state)
            self._programmatic_update = False
            
        return GLib.SOURCE_REMOVE

    def _on_destroy(self, widget: Gtk.Widget) -> None:
        super()._on_destroy(widget)
        if self.monitor_source_id is not None:
            GLib.source_remove(self.monitor_source_id)
            self.monitor_source_id = None

    def _on_toggle_changed(self, switch: Gtk.Switch, state: bool) -> bool:
        if self._programmatic_update:
            return False

        action = self.on_action.get("enabled" if state else "disabled", {})
        cmd = str(action.get("command", "")).strip()
        if cmd:
            utility.execute_command(cmd, "Toggle", bool(action.get("terminal", False)))

        if "key" in self.properties:
            utility.save_setting(
                str(self.properties.get("key", "")),
                state ^ self.key_inverse,
                self.save_as_int,
            )
        return False


class LabelRow(BaseActionRow):
    def __init__(
        self,
        properties: dict[str, Any],
        value: Optional[dict[str, Any]] = None,
        context: Optional[dict[str, Any]] = None,
    ) -> None:
        super().__init__(properties, None, context)

        self.value_config = value if value is not None else {}
        self.value_label = Gtk.Label(label="...")
        self.value_label.add_css_class("dim-label")
        self.value_label.set_valign(Gtk.Align.CENTER)
        self.value_label.set_halign(Gtk.Align.END)
        self.value_label.set_hexpand(True)
        self.value_label.set_ellipsize(Pango.EllipsizeMode.END)
        self.add_suffix(self.value_label)

        # GUARD: Prevent thread pile-up for value updates
        self._is_val_updating = False

        self._trigger_update()

        try:
            interval = int(properties.get("interval", 0))
        except (ValueError, TypeError):
            interval = 0

        if interval > 0:
            self.update_source_id = GLib.timeout_add_seconds(
                interval, self._on_timeout
            )

    def _on_timeout(self) -> bool:
        with self._destroy_lock:
            if self._is_destroyed:
                return GLib.SOURCE_REMOVE
        self._trigger_update()
        return GLib.SOURCE_CONTINUE

    def _trigger_update(self) -> None:
        # GUARD CHECK
        if self._is_val_updating:
            return
            
        # SET LOCK
        self._is_val_updating = True
        
        thread = threading.Thread(
            target=self._load_value_wrapper, daemon=True
        )
        thread.start()

    def _load_value_wrapper(self) -> None:
        try:
            with self._destroy_lock:
                if self._is_destroyed:
                    return
            result_text = self._get_value_text(self.value_config)
            GLib.idle_add(self._update_label, result_text)
        finally:
            # RELEASE LOCK
            self._is_val_updating = False

    def _update_label(self, text: str) -> bool:
        with self._destroy_lock:
            if self._is_destroyed:
                return GLib.SOURCE_REMOVE
        
        # OPTIMIZATION: Only redraw if text changed
        if self.value_label.get_label() != text:
            self.value_label.set_label(text)
            self.value_label.remove_css_class("dim-label")
            
        return GLib.SOURCE_REMOVE

    def _get_value_text(self, value: Any) -> str:
        if isinstance(value, str):
            return value
        if not isinstance(value, dict):
            return "N/A"

        value_type = value.get("type")

        if value_type == "exec":
            command = str(value.get("command", "")).strip()

            # Optimization: use native Python I/O for simple `cat` commands
            if command.startswith("cat "):
                try:
                    target_file = os.path.expanduser(command[4:].strip())
                    with open(target_file, "r", encoding="utf-8") as f:
                        return f.read().strip()
                except OSError:
                    pass  # Fall through to subprocess

            if command:
                try:
                    res = subprocess.run(
                        command, shell=True, capture_output=True, text=True, timeout=5
                    )
                    return res.stdout.strip() or "N/A"
                except subprocess.TimeoutExpired:
                    return "Timeout"
                except Exception:
                    return "Error"

        elif value_type == "static":
            return str(value.get("text", "N/A"))

        elif value_type == "file":
            path = os.path.expanduser(str(value.get("path", "")))
            try:
                with open(path, "r", encoding="utf-8") as f:
                    return f.read().strip()
            except OSError:
                return "N/A"

        elif value_type == "system":
            return utility.get_system_value(str(value.get("key", ""))) or "N/A"

        return "N/A"


class SliderRow(BaseActionRow):
    def __init__(
        self,
        properties: dict[str, Any],
        on_change: Optional[dict[str, Any]] = None,
        context: Optional[dict[str, Any]] = None,
    ) -> None:
        super().__init__(properties, on_change, context)

        self.min_value = float(properties.get("min", 0))
        self.max_value = float(properties.get("max", 100))
        self.step_value = float(properties.get("step", 1))
        self.slider_changing = False
        self.last_snapped_value: Optional[float] = None

        adjustment = Gtk.Adjustment(
            value=float(properties.get("default", 0)),
            lower=self.min_value,
            upper=self.max_value,
            step_increment=self.step_value,
            page_increment=self.step_value * 10,
            page_size=0,
        )

        self.slider = Gtk.Scale(
            orientation=Gtk.Orientation.HORIZONTAL, adjustment=adjustment
        )
        self.slider.set_valign(Gtk.Align.CENTER)
        self.slider.set_hexpand(True)
        self.slider.set_draw_value(False)
        self.slider.connect("value-changed", self._on_slider_changed)
        self.add_suffix(self.slider)

    def _on_slider_changed(self, slider: Gtk.Scale) -> None:
        if self.slider_changing:
            return

        val = slider.get_value()
        snapped = round(val / self.step_value) * self.step_value
        snapped = max(self.min_value, min(snapped, self.max_value))

        if (
            self.last_snapped_value is not None
            and abs(snapped - self.last_snapped_value) < 1e-6
        ):
            return

        self.last_snapped_value = snapped

        if abs(snapped - val) > 1e-6:
            self.slider_changing = True
            self.slider.set_value(float(snapped))
            self.slider_changing = False

        action_type = self.on_action.get("type", "")
        if action_type == "exec":
            cmd = str(self.on_action.get("command", "")).strip()
            if cmd:
                # Optimized conversion
                final_cmd = cmd.replace("{value}", str(int(snapped)))
                utility.execute_command(
                    final_cmd, "Slider", bool(self.on_action.get("terminal", False))
                )

class GridCard(Gtk.Button):
    def __init__(
        self,
        properties: dict[str, Any],
        on_press: Optional[dict[str, Any]] = None,
        context: Optional[dict[str, Any]] = None,
    ) -> None:
        super().__init__()
        self.add_css_class("hero-card")

        self.properties = properties
        self.on_action = on_press if on_press is not None else {}
        self.context = context if context is not None else {}
        self.toast_overlay = self.context.get("toast_overlay")

        self.icon_source_id: Optional[int] = None
        self._is_destroyed = False
        self._destroy_lock = threading.Lock()
        
        # GUARD
        self._is_icon_updating = False

        style = str(properties.get("style", "default")).lower()
        if style == "destructive":
            self.add_css_class("destructive-card")
        elif style == "suggested":
            self.add_css_class("suggested-card")

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.set_valign(Gtk.Align.CENTER)
        box.set_halign(Gtk.Align.CENTER)

        icon_config = properties.get("icon", "utilities-terminal-symbolic")
        self.icon_widget = Gtk.Image.new_from_icon_name(
            self._get_initial_icon_name(icon_config)
        )
        self.icon_widget.set_pixel_size(42)
        self.icon_widget.add_css_class("hero-icon")

        title = Gtk.Label(label=str(properties.get("title", "Unnamed")))
        title.add_css_class("hero-title")
        title.set_wrap(True)
        title.set_justify(Gtk.Justification.CENTER)
        title.set_max_width_chars(16)

        box.append(self.icon_widget)
        box.append(title)
        self.set_child(box)

        self.connect("clicked", self._on_clicked)
        self.connect("destroy", self._on_destroy)

        if _is_dynamic_icon(icon_config):
            self._start_icon_update_loop(icon_config)

    def _get_initial_icon_name(self, icon: Any) -> str:
        if isinstance(icon, dict):
            return str(icon.get("name", "utilities-terminal-symbolic"))
        return str(icon)

    def _start_icon_update_loop(self, icon_config: dict[str, Any]) -> None:
        try:
            interval = int(icon_config.get("interval", 5))
        except (ValueError, TypeError):
            interval = 5

        if interval > 0:
            cmd = str(icon_config.get("command", ""))
            self.icon_source_id = GLib.timeout_add_seconds(
                interval, self._update_icon, cmd
            )

    def _update_icon(self, command: str) -> bool:
        # GUARD CHECK
        if self._is_icon_updating:
            return GLib.SOURCE_CONTINUE

        with self._destroy_lock:
            if self._is_destroyed:
                return GLib.SOURCE_REMOVE

        # SET LOCK
        self._is_icon_updating = True

        thread = threading.Thread(
            target=self._fetch_icon_wrapper, args=(command,), daemon=True
        )
        thread.start()
        return GLib.SOURCE_CONTINUE

    def _fetch_icon_wrapper(self, command: str) -> None:
        try:
            with self._destroy_lock:
                if self._is_destroyed: return
            
            res = subprocess.run(
                command, shell=True, capture_output=True, text=True, timeout=2
            )
            new_icon = res.stdout.strip()
            if new_icon:
                GLib.idle_add(self._apply_icon_update, new_icon)
        except Exception:
            pass
        finally:
            # RELEASE LOCK
            self._is_icon_updating = False

    def _apply_icon_update(self, new_icon: str) -> bool:
        with self._destroy_lock:
            if self._is_destroyed:
                return GLib.SOURCE_REMOVE
        
        # OPTIMIZATION: Check for change
        if self.icon_widget and self.icon_widget.get_icon_name() != new_icon:
            self.icon_widget.set_from_icon_name(new_icon)
            
        return GLib.SOURCE_REMOVE

    def _on_destroy(self, widget: Gtk.Widget) -> None:
        with self._destroy_lock:
            self._is_destroyed = True
        if self.icon_source_id is not None:
            GLib.source_remove(self.icon_source_id)
            self.icon_source_id = None

    def _on_clicked(self, button: Gtk.Button) -> None:
        action_type = self.on_action.get("type")

        if action_type == "exec":
            cmd = str(self.on_action.get("command", "")).strip()
            if cmd:
                success = utility.execute_command(
                    cmd, "Command", bool(self.on_action.get("terminal", False))
                )
                if success:
                    utility.toast(self.toast_overlay, "▶ Launched")
                else:
                    utility.toast(self.toast_overlay, "✖ Failed")

        elif action_type == "redirect":
            page_id = self.on_action.get("page")
            if page_id and self.context.get("stack"):
                 pages = self.context.get("config", {}).get("pages", [])
                 sidebar = self.context.get("sidebar")
                 
                 for idx, page in enumerate(pages):
                    if isinstance(page, dict) and page.get("id") == page_id:
                        if sidebar:
                            row = sidebar.get_row_at_index(idx)
                            sidebar.select_row(row)
                        
                        label = self.context.get("content_title_label")
                        if label:
                            label.set_label(str(page.get("title", "")))
                        break


class GridToggleCard(Gtk.Button):
    def __init__(
        self,
        properties: dict[str, Any],
        on_toggle: Optional[dict[str, Any]] = None,
        context: Optional[dict[str, Any]] = None,
    ) -> None:
        super().__init__()
        self.add_css_class("hero-card")

        self.properties = properties
        self.on_action = on_toggle if on_toggle is not None else {}
        self.context = context if context is not None else {}

        self.save_as_int = bool(properties.get("save_as_int", False))
        self.key_inverse = bool(properties.get("key_inverse", False))
        self.is_active = False
        self.monitor_source_id: Optional[int] = None
        self._is_destroyed = False
        self._destroy_lock = threading.Lock()
        
        # GUARD
        self._is_monitoring = False

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.set_valign(Gtk.Align.CENTER)
        box.set_halign(Gtk.Align.CENTER)

        icon_name = str(properties.get("icon", "utilities-terminal-symbolic"))
        self.icon_widget = Gtk.Image.new_from_icon_name(icon_name)
        self.icon_widget.set_pixel_size(42)
        self.icon_widget.add_css_class("hero-icon")

        title = Gtk.Label(label=str(properties.get("title", "Toggle")))
        title.add_css_class("hero-title")

        self.status_label = Gtk.Label(label="Off")
        self.status_label.add_css_class("hero-subtitle")

        box.append(self.icon_widget)
        box.append(title)
        box.append(self.status_label)
        self.set_child(box)

        if "key" in properties:
            key = str(properties.get("key", "")).strip()
            system_value = utility.load_setting(key, False, self.key_inverse)
            if isinstance(system_value, bool):
                self._set_visual_state(system_value)

        self.connect("clicked", self._on_clicked)
        self.connect("destroy", self._on_card_destroy)

        try:
            monitor_interval = int(properties.get("interval", 2))
        except (ValueError, TypeError):
            monitor_interval = 2

        if "key" in properties and monitor_interval > 0:
            self.monitor_source_id = GLib.timeout_add_seconds(
                monitor_interval, self._monitor_state
            )

    def _monitor_state(self) -> bool:
        # GUARD CHECK
        if self._is_monitoring:
            return GLib.SOURCE_CONTINUE

        with self._destroy_lock:
            if self._is_destroyed:
                return GLib.SOURCE_REMOVE

        # SET LOCK
        self._is_monitoring = True

        thread = threading.Thread(
            target=self._async_check_state_wrapper, daemon=True
        )
        thread.start()
        return GLib.SOURCE_CONTINUE

    def _async_check_state_wrapper(self) -> None:
        try:
            with self._destroy_lock:
                if self._is_destroyed: return
            
            key = str(self.properties.get("key", "")).strip()
            current_file_state = utility.load_setting(key, False, self.key_inverse)

            if isinstance(current_file_state, bool):
                GLib.idle_add(self._apply_monitor_state, current_file_state)
        finally:
            # RELEASE LOCK
            self._is_monitoring = False

    def _apply_monitor_state(self, current_file_state: bool) -> bool:
        with self._destroy_lock:
            if self._is_destroyed:
                return GLib.SOURCE_REMOVE
        
        # OPTIMIZATION: Only update if changed
        if current_file_state != self.is_active:
            self._set_visual_state(current_file_state)
            
        return GLib.SOURCE_REMOVE

    def _on_card_destroy(self, widget: Gtk.Widget) -> None:
        with self._destroy_lock:
            self._is_destroyed = True
        if self.monitor_source_id is not None:
            GLib.source_remove(self.monitor_source_id)
            self.monitor_source_id = None

    def _set_visual_state(self, state: bool) -> None:
        self.is_active = state
        self.status_label.set_label("On" if state else "Off")
        if state:
            self.add_css_class("toggle-active")
        else:
            self.remove_css_class("toggle-active")

    def _on_clicked(self, button: Gtk.Button) -> None:
        new_state = not self.is_active
        self._set_visual_state(new_state)

        action = self.on_action.get("enabled" if new_state else "disabled", {})
        cmd = str(action.get("command", "")).strip()
        if cmd:
            utility.execute_command(cmd, "Toggle", bool(action.get("terminal", False)))

        if "key" in self.properties:
            utility.save_setting(
                str(self.properties.get("key", "")),
                new_state ^ self.key_inverse,
                self.save_as_int,
            )
