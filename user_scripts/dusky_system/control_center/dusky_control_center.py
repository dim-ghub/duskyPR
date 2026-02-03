#!/usr/bin/env python3
"""
Dusky Control Center (Production Build)
A GTK4/Libadwaita configuration launcher for the Dusky Dotfiles.
Fully UWSM-compliant for Arch Linux/Hyprland environments.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path
from typing import Any, Optional

# =============================================================================
# VERSION CHECK
# =============================================================================
if sys.version_info < (3, 10):
    sys.exit("[FATAL] Python 3.10+ is required for this application.")

# =============================================================================
# CACHE CONFIGURATION
# =============================================================================
try:
    XDG_CACHE_HOME = os.environ.get(
        "XDG_CACHE_HOME", os.path.join(os.path.expanduser("~"), ".cache")
    )
    CACHE_DIR = os.path.join(XDG_CACHE_HOME, "duskycc")
    Path(CACHE_DIR).mkdir(parents=True, exist_ok=True)
    sys.pycache_prefix = CACHE_DIR
except OSError as e:
    print(f"[WARN] Could not set custom pycache location: {e}")

# =============================================================================
# IMPORTS & PRE-FLIGHT
# =============================================================================
import lib.utility as utility

# Pre-flight check ensures dependencies exist before GTK import tries to crash
utility.preflight_check()

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, Gio, GLib, Gtk, Pango

import lib.rows as rows

# =============================================================================
# CONSTANTS
# =============================================================================
APP_ID = "com.github.dusky.controlcenter"
APP_TITLE = "Dusky Control Center"
CONFIG_FILENAME = "dusky_config.yaml"
SCRIPT_DIR = Path(__file__).resolve().parent
CSS_FILENAME = "dusky_style.css"

try:
    with open(SCRIPT_DIR / CSS_FILENAME, "r", encoding="utf-8") as f:
        CSS = f.read()
except OSError:
    print(f"[WARN] CSS file not found or unreadable: {CSS_FILENAME}")
    CSS = ""


class DuskyControlCenter(Adw.Application):
    """Main application class."""

    def __init__(self) -> None:
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.FLAGS_NONE)
        self.config: dict[str, Any] = {}
        self.sidebar_list: Optional[Gtk.ListBox] = None
        self.stack: Optional[Adw.ViewStack] = None
        self.content_title_label: Optional[Gtk.Label] = None
        self.toast_overlay: Optional[Adw.ToastOverlay] = None
        self.search_bar: Optional[Gtk.SearchBar] = None
        self.search_entry: Optional[Gtk.SearchEntry] = None
        self.search_page: Optional[Adw.PreferencesPage] = None
        self.search_results_group: Optional[Adw.PreferencesGroup] = None
        self.last_visible_page: Optional[str] = None
        self.search_debounce_source: Optional[int] = None

    def do_activate(self) -> None:
        """GTK Application activation hook."""
        # Note: StyleManager default is implicitly handled by Adwaita
        self.config = utility.load_config(SCRIPT_DIR / CONFIG_FILENAME)
        self._validate_config()
        self._apply_css()
        self._build_ui()

    def do_shutdown(self) -> None:
        """GTK Application shutdown hook. Clean up pending sources."""
        if self.search_debounce_source is not None:
            GLib.source_remove(self.search_debounce_source)
            self.search_debounce_source = None
        Adw.Application.do_shutdown(self)

    def _validate_config(self) -> None:
        """Ensure critical config keys exist to prevent runtime crashes."""
        if not isinstance(self.config, dict):
            self.config = {}
        if "pages" not in self.config or not isinstance(self.config["pages"], list):
            self.config["pages"] = []

    def _apply_css(self) -> None:
        """Load and apply the custom CSS stylesheet."""
        if not CSS:
            return
        provider = Gtk.CssProvider()
        provider.load_from_data(CSS.encode("utf-8"))
        display = Gdk.Display.get_default()
        if display:
            Gtk.StyleContext.add_provider_for_display(
                display, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            )

    def _get_context(self) -> dict[str, Any]:
        """Build the shared context dictionary for all row widgets."""
        return {
            "stack": self.stack,
            "content_title_label": self.content_title_label,
            "config": self.config,
            "sidebar": self.sidebar_list,
            "toast_overlay": self.toast_overlay,
        }

    def _build_ui(self) -> None:
        """Construct the main application window and layout."""
        window = Adw.Window(application=self, title=APP_TITLE)
        window.set_default_size(1180, 780)

        key_controller = Gtk.EventControllerKey()
        key_controller.connect("key-pressed", self._on_key_pressed)
        window.add_controller(key_controller)

        self.toast_overlay = Adw.ToastOverlay()
        split = Adw.OverlaySplitView()
        split.set_min_sidebar_width(220)
        split.set_max_sidebar_width(260)
        split.set_sidebar_width_fraction(0.25)

        split.set_sidebar(self._create_sidebar())
        split.set_content(self._create_content_panel())

        self.toast_overlay.set_child(split)
        window.set_content(self.toast_overlay)

        self._create_search_page()
        self._populate_pages()
        window.present()

    def _on_key_pressed(
        self,
        controller: Gtk.EventControllerKey,
        keyval: int,
        keycode: int,
        state: Gdk.ModifierType,
    ) -> bool:
        """Handle global keyboard shortcuts."""
        ctrl_held = bool(state & Gdk.ModifierType.CONTROL_MASK)

        if ctrl_held and keyval == Gdk.KEY_r:
            self._reload_app()
            return True
        if ctrl_held and keyval == Gdk.KEY_f:
            if self.search_bar and self.search_entry:
                self.search_bar.set_search_mode(True)
                self.search_entry.grab_focus()
            return True
        if ctrl_held and keyval == Gdk.KEY_q:
            self.quit()
            return True
        if keyval == Gdk.KEY_Escape:
            if self.search_bar and self.search_bar.get_search_mode():
                self.search_bar.set_search_mode(False)
                self._exit_search_mode()
            return True
        return False

    def _reload_app(self) -> None:
        """Hot Reload: Refresh config and rebuild UI."""
        print("[INFO] Hot Reload Initiated...")
        new_config = utility.load_config(SCRIPT_DIR / CONFIG_FILENAME)
        if not new_config:
            self._toast("Reload Failed: Invalid Config", 3)
            return

        self.config = new_config
        self._validate_config()

        # Aggressive cleanup of old widgets with safety break
        if self.sidebar_list:
            max_rows = 500  # Safety limit to prevent infinite loops
            for _ in range(max_rows):
                row = self.sidebar_list.get_row_at_index(0)
                if not row:
                    break
                self.sidebar_list.remove(row)

        if self.stack:
            child = self.stack.get_first_child()
            while child:
                next_child = child.get_next_sibling()
                self.stack.remove(child)
                child = next_child

        self._create_search_page()
        self._populate_pages()
        self._toast("Configuration Reloaded 🚀")

    # ─────────────────────────────────────────────────────────────────────────
    # SEARCH LOGIC
    # ─────────────────────────────────────────────────────────────────────────
    def _create_search_page(self) -> None:
        self.search_page = Adw.PreferencesPage()
        self.search_results_group = Adw.PreferencesGroup(title="Search Results")
        self.search_page.add(self.search_results_group)
        if self.stack:
            self.stack.add_named(self.search_page, "search-results")

    def _on_search_btn_toggled(self, button: Gtk.ToggleButton) -> None:
        if not self.search_bar:
            return
        is_active = button.get_active()
        self.search_bar.set_search_mode(is_active)
        if is_active and self.search_entry:
            self.search_entry.grab_focus()
        else:
            self._exit_search_mode()

    def _exit_search_mode(self) -> None:
        if self.search_entry:
            self.search_entry.set_text("")
        if self.last_visible_page and self.stack:
            self.stack.set_visible_child_name(self.last_visible_page)
            if self.content_title_label:
                self.content_title_label.set_label(
                    self._get_page_title_by_id(self.last_visible_page)
                )

    def _get_page_title_by_id(self, page_id: str) -> str:
        if not page_id.startswith("page-"):
            return "Settings"
        try:
            index = int(page_id.split("-", 1)[1])
            pages = self.config.get("pages", [])
            if 0 <= index < len(pages):
                return str(pages[index].get("title", "Settings"))
        except (ValueError, IndexError, KeyError, TypeError):
            pass
        return "Settings"

    def _on_search_changed(self, entry: Gtk.SearchEntry) -> None:
        if self.search_debounce_source is not None:
            GLib.source_remove(self.search_debounce_source)
            self.search_debounce_source = None

        self.search_debounce_source = GLib.timeout_add(
            200, self._execute_search_delayed, entry.get_text()
        )

    def _execute_search_delayed(self, query_text: str) -> bool:
        self.search_debounce_source = None
        if not self.stack or not self.search_page or not self.search_results_group:
            return GLib.SOURCE_REMOVE

        query = query_text.strip().lower()
        if not query:
            self._clear_search_results("Search Results")
            return GLib.SOURCE_REMOVE

        current_page = self.stack.get_visible_child_name()
        if current_page and current_page != "search-results":
            self.last_visible_page = current_page

        self.stack.set_visible_child_name("search-results")
        if self.content_title_label:
            self.content_title_label.set_label("Search")

        self._clear_search_results(f"Results for '{query}'")
        self._perform_search(query)
        return GLib.SOURCE_REMOVE

    def _clear_search_results(self, new_title: str) -> None:
        if self.search_page and self.search_results_group:
            self.search_page.remove(self.search_results_group)
            self.search_results_group = Adw.PreferencesGroup(title=new_title)
            self.search_page.add(self.search_results_group)

    def _perform_search(self, query: str) -> None:
        if not self.search_results_group:
            return
        found_count = 0

        # Type safe iteration
        for page in self.config.get("pages", []):
            if not isinstance(page, dict):
                continue
            page_name = str(page.get("title", "Unknown"))

            for section in page.get("layout", []):
                if not isinstance(section, dict):
                    continue

                for item in section.get("items", []):
                    if not isinstance(item, dict):
                        continue
                    
                    props = item.get("properties", {})
                    if not isinstance(props, dict):
                        continue

                    title = str(props.get("title", "")).lower()
                    desc = str(props.get("description", "")).lower()

                    if query in title or query in desc:
                        context_item = item.copy()
                        context_item["properties"] = props.copy()
                        original_desc = props.get("description", "")
                        context_item["properties"]["description"] = (
                            f"{page_name} • {original_desc}" if original_desc else page_name
                        )
                        row = self._build_item_row(context_item)
                        self.search_results_group.add(row)
                        found_count += 1

        if found_count == 0:
            status = Adw.ActionRow(title="No results found")
            status.set_activatable(False)
            self.search_results_group.add(status)

    # ─────────────────────────────────────────────────────────────────────────
    # UI CONSTRUCTION
    # ─────────────────────────────────────────────────────────────────────────
    def _create_sidebar(self) -> Adw.ToolbarView:
        view = Adw.ToolbarView()
        view.add_css_class("sidebar-container")

        header = Adw.HeaderBar()
        header.add_css_class("sidebar-header")
        header.set_show_end_title_buttons(False)

        title_box = Gtk.Box(spacing=8)
        icon = Gtk.Image.new_from_icon_name("emblem-system-symbolic")
        icon.add_css_class("sidebar-header-icon")
        label = Gtk.Label(label="Dusky")
        label.add_css_class("title")
        title_box.append(icon)
        title_box.append(label)
        header.set_title_widget(title_box)

        search_btn = Gtk.ToggleButton(icon_name="system-search-symbolic")
        search_btn.set_tooltip_text("Search Settings (Ctrl+F)")
        search_btn.connect("toggled", self._on_search_btn_toggled)
        header.pack_end(search_btn)

        view.add_top_bar(header)

        self.search_bar = Gtk.SearchBar()
        self.search_entry = Gtk.SearchEntry(placeholder_text="Find setting...")
        self.search_entry.connect("search-changed", self._on_search_changed)
        self.search_bar.set_child(self.search_entry)
        self.search_bar.connect_entry(self.search_entry)
        view.add_top_bar(self.search_bar)

        self.sidebar_list = Gtk.ListBox()
        self.sidebar_list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.sidebar_list.add_css_class("sidebar-listbox")
        self.sidebar_list.connect("row-selected", self._on_row_selected)

        scroll = Gtk.ScrolledWindow(vexpand=True)
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_child(self.sidebar_list)
        view.set_content(scroll)
        return view

    def _make_sidebar_row(self, name: str, icon_name: str) -> Gtk.ListBoxRow:
        row = Gtk.ListBoxRow()
        row.add_css_class("sidebar-row")
        box = Gtk.Box()
        icon = Gtk.Image.new_from_icon_name(icon_name)
        icon.add_css_class("sidebar-row-icon")
        label = Gtk.Label(label=name, xalign=0, hexpand=True)
        label.add_css_class("sidebar-row-label")
        label.set_ellipsize(Pango.EllipsizeMode.END)
        box.append(icon)
        box.append(label)
        row.set_child(box)
        return row

    def _on_row_selected(self, listbox: Gtk.ListBox, row: Optional[Gtk.ListBoxRow]) -> None:
        if row is None or self.stack is None:
            return
        index = row.get_index()
        pages = self.config.get("pages", [])
        if 0 <= index < len(pages):
            self.stack.set_visible_child_name(f"page-{index}")
            if self.content_title_label:
                self.content_title_label.set_label(str(pages[index].get("title", "")))

    def _create_content_panel(self) -> Adw.ToolbarView:
        view = Adw.ToolbarView()
        header = Adw.HeaderBar()
        header.add_css_class("content-header")
        self.content_title_label = Gtk.Label(label="Welcome")
        self.content_title_label.add_css_class("content-title")
        header.set_title_widget(self.content_title_label)
        view.add_top_bar(header)
        self.stack = Adw.ViewStack(vexpand=True, hexpand=True)
        view.set_content(self.stack)
        return view

    def _populate_pages(self) -> None:
        pages = self.config.get("pages", [])
        if not pages:
            self._show_empty_state()
            return

        first_row: Optional[Gtk.ListBoxRow] = None
        for idx, page_data in enumerate(pages):
            if not isinstance(page_data, dict):
                continue
            name = str(page_data.get("title", "Untitled"))
            icon = str(page_data.get("icon", "application-x-executable-symbolic"))

            row = self._make_sidebar_row(name, icon)
            if self.sidebar_list:
                self.sidebar_list.append(row)

            pref_page = self._build_pref_page(page_data)
            if self.stack:
                self.stack.add_named(pref_page, f"page-{idx}")

            if idx == 0:
                first_row = row

        if first_row and self.sidebar_list:
            self.sidebar_list.select_row(first_row)

    def _build_pref_page(self, page_data: dict[str, Any]) -> Adw.PreferencesPage:
        page = Adw.PreferencesPage()
        context = self._get_context()

        for section_data in page_data.get("layout", []):
            if not isinstance(section_data, dict):
                continue
            section_type = section_data.get("type")

            if section_type == "grid_section":
                group = Adw.PreferencesGroup()
                title = str(section_data.get("properties", {}).get("title", ""))
                if title:
                    group.set_title(GLib.markup_escape_text(title))

                flowbox = Gtk.FlowBox()
                flowbox.set_valign(Gtk.Align.START)
                flowbox.set_selection_mode(Gtk.SelectionMode.NONE)
                flowbox.set_column_spacing(12)
                flowbox.set_row_spacing(12)

                for item in section_data.get("items", []):
                    if not isinstance(item, dict):
                        continue
                    props = item.get("properties", {})
                    if item.get("type") == "toggle_card":
                        card = rows.GridToggleCard(props, item.get("on_toggle"), context)
                    else:
                        card = rows.GridCard(props, item.get("on_press"), context)
                    flowbox.append(card)

                group.add(flowbox)
                page.add(group)

            elif section_type == "section" or "items" in section_data:
                group = Adw.PreferencesGroup()
                props = section_data.get("properties", {})
                title = str(props.get("title", ""))
                if title:
                    group.set_title(GLib.markup_escape_text(title))
                desc = str(props.get("description", ""))
                if desc:
                    group.set_description(GLib.markup_escape_text(desc))
                for item in section_data.get("items", []):
                    if not isinstance(item, dict):
                        continue
                    group.add(self._build_item_row(item, context))
                page.add(group)
            else:
                group = Adw.PreferencesGroup()
                group.add(self._build_item_row(section_data, context))
                page.add(group)

        return page

    def _build_item_row(self, item: dict[str, Any], context: Optional[dict[str, Any]] = None) -> Adw.PreferencesRow:
        """Build a single row widget from an item definition."""
        item_type = item.get("type")
        properties = item.get("properties", {})
        if context is None: context = self._get_context()

        if item_type == "button":
            return rows.ButtonRow(properties, item.get("on_press"), context)
        if item_type == "toggle":
            return rows.ToggleRow(properties, item.get("on_toggle"), context)
        if item_type == "label":
            return rows.LabelRow(properties, item.get("value"), context)
        if item_type == "slider":
            return rows.SliderRow(properties, item.get("on_change"), context)
        if item_type == "warning_banner":
            return self._build_warning_banner_row(properties)
        # Default fallback
        return rows.ButtonRow(properties, item.get("on_press"), context)

    def _build_warning_banner_row(self, properties: dict[str, Any]) -> Adw.PreferencesRow:
        row = Adw.PreferencesRow()
        row.add_css_class("action-row")

        banner_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        banner_box.add_css_class("warning-banner-box")

        warning_icon = Gtk.Image.new_from_icon_name("dialog-warning-symbolic")
        warning_icon.set_halign(Gtk.Align.CENTER)
        warning_icon.set_margin_bottom(8)
        warning_icon.add_css_class("warning-banner-icon")

        title_text = GLib.markup_escape_text(str(properties.get("title", "Warning")))
        title_label = Gtk.Label(label=title_text)
        title_label.add_css_class("title-1")
        title_label.set_halign(Gtk.Align.CENTER)

        message_text = GLib.markup_escape_text(str(properties.get("message", "")))
        message_label = Gtk.Label(label=message_text)
        message_label.add_css_class("body")
        message_label.set_halign(Gtk.Align.CENTER)
        message_label.set_wrap(True)

        banner_box.append(warning_icon)
        banner_box.append(title_label)
        banner_box.append(message_label)
        row.set_child(banner_box)
        return row

    def _show_empty_state(self) -> None:
        box = Gtk.Box(
            orientation=Gtk.Orientation.VERTICAL,
            spacing=8,
            halign=Gtk.Align.CENTER,
            valign=Gtk.Align.CENTER,
        )
        box.add_css_class("empty-state-box")
        icon = Gtk.Image.new_from_icon_name("document-open-symbolic")
        icon.add_css_class("empty-state-icon")
        title = Gtk.Label(label="No Configuration Found")
        title.add_css_class("empty-state-title")
        subtitle = Gtk.Label(label="Create a config file to define your control center layout.")
        subtitle.add_css_class("empty-state-subtitle")
        box.append(icon)
        box.append(title)
        box.append(subtitle)
        if self.stack:
            self.stack.add_named(box, "empty-state")

    def _toast(self, message: str, timeout: int = 2) -> None:
        if self.toast_overlay:
            toast = Adw.Toast(title=message, timeout=timeout)
            self.toast_overlay.add_toast(toast)


if __name__ == "__main__":
    app = DuskyControlCenter()
    sys.exit(app.run(sys.argv))
