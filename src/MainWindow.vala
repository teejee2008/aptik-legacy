/*
 * MainWindow.vala
 *
 * Copyright 2015 Tony George <teejee2008@gmail.com>
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
using TeeJee.GtkHelper;
using TeeJee.Multimedia;
using TeeJee.System;
using TeeJee.Misc;

public class MainWindow : Window {
	private Box vbox_main;

	private Grid grid_backup_buttons;

	private Toolbar toolbar_bottom;
	private ToolButton btn_donate;
	private ToolButton btn_about;

	private Gtk.Entry txt_backup_path;
	private Button btn_browse_backup_dir;
	private Button btn_open_backup_dir;

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

	private Button btn_software_manager;

	private ProgressBar progressbar;
	private Label lbl_status;

	int def_width = 400;
	int def_height = -1;

	int icon_size_list = 22;
	int button_width = 85;
	int button_height = 15;

	public MainWindow () {
		title = AppName + " v" + AppVersion;
		window_position = WindowPosition.CENTER;
		resizable = false;
		destroy.connect (Gtk.main_quit);
		set_default_size (def_width, def_height);
		icon = get_app_icon(16);

		//vboxMain
		vbox_main = new Box (Orientation.VERTICAL, 0);
		vbox_main.margin = 12;
		add (vbox_main);

		//actions ---------------------------------------------

		init_section_backup_location();

		init_section_backup();

		//init_section_tools();

		init_section_toolbar_bottom();

		init_section_status();
	}

	private void init_section_backup_location() {
		// lbl_header_location
		Label lbl_header_location = new Label ("<b>" + _("Backup Directory") + "</b>");
		lbl_header_location.set_use_markup(true);
		lbl_header_location.halign = Align.START;
		//lbl_header_location.margin_top = 6;
		lbl_header_location.margin_bottom = 6;
		vbox_main.pack_start (lbl_header_location, false, true, 0);

		//vbox_backup_dir
		Box hbox_backup_dir = new Box (Gtk.Orientation.HORIZONTAL, 6);
		vbox_main.pack_start (hbox_backup_dir, false, true, 0);

		//txt_backup_path
		txt_backup_path = new Gtk.Entry();
		txt_backup_path.hexpand = true;
		//txt_backup_path.secondary_icon_stock = "gtk-open";
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
		// lbl_header_backup
		Label lbl_header_backup = new Label ("<b>" + _("Backup &amp; Restore") + "</b>");
		lbl_header_backup.set_use_markup(true);
		lbl_header_backup.halign = Align.START;
		lbl_header_backup.margin_top = 12;
		lbl_header_backup.margin_bottom = 6;
		vbox_main.pack_start (lbl_header_backup, false, true, 0);

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
	
		init_section_backup_configs(++row);

		init_section_backup_themes(++row);
	}

	private void init_section_backup_ppa(int row) {
		var img = get_shared_icon("x-system-software-sources", "ppa.svg", icon_size_list);
		grid_backup_buttons.attach(img, 0, row, 1, 1);

		//lbl_backup_ppa
		Label lbl_backup_ppa = new Label (" " + _("Software Sources (PPAs)"));
		lbl_backup_ppa.set_tooltip_text(_("Software Sources (Third Party PPAs)"));
		lbl_backup_ppa.set_use_markup(true);
		lbl_backup_ppa.halign = Align.START;
		lbl_backup_ppa.hexpand = true;
		grid_backup_buttons.attach(lbl_backup_ppa, 1, row, 1, 1);

		//btn_backup_ppa
		btn_backup_ppa = new Gtk.Button.with_label (" " + _("Backup") + " ");
		btn_backup_ppa.set_size_request(button_width, button_height);
		btn_backup_ppa.set_tooltip_text(_("Backup the list of installed PPAs"));
		grid_backup_buttons.attach(btn_backup_ppa, 2, row, 1, 1);

		btn_backup_ppa.clicked.connect(()=>{
			if (!check_backup_folder()) {
				return;
			}

			this.hide();
			var dlg = new PpaWindow.with_parent(this,false);
			dlg.show_all();
		});

		//btn_restore_ppa
		btn_restore_ppa = new Gtk.Button.with_label (" " + _("Restore") + " ");
		btn_restore_ppa.set_size_request(button_width, button_height);
		btn_restore_ppa.set_tooltip_text(_("Add missing PPAs"));
		grid_backup_buttons.attach(btn_restore_ppa, 3, row, 1, 1);

		btn_restore_ppa.clicked.connect(()=>{
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

		//lbl_backup_cache
		Label lbl_backup_cache = new Label (" " + _("Downloaded Packages (APT Cache)"));
		lbl_backup_cache.set_tooltip_text(_("Downloaded Packages (APT Cache)"));
		lbl_backup_cache.set_use_markup(true);
		lbl_backup_cache.halign = Align.START;
		lbl_backup_cache.hexpand = true;
		grid_backup_buttons.attach(lbl_backup_cache, 1, row, 1, 1);

		//btn_backup_cache
		btn_backup_cache = new Gtk.Button.with_label (" " + _("Backup") + " ");
		btn_backup_cache.set_size_request(button_width, button_height);
		btn_backup_cache.set_tooltip_text(_("Backup downloaded packages from APT cache"));
		btn_backup_cache.clicked.connect(btn_backup_cache_clicked);
		grid_backup_buttons.attach(btn_backup_cache, 2, row, 1, 1);

		//btn_restore_cache
		btn_restore_cache = new Gtk.Button.with_label (" " + _("Restore") + " ");
		btn_restore_cache.set_size_request(button_width, button_height);
		btn_restore_cache.set_tooltip_text(_("Restore downloaded packages to APT cache"));
		btn_restore_cache.clicked.connect(btn_restore_cache_clicked);
		grid_backup_buttons.attach(btn_restore_cache, 3, row, 1, 1);
	}

	private void init_section_backup_packages(int row) {
		var img = get_shared_icon("gnome-package", "package.svg", icon_size_list);
		grid_backup_buttons.attach(img, 0, row, 1, 1);

		//lbl_backup_packages
		Label lbl_backup_packages = new Label (" " + _("Software Selections"));
		lbl_backup_packages.set_tooltip_text(_("Software Selections (Installed Packages)"));
		lbl_backup_packages.set_use_markup(true);
		lbl_backup_packages.halign = Align.START;
		lbl_backup_packages.hexpand = true;
		grid_backup_buttons.attach(lbl_backup_packages, 1, row, 1, 1);

		//btn_backup_packages
		btn_backup_packages = new Gtk.Button.with_label (" " + _("Backup") + " ");
		btn_backup_packages.set_size_request(button_width, button_height);
		btn_backup_packages.set_tooltip_text(_("Backup the list of installed packages"));
		btn_backup_packages.vexpand = false;
		grid_backup_buttons.attach(btn_backup_packages, 2, row, 1, 1);

		btn_backup_packages.clicked.connect(()=>{
			if (!check_backup_folder()) {
				return;
			}

			this.hide();
			var dlg = new PackageWindow.with_parent(this,false);
			dlg.show_all();
		});

		//btn_restore_packages
		btn_restore_packages = new Gtk.Button.with_label (" " + _("Restore") + " ");
		btn_restore_packages.set_size_request(button_width, button_height);
		btn_restore_packages.set_tooltip_text(_("Install missing packages"));
		grid_backup_buttons.attach(btn_restore_packages, 3, row, 1, 1);

		btn_restore_packages.clicked.connect(()=>{
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

	private void init_section_backup_configs(int row) {
		var img = get_shared_icon("gnome-settings", "config.svg", icon_size_list);
		grid_backup_buttons.attach(img, 0, row, 1, 1);

		//lbl_backup_config
		Label lbl_backup_config = new Label (" " + _("Application Settings"));
		lbl_backup_config.set_tooltip_text(_("Application Settings"));
		lbl_backup_config.set_use_markup(true);
		lbl_backup_config.halign = Align.START;
		lbl_backup_config.hexpand = true;
		grid_backup_buttons.attach(lbl_backup_config, 1, row, 1, 1);

		//btn_backup_config
		btn_backup_config = new Gtk.Button.with_label (" " + _("Backup") + " ");
		btn_backup_config.set_size_request(button_width, button_height);
		btn_backup_config.set_tooltip_text(_("Backup application settings"));
		grid_backup_buttons.attach(btn_backup_config, 2, row, 1, 1);

		btn_backup_config.clicked.connect(()=>{
			if (!check_backup_folder()) {
				return;
			}

			this.hide();
			var dlg = new ConfigWindow.with_parent(this,false);
			dlg.show_all();
		});

		//btn_restore_config
		btn_restore_config = new Gtk.Button.with_label (" " + _("Restore") + " ");
		btn_restore_config.set_size_request(button_width, button_height);
		btn_restore_config.set_tooltip_text(_("Restore application settings"));
		grid_backup_buttons.attach(btn_restore_config, 3, row, 1, 1);

		btn_restore_config.clicked.connect(()=>{
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

		//lbl_backup_theme
		Label lbl_backup_theme = new Label (" " + _("Themes and Icons"));
		lbl_backup_theme.set_tooltip_text(_("Themes and Icons"));
		lbl_backup_theme.set_use_markup(true);
		lbl_backup_theme.halign = Align.START;
		lbl_backup_theme.hexpand = true;
		grid_backup_buttons.attach(lbl_backup_theme, 1, row, 1, 1);

		//btn_backup_theme
		btn_backup_theme = new Gtk.Button.with_label (" " + _("Backup") + " ");
		btn_backup_theme.set_size_request(button_width, button_height);
		btn_backup_theme.set_tooltip_text(_("Backup themes and icons"));
		grid_backup_buttons.attach(btn_backup_theme, 2, row, 1, 1);

		btn_backup_theme.clicked.connect(()=>{
			if (!check_backup_folder()) {
				return;
			}

			this.hide();
			var dlg = new ThemeWindow.with_parent(this,false);
			dlg.show_all();
		});

		//btn_restore_theme
		btn_restore_theme = new Gtk.Button.with_label (" " + _("Restore") + " ");
		btn_restore_theme.set_size_request(button_width, button_height);
		btn_restore_theme.set_tooltip_text(_("Restore themes and icons"));
		grid_backup_buttons.attach(btn_restore_theme, 3, row, 1, 1);

		btn_restore_theme.clicked.connect(()=>{
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

	private void init_section_tools() {
		// lbl_header_tools
		Label lbl_header_tools = new Label ("<b>" + _("Tools &amp; Tweaks") + "</b>");
		lbl_header_tools.set_use_markup(true);
		lbl_header_tools.halign = Align.START;
		lbl_header_tools.margin_top = 6;
		lbl_header_tools.margin_bottom = 6;
		vbox_main.pack_start (lbl_header_tools, false, true, 0);

		//grid_backup_tools
		Grid grid_backup_tools = new Grid();
		grid_backup_tools.set_column_spacing (6);
		grid_backup_tools.set_row_spacing (6);
		grid_backup_tools.margin_left = 6;
		vbox_main.pack_start (grid_backup_tools, false, true, 0);

		int row = 1;

		//btn_software_manager
		btn_software_manager = new Gtk.Button.with_label (" " + _("Software Manager") + " ");
		btn_software_manager.set_size_request(button_width, button_height);
		btn_software_manager.set_tooltip_text(_("Add &amp; Remove Software Packages"));
		grid_backup_tools.attach(btn_software_manager, 0, row, 1, 1);

		btn_software_manager.clicked.connect(() => {
			//var win = new PackageManagerWindow.with_parent(this);
			//win.title = "Aptik Package Manager" + " v" + AppVersion;
			//win.show_all();
			//dialog.destroy();
		});

		//btn_battery_monitor
		var btn_battery_monitor = new Gtk.Button.with_label (" " + _("Battery Monitor") + " ");
		btn_battery_monitor.set_size_request(button_width, button_height);
		btn_battery_monitor.set_tooltip_text(_("View battery statistics"));
		grid_backup_tools.attach(btn_battery_monitor, 1, row, 1, 1);

		string path = get_cmd_path("aptik-bmon-gtk");
		btn_battery_monitor.sensitive = (path != null) && (path.length > 0);

		btn_battery_monitor.clicked.connect(() => {
			Posix.system("aptik-bmon-gtk");
		});
		/*
				//btn_mount_manager
			 	var btn_mount_manager = new Gtk.Button.with_label (" " + _("Mount Manager") + " ");
				btn_mount_manager.set_size_request(button_width,button_height);
				btn_mount_manager.set_tooltip_text(_("Add &amp; Remove Software Packages"));
				grid_backup_tools.attach(btn_mount_manager,1,row,1,1);


				//btn_ssd_tweaks
			 	var btn_ssd_tweaks = new Gtk.Button.with_label (" " + _("SSD Tweaks") + " ");
				btn_ssd_tweaks.set_size_request(button_width,button_height);
				btn_ssd_tweaks.set_tooltip_text(_("Add &amp; Remove Software Packages"));
				grid_backup_tools.attach(btn_ssd_tweaks,2,row,1,1);

				//btn_icon_explorer
			 	var btn_icon_explorer = new Gtk.Button.with_label (" " + _("Icon Explorer") + " ");
				btn_icon_explorer.set_size_request(button_width,button_height);
				btn_icon_explorer.set_tooltip_text(_("Add &amp; Remove Software Packages"));
				grid_backup_tools.attach(btn_icon_explorer,0,++row,1,1);

				//btn_brightness_fix
				var btn_brightness_fix = new Gtk.Button.with_label (" " + _("Brightness Fix") + " ");
				btn_brightness_fix.set_size_request(button_width,button_height);
				btn_brightness_fix.set_tooltip_text(_("Fix for maintaining display brightness level after reboot"));
				grid_backup_tools.attach(btn_brightness_fix,0,++row,1,1);
				*/
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
		//toolbar_bottom
		toolbar_bottom = new Gtk.Toolbar();
		toolbar_bottom.toolbar_style = ToolbarStyle.BOTH;
		toolbar_bottom.margin_top = 24;
		vbox_main.add(toolbar_bottom);

		//separator
		var separator = new Gtk.SeparatorToolItem();
		separator.set_draw (false);
		separator.set_expand (true);
		toolbar_bottom.add(separator);

		//btn_donate
		btn_donate = new Gtk.ToolButton.from_stock ("gtk-missing-image");
		btn_donate.label = _("Donate");
		btn_donate.set_tooltip_text (_("Donate"));
		btn_donate.icon_widget = get_shared_icon("donate", "donate.svg", 32);
		toolbar_bottom.add(btn_donate);

		btn_donate.clicked.connect(() => {
			var dialog = new DonationWindow();
			dialog.set_transient_for(this);
			dialog.show_all();
			dialog.run();
			dialog.destroy();
		});

		//btn_about
		btn_about = new Gtk.ToolButton.from_stock ("gtk-about");
		btn_about.label = _("About");
		btn_about.set_tooltip_text (_("Application Info"));
		btn_about.icon_widget = get_shared_icon("", "help-info.svg", 32);
		toolbar_bottom.add(btn_about);

		btn_about.clicked.connect (btn_about_clicked);
	}

	private void btn_about_clicked () {
		var dialog = new AboutWindow();
		dialog.set_transient_for (this);

		dialog.authors = {
			"Tony George:teejeetech@gmail.com"
		};

		dialog.translators = {
			"giulux (Italian)",
			"Jorge Jamhour (Brazilian Portuguese):https://launchpad.net/~jorge-jamhour",
			"B. W. Knight (Korean):https://launchpad.net/~kbd0651",
			"Rodion R. (Russian):https://launchpad.net/~r0di0n"
		};

		dialog.documenters = null;
		dialog.artists = null;
		dialog.donations = null;

		dialog.program_name = AppName;
		dialog.comments = _("System migration toolkit for Ubuntu-based distributions");
		dialog.copyright = "Copyright © 2014 Tony George (%s)".printf(AppAuthorEmail);
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
			string msg = _("Please select the backup directory");
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
		
		string message = _("Preparing") + "...";
		var dlg = new ProgressWindow.with_parent(this,message);
		dlg.show_all();
		gtk_do_events();

		App.backup_apt_cache();
		while (App.is_running) {
			dlg.update_progress(_("Copying"));
		}

		//finish ----------------------------------
		message = _("Finished") + " - ";
		message += _("%ld packages in backup").printf(get_file_count(archives_dir));
		dlg.finish(message);
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

		string message = _("Preparing") + "...";
		var dlg = new ProgressWindow.with_parent(this,message);
		dlg.show_all();
		gtk_do_events();

		App.restore_apt_cache();
		while (App.is_running) {
			dlg.update_progress(_("Copying"));
		}

		//finish ----------------------------------
		message = _("Finished") + " - ";
		message += _("%ld packages in cache").printf(get_file_count("/var/cache/apt/archives") - 2); //excluding 'lock' and 'partial'
		dlg.finish(message);
		gtk_do_events();
	}

	/* Misc */

	private void btn_take_ownership_clicked() {
		string title = _("Change Ownership");
		string msg = _("Owner will be changed to '%s' (uid=%d) for files in directory '%s'").printf(App.user_login, App.user_uid, App.user_home);
		msg += "\n\n" + _("Continue?");

		var dlg = new Gtk.MessageDialog.with_markup(null, Gtk.DialogFlags.MODAL, Gtk.MessageType.QUESTION, Gtk.ButtonsType.YES_NO, msg);
		dlg.set_title(title);
		dlg.set_default_size (200, -1);
		dlg.set_transient_for(this);
		dlg.set_modal(true);
		int response = dlg.run();
		dlg.destroy();
		gtk_do_events();

		if (response == Gtk.ResponseType.YES) {
			gtk_set_busy(true, this);

			bool is_success = App.take_ownership();
			if (is_success) {
				title = _("Success");
				msg = _("You are now the owner of all files in your home directory");
				gtk_messagebox(title, msg, this, false);
			}
			else {
				title = _("Error");
				msg = _("Failed to change file ownership");
				gtk_messagebox(title, msg, this, true);
			}

			gtk_set_busy(false, this);
		}
	}
}


