/*
 * MainWindow.vala
 *
 * Copyright 2012-2017 Tony George <teejeetech@gmail.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
 * MA 02110-1301, USA.
 *
 *
 */

using Gtk;
using Gee;

using TeeJee.Logging;
using TeeJee.FileSystem;
using TeeJee.JSON;
using TeeJee.ProcessManagement;
using TeeJee.System;
using TeeJee.Misc;
using TeeJee.GtkHelper;
using TeeJee.GtkHelper;

public class MainWindow : Window {
	private Box vbox_main;

	private Grid grid_backup_buttons;

	private Toolbar toolbar_bottom;
	private ToolButton btn_donate;
	private ToolButton btn_about;

	private Gtk.Entry txt_backup_path;
	private Button btn_browse_backup_dir;
	private Button btn_open_backup_dir;

	private Gtk.Entry txt_password;

	private Button btn_restore_packages;
	private Button btn_backup_packages;

	private Button btn_restore_ppa;
	private Button btn_backup_ppa;
	
	private Button btn_restore_cache;
	private Button btn_backup_cache;

	private Button btn_restore_config;
	private Button btn_backup_config;

	private Button btn_restore_theme;
	private Button btn_backup_theme;

	private Button btn_restore_mount;
	private Button btn_backup_mount;

	private Button btn_restore_home;
	private Button btn_backup_home;

	private Button btn_restore_crontab;
	private Button btn_backup_crontab;
	
	private Button btn_restore_user;
	private Button btn_backup_user;

	private ProgressBar progressbar;
	private Label lbl_status;

	private TerminalWindow term;

	int def_width = 450;
	int def_height = -1;

	int icon_size_list = 22;
	int button_width = 85;
	int button_height = 15;

	public MainWindow () {
		title = AppName + " v" + AppVersion;
		window_position = WindowPosition.CENTER;
		resizable = false;
		destroy.connect (Gtk.main_quit);
		//set_default_size (def_width, def_height);
		icon = get_app_icon(16);

		//vboxMain
		vbox_main = new Box (Orientation.VERTICAL, 6);
		vbox_main.margin = 6;
		vbox_main.set_size_request (def_width, def_height);
		add (vbox_main);

		//actions ---------------------------------------------

		init_section_backup_location();

		init_section_password();

		init_section_backup();

		init_section_toolbar_bottom();

		init_section_status();
	}

	private void init_section_backup_location() {
		
		// header
		var label = new Label ("<b>" + _("Backup Location &amp; Password") + "</b>");
		label.set_use_markup(true);
		label.halign = Align.START;
		//label.margin_top = 12;
		label.margin_bottom = 6;
		vbox_main.pack_start (label, false, true, 0);
		
		//vbox_backup_dir
		Box hbox_backup_dir = new Box (Gtk.Orientation.HORIZONTAL, 6);
		vbox_main.pack_start (hbox_backup_dir, false, true, 0);

		//txt_backup_path
		txt_backup_path = new Gtk.Entry();
		txt_backup_path.hexpand = true;
		//txt_backup_path.secondary_icon_stock = "gtk-open";
		txt_backup_path.placeholder_text = _("Select backup directory");
		txt_backup_path.margin_left = 6;
		hbox_backup_dir.pack_start (txt_backup_path, true, true, 0);

		if ((App.backup_dir != null) && dir_exists (App.backup_dir)) {
			var path = App.backup_dir;
			path = path.has_suffix("/") ? path[0:path.length-1] : path;
			txt_backup_path.text = path;
		}

		txt_backup_path.changed.connect(() => {
			var path = txt_backup_path.text;
			path = path.has_suffix("/") ? path : path + "/";
			App.backup_dir = path;
		});
		
		txt_backup_path.icon_release.connect((p0, p1) => {
			backup_location_browse();
		});

		//btn_browse_backup_dir
		btn_browse_backup_dir = new Gtk.Button.with_label (" " + _("Select") + " ");
		btn_browse_backup_dir.set_size_request(button_width, button_height);
		btn_browse_backup_dir.set_tooltip_text(_("Select backup location"));
		hbox_backup_dir.pack_start (btn_browse_backup_dir, false, true, 0);

		btn_browse_backup_dir.clicked.connect(backup_location_browse);
		
		//btn_open_backup_dir
		btn_open_backup_dir = new Gtk.Button.with_label (" " + _("Open") + " ");
		btn_open_backup_dir.set_size_request(button_width, button_height);
		btn_open_backup_dir.set_tooltip_text(_("Open backup location"));
		hbox_backup_dir.pack_start (btn_open_backup_dir, false, true, 0);

		btn_open_backup_dir.clicked.connect(() => {
			if (check_backup_folder()) {
				exo_open_folder(App.backup_dir, false);
			}
		});

		btn_browse_backup_dir.grab_focus();
	}

	private void init_section_password() {

		//vbox_backup_dir
		Box hbox_backup_dir = new Box (Gtk.Orientation.HORIZONTAL, 6);
		vbox_main.pack_start (hbox_backup_dir, false, true, 0);

		//txt_backup_path
		txt_password = new Gtk.Entry();
		txt_password.hexpand = true;
		//txt_password.secondary_icon_stock = "gtk-open";
		txt_password.placeholder_text = _("Enter encryption password");
		txt_password.margin_left = 6;
		txt_password.visibility = false;
		hbox_backup_dir.pack_start (txt_password, true, true, 0);

		//button
		var button = new Gtk.Button.with_label (" " + _("Show") + " ");
		button.set_size_request(button_width, button_height);
		hbox_backup_dir.pack_start (button, false, true, 0);

		button.clicked.connect(() => {
			txt_password.visibility = !txt_password.visibility;
			if (txt_password.visibility){
				button.label = _("Hide");
				button.set_tooltip_text(_("Hide passphrase"));
			}
			else{
				button.label = _("Show");
				button.set_tooltip_text(_("Show passphrase"));
			}
		});
	}

	private void backup_location_browse(){
		//chooser
		var chooser = new Gtk.FileChooserDialog(
			"Select Path",
			this,
			FileChooserAction.SELECT_FOLDER,
			"_Cancel",
			Gtk.ResponseType.CANCEL,
			"_Open",
			Gtk.ResponseType.ACCEPT
		);

		chooser.select_multiple = false;
		chooser.set_filename(App.backup_dir);

		if (chooser.run() == Gtk.ResponseType.ACCEPT) {
			txt_backup_path.text = chooser.get_filename();
		}

		chooser.destroy();
	}
	
	private void init_section_backup() {

		var sep = new Gtk.Separator(Gtk.Orientation.HORIZONTAL);
		sep.margin_top = 12;
		vbox_main.add(sep);
		
		// lbl_header_backup
		var label = new Label ("<b>" + _("Backup &amp; Restore") + "</b>");
		label.set_use_markup(true);
		label.halign = Align.START;
		label.margin_bottom = 6;
		vbox_main.pack_start (label, false, true, 0);

		//grid_backup_buttons
		grid_backup_buttons = new Grid();
		grid_backup_buttons.set_column_spacing (6);
		grid_backup_buttons.set_row_spacing (6);
		grid_backup_buttons.margin_left = 6;
		vbox_main.pack_start (grid_backup_buttons, false, true, 0);

		int row = -1;

		init_section_backup_ppa(++row);

		init_section_backup_cache(++row);

		init_section_backup_packages(++row);
		
		init_section_backup_themes(++row);
		
		init_section_backup_mounts(++row);

		init_section_backup_users(++row);
		
		init_section_backup_configs(++row);

		init_section_backup_home(++row);
		
		init_section_backup_crontab(++row);
	}

	private void init_section_backup_ppa(int row) {
		var img = get_shared_icon("x-system-software-sources", "ppa.svg", icon_size_list);
		grid_backup_buttons.attach(img, 0, row, 1, 1);

		// label
		var label = new Label (Message.TASK_PPA);
		label.set_tooltip_text(_("Backup Launchpad PPAs"));
		label.set_use_markup(true);
		label.halign = Align.START;
		label.hexpand = true;
		grid_backup_buttons.attach(label, 1, row, 1, 1);

		// btn_backup_ppa
		var button = new Gtk.Button.with_label (_("Backup"));
		button.set_size_request(button_width, button_height);
		button.set_tooltip_text(_("Backup the list of installed PPAs"));
		grid_backup_buttons.attach(button, 2, row, 1, 1);
		btn_backup_ppa = button;
		
		button.clicked.connect(()=>{
			if (!check_backup_folder()) {
				return;
			}

			this.hide();
			var dlg = new PpaWindow.with_parent(this,false);
			dlg.show_all();
		});

		// btn_restore_ppa
		button = new Gtk.Button.with_label (_("Restore"));
		button.set_size_request(button_width, button_height);
		button.set_tooltip_text(_("Add missing PPAs"));
		grid_backup_buttons.attach(button, 3, row, 1, 1);
		btn_restore_ppa = button;
		
		button.clicked.connect(()=>{
			if (!check_backup_folder()) {
				return;
			}
			if (!check_backup_file("ppa.list")) {
				return;
			}

			this.hide();
			var dlg = new PpaWindow.with_parent(this,true);
			dlg.show_all();
		});
	}

	private void init_section_backup_cache(int row) {
		var img = get_shared_icon("download", "cache.svg", icon_size_list);
		grid_backup_buttons.attach(img, 0, row, 1, 1);

		// label
		var label = new Label (Message.TASK_CACHE);
		label.set_tooltip_text(_("Backup downloaded packages in /var/cache/apt"));
		label.set_use_markup(true);
		label.halign = Align.START;
		label.hexpand = true;
		grid_backup_buttons.attach(label, 1, row, 1, 1);

		// btn_backup_cache
		var button = new Gtk.Button.with_label (_("Backup"));
		button.set_size_request(button_width, button_height);
		grid_backup_buttons.attach(button, 2, row, 1, 1);
		btn_backup_cache = button;

		button.clicked.connect(btn_backup_cache_clicked);
		
		// btn_restore_cache
		button = new Gtk.Button.with_label (_("Restore"));
		button.set_size_request(button_width, button_height);
		grid_backup_buttons.attach(button, 3, row, 1, 1);
		btn_restore_cache = button;
		
		button.clicked.connect(btn_restore_cache_clicked);
	}

	private void init_section_backup_packages(int row) {
		var img = get_shared_icon("gnome-package", "package.svg", icon_size_list);
		grid_backup_buttons.attach(img, 0, row, 1, 1);

		// label
		var label = new Label (Message.TASK_PACKAGE);
		label.set_tooltip_text(_("Backup installed packages"));
		label.set_use_markup(true);
		label.halign = Align.START;
		label.hexpand = true;
		grid_backup_buttons.attach(label, 1, row, 1, 1);

		// btn_backup_packages
		var button = new Gtk.Button.with_label (_("Backup"));
		button.set_size_request(button_width, button_height);
		button.vexpand = false;
		grid_backup_buttons.attach(button, 2, row, 1, 1);
		btn_backup_packages = button;
		
		button.clicked.connect(()=>{
			if (!check_backup_folder()) {
				return;
			}

			this.hide();
			var dlg = new PackageWindow.with_parent(this,false);
			dlg.show_all();
		});

		// btn_restore_packages
		button = new Gtk.Button.with_label (_("Restore"));
		button.set_size_request(button_width, button_height);
		grid_backup_buttons.attach(button, 3, row, 1, 1);
		btn_restore_packages = button;
		
		button.clicked.connect(()=>{
			if (!check_backup_folder()) {
				return;
			}
			if (!check_backup_file("packages.list")) {
				return;
			}

			this.hide();
			var dlg = new PackageWindow.with_parent(this,true);
			dlg.show_all();
		});
	}

	private void init_section_backup_users(int row) {
		
		var img = get_shared_icon("config-users", "system-users.svg", icon_size_list);
		grid_backup_buttons.attach(img, 0, row, 1, 1);

		// label
		var label = new Label (Message.TASK_USER);
		label.set_tooltip_text(_("Backup users and groups"));
		label.set_use_markup(true);
		label.halign = Align.START;
		label.hexpand = true;
		grid_backup_buttons.attach(label, 1, row, 1, 1);

		//btn_backup_user
		var button = new Gtk.Button.with_label (_("Backup"));
		button.set_size_request(button_width, button_height);
		grid_backup_buttons.attach(button, 2, row, 1, 1);
		btn_backup_user = button;
		
		button.clicked.connect(btn_backup_users_clicked);

		//btn_restore_user
		button = new Gtk.Button.with_label (_("Restore"));
		button.set_size_request(button_width, button_height);
		grid_backup_buttons.attach(button, 3, row, 1, 1);
		btn_restore_user = button;
		
		button.clicked.connect(btn_restore_users_clicked);
	}

	private void init_section_backup_configs(int row) {
		var img = get_shared_icon("gnome-settings", "config.svg", icon_size_list);
		grid_backup_buttons.attach(img, 0, row, 1, 1);

		// label
		var label = new Label (Message.TASK_CONFIG);
		label.set_tooltip_text(_("Backup application settings"));
		label.set_use_markup(true);
		label.halign = Align.START;
		label.hexpand = true;
		grid_backup_buttons.attach(label, 1, row, 1, 1);

		// btn_backup_config
		var button = new Gtk.Button.with_label (_("Backup"));
		button.set_size_request(button_width, button_height);
		grid_backup_buttons.attach(button, 2, row, 1, 1);
		btn_backup_config = button;
		
		button.clicked.connect(()=>{
			if (!check_backup_folder()) {
				return;
			}

			this.hide();
			var dlg = new ConfigWindow.with_parent(this,false);
			dlg.show_all();
		});

		// btn_restore_config
		button = new Gtk.Button.with_label (_("Restore"));
		button.set_size_request(button_width, button_height);
		grid_backup_buttons.attach(button, 3, row, 1, 1);
		btn_restore_config = button;
		
		button.clicked.connect(()=>{
			if (!check_backup_folder()) {
				return;
			}
			if (!check_backup_subfolder("configs")){
				return;
			}

			this.hide();
			var dlg = new ConfigWindow.with_parent(this,true);
			dlg.show_all();
		});
	}

	private void init_section_backup_themes(int row) {
		var img = get_shared_icon("preferences-theme", "theme.svg", icon_size_list);
		grid_backup_buttons.attach(img, 0, row, 1, 1);

		// label
		var label = new Label (Message.TASK_THEME);
		label.set_tooltip_text(_("Backup themes, icons and cursors in /usr/share/icons and /usr/share/themes"));
		label.set_use_markup(true);
		label.halign = Align.START;
		label.hexpand = true;
		grid_backup_buttons.attach(label, 1, row, 1, 1);

		// btn_backup_theme
		var button = new Gtk.Button.with_label (_("Backup"));
		button.set_size_request(button_width, button_height);
		grid_backup_buttons.attach(button, 2, row, 1, 1);
		btn_backup_theme = button;
		
		button.clicked.connect(()=>{
			if (!check_backup_folder()) {
				return;
			}

			this.hide();
			var dlg = new ThemeWindow.with_parent(this,false);
			dlg.show_all();
		});

		// btn_restore_theme
		button = new Gtk.Button.with_label (_("Restore"));
		button.set_size_request(button_width, button_height);
		grid_backup_buttons.attach(button, 3, row, 1, 1);
		btn_restore_theme = button;

		button.clicked.connect(()=>{
			if (!check_backup_folder()) {
				return;
			}
			if (!(check_backup_subfolder("themes") || check_backup_subfolder("icons"))){
				return;
			}

			this.hide();
			var dlg = new ThemeWindow.with_parent(this,true);
			dlg.show_all();
		});
	}

	private void init_section_backup_mounts(int row) {
		var img = get_shared_icon("gtk-harddisk", "mount.svg", icon_size_list);
		grid_backup_buttons.attach(img, 0, row, 1, 1);

		//label
		var label = new Label (Message.TASK_MOUNT);
		label.set_tooltip_text(_("Backup /etc/fstab and /etc/crypttab entries"));
		label.set_use_markup(true);
		label.halign = Align.START;
		label.hexpand = true;
		grid_backup_buttons.attach(label, 1, row, 1, 1);

		// btn_backup_mount
		var button = new Gtk.Button.with_label (_("Backup"));
		button.set_size_request(button_width, button_height);
		grid_backup_buttons.attach(button, 2, row, 1, 1);
		btn_backup_mount = button;
		
		button.clicked.connect(btn_backup_mounts_clicked);

		// btn_restore_mount
		button = new Gtk.Button.with_label (_("Restore"));
		button.set_size_request(button_width, button_height);
		grid_backup_buttons.attach(button, 3, row, 1, 1);
		btn_restore_mount = button;
		
		button.clicked.connect(btn_restore_mounts_clicked);
	}

	private void init_section_backup_home(int row) {
		var img = get_shared_icon("", "home.svg", icon_size_list);
		grid_backup_buttons.attach(img, 0, row, 1, 1);

		// label
		var label = new Label (Message.TASK_HOME);
		label.set_tooltip_text(_("Backup home directory data\n\nNote: App config directories will not be included in the backup. Use the 'Application Settings' section to backup app config directories."));
		label.set_use_markup(true);
		label.halign = Align.START;
		label.hexpand = true;
		grid_backup_buttons.attach(label, 1, row, 1, 1);

		// btn_backup_home
		var button = new Gtk.Button.with_label (_("Backup"));
		button.set_size_request(button_width, button_height);
		grid_backup_buttons.attach(button, 2, row, 1, 1);
		btn_backup_home = button;
		
		button.clicked.connect(btn_backup_home_clicked);

		// btn_restore_home
		button = new Gtk.Button.with_label (_("Restore"));
		button.set_size_request(button_width, button_height);
		grid_backup_buttons.attach(button, 3, row, 1, 1);
		btn_restore_home = button;
		
		button.clicked.connect(btn_restore_home_clicked);
	}

	private void init_section_backup_crontab(int row) {
		var img = get_shared_icon("", "clock.png", icon_size_list);
		grid_backup_buttons.attach(img, 0, row, 1, 1);

		// label
		var label = new Label (Message.TASK_CRON);
		label.set_tooltip_text(_("Backup scheduled tasks for all users (crontab file)"));
		label.set_use_markup(true);
		label.halign = Align.START;
		label.hexpand = true;
		grid_backup_buttons.attach(label, 1, row, 1, 1);

		// btn_backup_crontab
		var button = new Gtk.Button.with_label (_("Backup"));
		button.set_size_request(button_width, button_height);
		grid_backup_buttons.attach(button, 2, row, 1, 1);
		btn_backup_crontab = button;
		
		button.clicked.connect(()=>{

			if (!check_backup_folder()) {
				return;
			}
		
			bool ok = App.backup_crontab();
			
			if (ok){
				gtk_messagebox(_("Finished"), Message.BACKUP_OK, this, false);
			}
			else{
				gtk_messagebox(_("Error"), Message.BACKUP_ERROR, this, false);
			}
		});

		// btn_restore_crontab
		button = new Gtk.Button.with_label (_("Restore"));
		button.set_size_request(button_width, button_height);
		grid_backup_buttons.attach(button, 3, row, 1, 1);
		btn_restore_crontab = button;
		
		button.clicked.connect(()=>{

			if (!check_backup_folder()) {
				return;
			}
		
			bool ok = App.restore_crontab();
			
			if (ok){
				gtk_messagebox(_("Finished"), Message.RESTORE_OK, this, false);
			}
			else{
				gtk_messagebox(_("Error"), Message.RESTORE_ERROR, this, false);
			}
		});
	}

	private void init_section_status() {
		//lbl_status
		lbl_status = new Label ("");
		lbl_status.halign = Align.START;
		lbl_status.max_width_chars = 50;
		lbl_status.ellipsize = Pango.EllipsizeMode.END;
		lbl_status.no_show_all = true;
		lbl_status.visible = false;
		lbl_status.margin_bottom = 3;
		lbl_status.margin_left = 3;
		lbl_status.margin_right = 3;
		vbox_main.pack_start (lbl_status, false, true, 0);

		//progressbar
		progressbar = new ProgressBar();
		progressbar.no_show_all = true;
		progressbar.margin_bottom = 3;
		progressbar.margin_left = 3;
		progressbar.margin_right = 3;
		progressbar.set_size_request(-1, 25);
		//progressbar.pulse_step = 0.2;
		vbox_main.pack_start (progressbar, false, true, 0);
	}

	private void init_section_toolbar_bottom() {

		var sep = new Gtk.Separator(Gtk.Orientation.HORIZONTAL);
		sep.margin_top = 12;
		vbox_main.add(sep);

		// header
		var label = new Label ("<b>" + _("One-Click Backup &amp; Restore") + "</b>");
		label.set_use_markup(true);
		label.halign = Align.START;
		//label.margin_top = 12;
		//label.margin_bottom = 6;
		vbox_main.pack_start (label, false, true, 0);
		
		//toolbar_bottom
		toolbar_bottom = new Gtk.Toolbar();
		toolbar_bottom.toolbar_style = ToolbarStyle.BOTH;
		vbox_main.add(toolbar_bottom);

		int BUTTON_SIZE = 80;
		int ICON_SIZE = 48;
		
		//remove toolbar background
		var css_provider = new Gtk.CssProvider();
		var toolbar_css = ".toolbar2 { background: alpha (@bg_color, 0.0); border-color: transparent; }";
		try {
			css_provider.load_from_data(toolbar_css,-1);
		} catch (GLib.Error e) {
            warning(e.message);
        }
		toolbar_bottom.get_style_context().add_provider(css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
		toolbar_bottom.get_style_context().add_class("toolbar2");

		//btn_donate
		var button = new Gtk.ToolButton.from_stock ("");
		button.label = _("One-Click\nBackup");
		button.set_tooltip_text (_("One-Click Backup"));
		button.icon_widget = get_shared_icon("", "backup.svg", ICON_SIZE);
		toolbar_bottom.add(button);
		button.set_size_request(BUTTON_SIZE,-1);
		
		button.clicked.connect(btn_backup_all_clicked);
		
		button = new Gtk.ToolButton.from_stock ("");
		button.label = _("One-Click\nRestore");
		button.set_tooltip_text (_("One-Click Restore"));
		button.icon_widget = get_shared_icon("", "restore.svg", ICON_SIZE);
		toolbar_bottom.add(button);
		button.set_size_request(BUTTON_SIZE,-1);
		
		button.clicked.connect(btn_restore_all_clicked);
		
		button = new Gtk.ToolButton.from_stock ("");
		button.label = _("One-Click\nSettings");
		button.set_tooltip_text (_("Settings for One-Click Backup & Restore"));
		button.icon_widget = get_shared_icon("", "config.svg", ICON_SIZE);
		toolbar_bottom.add(button);
		button.set_size_request(BUTTON_SIZE,-1);
		
		button.clicked.connect(btn_settings_clicked);
		
		//separator
		var separator = new Gtk.SeparatorToolItem();
		separator.set_draw (false);
		separator.set_expand (true);
		toolbar_bottom.add(separator);

		//btn_donate
		button = new Gtk.ToolButton.from_stock ("gtk-missing-image");
		button.label = _("Donate");
		button.set_tooltip_text (_("Donate"));
		button.icon_widget = get_shared_icon("donate", "donate.svg", ICON_SIZE);
		toolbar_bottom.add(button);
		button.set_size_request(BUTTON_SIZE,-1);
		btn_donate = button;

		button.clicked.connect(() => {
			var dialog = new DonationWindow();
			dialog.set_transient_for(this);
			dialog.show_all();
			dialog.run();
			dialog.destroy();
		});

		//btn_about
		button = new Gtk.ToolButton.from_stock ("gtk-about");
		button.label = _("About");
		button.set_tooltip_text (_("Application Info"));
		button.icon_widget = get_shared_icon("", "help-info.svg", ICON_SIZE);
		toolbar_bottom.add(button);
		btn_about = button;
		button.set_size_request(BUTTON_SIZE,-1);

		button.clicked.connect (btn_about_clicked);
	}

	private void btn_about_clicked () {
		var dialog = new AboutWindow();
		dialog.set_transient_for (this);

		dialog.authors = {
			"Tony George:teejeetech@gmail.com"
		};

		dialog.contributors = {
			"Shem Pasamba (Proxy support for package downloads):shemgp@gmail.com"
		};

		dialog.third_party = {
			"Numix project (Main app icon):https://numixproject.org/",
			"Elementary project (various icons):https://github.com/elementary/icons",
			"Tango project (various icons):http://tango.freedesktop.org/Tango_Desktop_Project"
		};
		
		dialog.translators = {
			"B. W. Knight (Korean):https://launchpad.net/~kbd0651",
			"giulux (Italian)",
			"Jorge Jamhour (Brazilian Portuguese):https://launchpad.net/~jorge-jamhour",
			"Radek Otáhal (Czech):radek.otahal@email.cz",
			"Rodion R. (Russian):https://launchpad.net/~r0di0n"
		};

		dialog.documenters = null;
		dialog.artists = null;
		dialog.donations = null;

		dialog.program_name = AppName;
		dialog.comments = _("Migration utility for Ubuntu-based distributions");
		dialog.copyright = "Copyright © 2016 Tony George (%s)".printf(AppAuthorEmail);
		dialog.version = AppVersion;
		dialog.logo = get_app_icon(128);

		dialog.license = "This program is free for personal and commercial use and comes with absolutely no warranty. You use this program entirely at your own risk. The author will not be liable for any damages arising from the use of this program.";
		dialog.website = "http://teejeetech.in";
		dialog.website_label = "http://teejeetech.blogspot.in";

		dialog.initialize();
		dialog.show_all();
	}

	private bool check_backup_folder() {
		if ((App.backup_dir != null) && dir_exists (App.backup_dir)) {
			return true;
		}
		else {
			string title = _("Backup Directory Not Selected");
			string msg = _("Select the backup directory");
			gtk_messagebox(title, msg, this, false);
			return false;
		}
	}

	private bool check_password() {

		App.arg_password = txt_password.text;
		
		if (App.arg_password.length > 0){
			return true;
		}
		else {
			string title = _("Password Field is Empty");
			string msg = _("Enter the passphrase for encryption");
			gtk_messagebox(title, msg, this, false);
			return false;
		}
	}


	private bool check_backup_file(string file_name) {
		if (check_backup_folder()) {
			string backup_file = App.backup_dir + file_name;
			var f = File.new_for_path(backup_file);
			if (!f.query_exists()) {
				string title = _("File Not Found");
				string msg = _("File not found in backup directory") + " - %s".printf(file_name);
				gtk_messagebox(title, msg, this, true);
				return false;
			}
			else {
				return true;
			}
		}
		else {
			return false;
		}
	}

	private bool check_backup_subfolder(string folder_name) {
		if (check_backup_folder()) {
			string folder = App.backup_dir + folder_name;
			var f = File.new_for_path(folder);
			if (!f.query_exists()) {
				string title = _("Folder Not Found");
				string msg = _("Folder not found in backup directory") + " - %s".printf(folder_name);
				gtk_messagebox(title, msg, this, true);
				return false;
			}
			else {
				return true;
			}
		}
		else {
			return false;
		}
	}

	/* APT Cache */

	private void btn_backup_cache_clicked() {
		if (!check_backup_folder()) {
			return;
		}

		string archives_dir = App.backup_dir + "archives";
		
		string message = _("Preparing...");
		var dlg = new ProgressWindow.with_parent(this, message, true);
		dlg.show_all();
		gtk_do_events();

		//dlg.pulse_start();
		dlg.update_message(_("Copying packages..."));
		dlg.update_status_line(true);
		
		App.backup_apt_cache();
		while (App.is_running) {
			dlg.update_progressbar();
			dlg.update_status_line();
			dlg.sleep(100);
			
			if (App.cancelled){
				App.rsync_quit();
				gtk_do_events();
			}
		}

		//finish ----------------------------------

		if (!App.cancelled){
			message = Message.BACKUP_OK;
			message += " " + _("(%ld packages in backup)").printf(dir_count(archives_dir));
			dlg.finish(message);
		}
		else{
			dlg.destroy();
		}

		gtk_do_events();
	}

	private void btn_restore_cache_clicked() {
		if (!check_backup_folder()) {
			return;
		}

		//check 'archives' directory
		string archives_dir = App.backup_dir + "archives";
		var f = File.new_for_path(archives_dir);
		if (!f.query_exists()) {
			string title = _("Files Not Found");
			string msg = _("Cache backup not found in backup directory");
			gtk_messagebox(title, msg, this, true);
			return;
		}

		string message = _("Preparing...");
		var dlg = new ProgressWindow.with_parent(this, message, true);
		dlg.show_all();
		gtk_do_events();

		//dlg.pulse_start();
		dlg.update_message(_("Copying packages..."));
		dlg.update_status_line(true);
		
		App.restore_apt_cache();
		while (App.is_running) {
			dlg.update_progressbar();
			dlg.update_status_line();
			dlg.sleep(100);
			
			if (App.cancelled){
				App.rsync_quit();
				gtk_do_events();
			}
		}

		//finish ----------------------------------

		if (!App.cancelled){
			message = Message.RESTORE_OK;
			message += " " + _("(%ld packages in cache)").printf(dir_count("/var/cache/apt/archives") - 2); //excluding 'lock' and 'partial'
			dlg.finish(message);
		}
		else{
			dlg.destroy();
		}

		gtk_do_events();
	}

	/* Home */

	private void btn_backup_home_clicked(){
		
		if (!check_backup_folder()) {
			return;
		}

		if (!check_password()){
			return;
		}

		// select users ------------------------------

		var dlg = new UserDataSettingsDialog.with_parent(this, true);
		int response = dlg.run();
		if (response == Gtk.ResponseType.ACCEPT){

			this.hide();
			
			term = new TerminalWindow.with_parent(this, false, true);
			term.script_complete.connect(all_tasks_complete);
			term.destroy.connect(()=>{
				this.present();
			});
			
			term.execute_script(save_bash_script_temp(App.backup_home_get_script()));
			
			dlg.destroy();
		}
		else{
			dlg.destroy();
			return;
		}
	}

	private void btn_restore_home_clicked(){

		if (!check_backup_folder()) {
			return;
		}

		if (!check_password()){
			return;
		}

		// select users ------------------------------
		
		var dlg = new UserDataSettingsDialog.with_parent(this, false);
		int response = dlg.run();
		if (response == Gtk.ResponseType.ACCEPT){

			this.hide();
			
			term = new TerminalWindow.with_parent(this, false, true);
			term.script_complete.connect(all_tasks_complete);
			term.destroy.connect(()=>{
				this.present();
			});
			
			term.execute_script(save_bash_script_temp(App.restore_home_get_script()));

			dlg.destroy();
		}
		else{
			dlg.destroy();
			return;
		}
	}

	/* Users */

	private void btn_backup_users_clicked(){
		
		if (!check_backup_folder()) {
			return;
		}

		if (!check_password()){
			return;
		}

		bool ok = App.backup_users_and_groups(App.arg_password);

		if (ok){
			gtk_messagebox("", Message.BACKUP_OK, this, false);
		}
		else{
			gtk_messagebox("", Message.BACKUP_ERROR, this, true);
		}
	
	}

	private void btn_restore_users_clicked(){
		
		if (!check_backup_folder()) {
			return;
		}
	
		if (!check_password()){
			return;
		}
		
		if (!check_backup_file("users/passwd.tar.gpg")
		|| !check_backup_file("users/shadow.tar.gpg")
		|| !check_backup_file("users/group.tar.gpg")){
			
			return;
		}

		clear_err_log();
		bool ok = App.restore_users_and_groups_init(App.arg_password);
		show_err_log(this);
		
		if (!ok){
			App.arg_password = ""; // forget password (may be incorrect)
			return;
		}

		this.hide();
		new UserAccountWindow.with_parent(this,true);
	}

	/* Mounts */

	private void btn_backup_mounts_clicked(){
		
		if (!check_backup_folder()) {
			return;
		}

		if (!check_password()){
			return;
		}

		bool ok = App.backup_mounts();
		
		if (ok){
			gtk_messagebox(_("Finished"), Message.BACKUP_OK, this, false);
		}
		else{
			gtk_messagebox(_("Error"), Message.BACKUP_ERROR, this, false);
		}
	}

	private void btn_restore_mounts_clicked(){
		
		if (!check_backup_folder()) {
			return;
		}

		if (!check_password()){
			return;
		}
	
		if (!check_backup_file("mounts/fstab.tar.gpg") && !check_backup_file("mounts/crypttab.tar.gpg")){
			return;
		}

		this.hide();
		new MountWindow.with_parent(this,true);
	}
	
	/* One-click */

	private void btn_backup_all_clicked() {
		
		if (!check_backup_folder()) {
			return;
		}

		if ((App.selected_tasks.length == 0)
			||App.selected_tasks.contains("user")
			||App.selected_tasks.contains("mount")
			||App.selected_tasks.contains("home")){
				
			if (!check_password()){
				return;
			}
		}
		
		this.hide();

		App.task_list = BackupTask.create_list();
		App.backup_mode = true;

		term = new TerminalWindow.with_parent(this, false, true);
		term.script_complete.connect(all_tasks_complete);
		term.destroy.connect(()=>{
			this.present();
		});

		string sh = "";
		foreach(var task in App.task_list){
			if (!task.is_selected){
				continue;
			}
			
			var cmd = (App.backup_mode) ? task.backup_cmd : task.restore_cmd;
			sh += "echo '%s'\n".printf(string.nfill(70,'='));
			sh += "echo '%s'\n".printf(task.display_name);
			sh += "echo '%s'\n".printf(string.nfill(70,'='));
			sh += "%s\n".printf(cmd);
			sh += "echo ''\n";
		}

		sh += "echo ''\n";
		sh += "echo 'Close window to exit...'\n";

		term.execute_script(save_bash_script_temp(sh));
	}
	
	private void btn_restore_all_clicked() {
		
		if (!check_backup_folder()) {
			return;
		}

		if ((App.selected_tasks.length == 0)
			||App.selected_tasks.contains("user")
			||App.selected_tasks.contains("mount")
			||App.selected_tasks.contains("home")){
				
			if (!check_password()){
				return;
			}
		}

		this.hide();

		App.task_list = BackupTask.create_list();
		App.backup_mode = false;
		
		term = new TerminalWindow.with_parent(this, false, true);
		term.script_complete.connect(all_tasks_complete);
		term.destroy.connect(()=>{
			this.present();
		});

		string sh = "";
		foreach(var task in App.task_list){
			if (!task.is_selected){
				continue;
			}
			
			string cmd = (App.backup_mode) ? task.backup_cmd : task.restore_cmd;
			sh += "echo '%s'\n".printf(string.nfill(70,'='));
			sh += "echo '%s'\n".printf(task.display_name);
			sh += "echo '%s'\n".printf(string.nfill(70,'='));
			sh += "%s\n".printf(cmd);
			sh += "echo ''\n";
		}
		
		sh += "echo ''\n";
		sh += "echo 'Close window to exit...'\n";

		term.execute_script(save_bash_script_temp(sh));
	}

	private void all_tasks_complete(){
		term.script_complete.disconnect(all_tasks_complete);
		term.execute_script(save_bash_script_temp("echo ''\necho 'Close window to exit...'\n"));
		term.allow_window_close();
	}

	private void btn_settings_clicked(){
		App.task_list = BackupTask.create_list();
		var dlg = new OneClickSettingsDialog.with_parent(this);
		dlg.run();
		dlg.destroy();
	}
}


