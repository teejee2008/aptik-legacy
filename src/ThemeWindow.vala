/*
 * ThemeWindow.vala
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

public class ThemeWindow : Window {
	private Gtk.Box vbox_main;
	private Gtk.Expander expander;
	
	private Button btn_restore;
	private Button btn_backup;
	private Button btn_cancel;
	private Button btn_select_all;
	private Button btn_select_none;
	
	private TreeView tv_theme;
	private TreeViewColumn col_theme_status;
	private ScrolledWindow sw_theme;
	
	private Gtk.ComboBox cmb_username;
	private Gtk.ComboBox cmb_type;
	private Gtk.Box hbox_filter;
	//private Gtk.Label lbl_theme_dir;
	
	private Gee.ArrayList<Theme> theme_list_user;
	
	private int def_width = 550;
	private int def_height = 450;
	private uint tmr_init = 0;
	private bool is_running = false;
	private bool is_restore_view = false;

	// init
	
	public ThemeWindow.with_parent(Window parent, bool restore) {
		set_transient_for(parent);
		set_modal(true);
		is_restore_view = restore;

		destroy.connect(()=>{
			parent.present();
		});
		
		init_window();
	}

	public void init_window () {
		//title = AppName + " v" + AppVersion;
		window_position = WindowPosition.CENTER;
		set_default_size (def_width, def_height);
		icon = get_app_icon(16);
		resizable = true;
		deletable = true;

		//vbox_main
		vbox_main = new Box (Orientation.VERTICAL, 6);
		vbox_main.margin = 6;
		add (vbox_main);

		init_filters();

		//treeview
		init_treeview();

		//buttons
		init_actions();
		
		show_all();

		tmr_init = Timeout.add(100, init_delayed);
	}

	private bool init_delayed() {
		/* any actions that need to run after window has been displayed */
		if (tmr_init > 0) {
			Source.remove(tmr_init);
			tmr_init = 0;
		}

		cmb_username_refresh();
		cmb_type_refresh();
		
		if (is_restore_view){
			title = _("Restore");
			col_theme_status.visible = true;
			
			btn_restore.show();
			btn_restore.visible = true;

			restore_init();
		}
		else{
			title = _("Backup");
			col_theme_status.visible = false;
			
			btn_backup.show();
			btn_backup.visible = true;

			//backup_init(); // will be trigerred by cmb_username_refresh()
		}

		return false;
	}

	private void init_filters(){
		expander = new Gtk.Expander(_("Advanced"));
		expander.use_markup = true;
		expander.expanded = false;
		vbox_main.add (expander);

		init_username();
		init_type();
	}
	
	private void init_username(){
		//hbox_filter
		hbox_filter = new Box (Orientation.HORIZONTAL, 6);
		hbox_filter.margin_left = 3;
		hbox_filter.margin_right = 3;
		expander.add(hbox_filter);

		//filter
		Label lbl_filter = new Label(_("Username"));
		hbox_filter.add (lbl_filter);
		
		//cmb_username
		cmb_username = new ComboBox();
		cmb_username.set_tooltip_text(_("Username"));
		hbox_filter.add (cmb_username);

		if (is_restore_view){
			lbl_filter.label = _("Restore for:");
		}
		else{
			lbl_filter.label = _("User:");
		}

		CellRendererText cell_username = new CellRendererText();
		cmb_username.pack_start(cell_username, false );
		cmb_username.set_cell_data_func (cell_username, (cell_username, cell, model, iter) => {
			string username;
			model.get (iter, 0, out username, -1);
			(cell as Gtk.CellRendererText).text = username;
		});

		cmb_username.changed.connect(()=>{
			App.select_user(gtk_combobox_get_value(cmb_username,1,"(all)"));
			
			if (is_restore_view){
				foreach(Theme theme in theme_list_user){
					theme.check_installed(App.user_login);
					theme.is_selected = !theme.is_installed;
				}
				tv_theme_refresh();
			}
			else{
				backup_init();
			}
		});

		/*var img = get_shared_icon("gtk-info","help-info.svg",16);
		img.margin_left = 6;
		hbox_filter.add (img);

		if (is_restore_view){
			var msg = _("Selecting 'All Users' will install files to '/usr/share/themes' and will be available to all users. They cannot be edited or deleted by non-admin users.\n\nSelecting a specific user will install files to the user's home directory (~/.themes and ~/.icons) which allows the user to edit and delete the theme. If the user applies a theme that is installed only for the user then some applications (executed at startup or as admin) may look ugly since the theme is not available to other users.");
			
			img.set_tooltip_markup(msg);
			cmb_username.set_tooltip_markup(msg);
		}
		else{
			var msg = _("<b>All Users</b> - List themes in /usr/share/themes and /usr/share/icons which are available for all users\n\n<b>&lt;user&gt;</b> - List themes in user's home directory (~/.themes and ~/.icons)");

			img.set_tooltip_markup(msg);
			cmb_username.set_tooltip_markup(msg);
		}*/
	}
	
	private void cmb_username_refresh() {
		var store = new Gtk.ListStore(2, typeof (string), typeof (string));;
		TreeIter iter;

		int selected = 0;
		int index = -1;

		index++;
		store.append(out iter);
		store.set (iter, 0, _("All Users"), 1, "(all)", -1);
		
		index++;
		store.append(out iter);
		store.set (iter, 0, _("root"), 1, "root", -1);
		
		foreach (string username in list_dir_names("/home")) {
			if (username == "PinguyBuilder"){
				continue;
			}
			
			index++;
			store.append(out iter);
			store.set (iter, 0, username, 1, username, -1);

			if (App.user_login == username){
				selected = index;
			}
		}
		
		cmb_username.set_model (store);
		cmb_username.active = 0;
	}

	private void init_type(){
		//label
		var lbl_type = new Label(_("Theme Type"));
		hbox_filter.add (lbl_type);
		
		//cmb_username
		cmb_type = new ComboBox();
		cmb_type.set_tooltip_text(_("Type of theme to display"));
		hbox_filter.add (cmb_type);

		/*if (is_restore_view){
			lbl_filter.label = _("Restore themes for:");
		}
		else{
			lbl_filter.label = _("Show installed themes for:");
		}*/

		CellRendererText cell_text = new CellRendererText();
		cmb_type.pack_start(cell_text, false );
		cmb_type.set_cell_data_func (cell_text, (cell_text, cell, model, iter) => {
			string type;
			model.get (iter, 0, out type, -1);
			(cell as Gtk.CellRendererText).text = type;
		});

		cmb_type.changed.connect(()=>{
			tv_theme_refresh();
		});
	}

	private void cmb_type_refresh() {
		var store = new Gtk.ListStore(2, typeof (string), typeof (Theme.ThemeType));
		TreeIter iter;

		store.append(out iter);
		store.set (iter, 0, _("All Types"), 1, Theme.ThemeType.ALL, -1);
		
		store.append(out iter);
		store.set (iter, 0, _("Icons"), 1, Theme.ThemeType.ICON, -1);
		
		store.append(out iter);
		store.set (iter, 0, _("Cursors"), 1, Theme.ThemeType.CURSOR, -1);
		
		store.append(out iter);
		store.set (iter, 0, _("GTK-2"), 1, Theme.ThemeType.GTK20, -1);
		
		store.append(out iter);
		store.set (iter, 0, _("GTK-3"), 1, Theme.ThemeType.GTK30, -1);
		
		store.append(out iter);
		store.set (iter, 0, _("Gnome Shell"), 1, Theme.ThemeType.GNOMESHELL, -1);
		
		store.append(out iter);
		store.set (iter, 0, _("Unity Shell"), 1, Theme.ThemeType.UNITY, -1);
		
		store.append(out iter);
		store.set (iter, 0, _("Cinnamon Shell"), 1, Theme.ThemeType.CINNAMON, -1);
		
		store.append(out iter);
		store.set (iter, 0, _("Metacity Window Border"), 1, Theme.ThemeType.METACITY1, -1);
		
		store.append(out iter);
		store.set (iter, 0, _("XFCE Window Border"), 1, Theme.ThemeType.XFWM4, -1);
		
		store.append(out iter);
		store.set (iter, 0, _("XFCE Notification"), 1, Theme.ThemeType.XFCENOTIFY40, -1);
		
		cmb_type.set_model (store);
		cmb_type.active = 0;
	}


	private void init_treeview() {
		//tv_theme
		tv_theme = new TreeView();
		tv_theme.get_selection().mode = SelectionMode.MULTIPLE;
		tv_theme.headers_clickable = true;
		tv_theme.set_rules_hint (true);
		tv_theme.set_tooltip_column(3);

		//sw_theme
		sw_theme = new ScrolledWindow(null, null);
		sw_theme.set_shadow_type (ShadowType.ETCHED_IN);
		sw_theme.add (tv_theme);
		sw_theme.expand = true;
		vbox_main.add(sw_theme);

		//col_theme_select ----------------------

		TreeViewColumn col_theme_select = new TreeViewColumn();
		col_theme_select.title = "";
		CellRendererToggle cell_theme_select = new CellRendererToggle ();
		cell_theme_select.activatable = true;
		col_theme_select.pack_start (cell_theme_select, false);
		tv_theme.append_column(col_theme_select);

		col_theme_select.set_cell_data_func (cell_theme_select, (cell_layout, cell, model, iter) => {
			bool selected;
			Theme theme;
			model.get (iter, 0, out selected, 1, out theme, -1);
			(cell as Gtk.CellRendererToggle).active = selected;
			(cell as Gtk.CellRendererToggle).sensitive = !is_restore_view || !theme.is_installed;
		});

		cell_theme_select.toggled.connect((path) => {
			var model = (Gtk.ListStore)tv_theme.model;
			bool selected;
			Theme theme;
			TreeIter iter;

			model.get_iter_from_string (out iter, path);
			model.get (iter, 0, out selected);
			model.get (iter, 1, out theme);
			model.set (iter, 0, !selected);
			theme.is_selected = !selected;
		});

		//col_theme_status ----------------------

		col_theme_status = new TreeViewColumn();
		//col_theme_status.title = _("");
		col_theme_status.resizable = true;
		tv_theme.append_column(col_theme_status);
		
		CellRendererPixbuf cell_theme_status = new CellRendererPixbuf ();
		col_theme_status.pack_start (cell_theme_status, false);
		col_theme_status.set_attributes(cell_theme_status, "pixbuf", 2);

		//col_theme_name ----------------------

		TreeViewColumn col_theme_name = new TreeViewColumn();
		col_theme_name.title = _("Theme");
		col_theme_name.resizable = true;
		col_theme_name.min_width = 150;
		tv_theme.append_column(col_theme_name);

		CellRendererText cell_theme_name = new CellRendererText ();
		cell_theme_name.ellipsize = Pango.EllipsizeMode.END;
		col_theme_name.pack_start (cell_theme_name, false);

		col_theme_name.set_cell_data_func (cell_theme_name, (cell_layout, cell, model, iter) => {
			Theme theme;
			model.get (iter, 1, out theme, -1);
			(cell as Gtk.CellRendererText).text = theme.name;
		});

		//col_theme_desc ----------------------

		TreeViewColumn col_theme_desc = new TreeViewColumn();
		col_theme_desc.resizable = true;
		col_theme_desc.min_width = 150;
		tv_theme.append_column(col_theme_desc);
		
		if (is_restore_view) {
			col_theme_desc.title = _("Backup File");
		}
		else{
			col_theme_desc.title = _("System Path");
		}

		CellRendererText cell_theme_desc = new CellRendererText ();
		cell_theme_desc.ellipsize = Pango.EllipsizeMode.END;
		col_theme_desc.pack_start (cell_theme_desc, false);

		col_theme_desc.set_cell_data_func (cell_theme_desc, (cell_layout, cell, model, iter) => {
			Theme theme;
			model.get (iter, 1, out theme, -1);
			(cell as Gtk.CellRendererText).text = (theme.archive_path.length > 0) ? theme.archive_path : theme.theme_dir_path;
		});
		
		
		//col_types ----------------------

		var col_types = new TreeViewColumn();
		col_types.title = _("Includes");
		col_types.resizable = true;
		col_types.min_width = 150;
		tv_theme.append_column(col_types);
		
		var cell_text = new CellRendererText ();
		cell_text.ellipsize = Pango.EllipsizeMode.END;
		col_types.pack_start (cell_text, false);

		col_types.set_cell_data_func (cell_text, (cell_layout, cell, model, iter) => {
			Theme theme;
			model.get (iter, 1, out theme, -1);
			(cell as Gtk.CellRendererText).text = theme.type_desc;
		});
	}

	private void tv_theme_refresh() {
		var model = new Gtk.ListStore(4, typeof(bool), typeof(Theme), typeof(Gdk.Pixbuf), typeof(string));

		//status icons
		Gdk.Pixbuf pix_enabled = null;
		Gdk.Pixbuf pix_missing = null;
		Gdk.Pixbuf pix_status = null;

		try {
			pix_enabled = new Gdk.Pixbuf.from_file (App.share_dir + "/aptik/images/item-green.png");
			pix_missing = new Gdk.Pixbuf.from_file (App.share_dir + "/aptik/images/item-gray.png");
		}
		catch (Error e) {
			log_error (e.message);
		}
		
		var theme_type = gtk_combobox_get_value_enum(cmb_type, 1, Theme.ThemeType.ALL);

		TreeIter iter;
		string tt = "";
		foreach(Theme theme in theme_list_user) {
			if ((theme_type != Theme.ThemeType.ALL) && (!theme.type_list.contains((Theme.ThemeType)theme_type))){
				continue;
			}
			
			//check status
			if (theme.is_installed) {
				pix_status = pix_enabled;
				tt = _("Installed");
			}
			else {
				pix_status = pix_missing;
				tt = _("Not Installed");
			}

			//add row
			model.append(out iter);
			model.set (iter, 0, theme.is_selected);
			model.set (iter, 1, theme);
			model.set (iter, 2, pix_status);
			model.set (iter, 3, tt);
		}

		tv_theme.set_model(model);
		tv_theme.columns_autosize();
	}


	private void init_actions() {
		//hbox_theme_actions
		Box hbox_theme_actions = new Box (Orientation.HORIZONTAL, 6);
		vbox_main.add (hbox_theme_actions);

		//btn_select_all
		btn_select_all = new Gtk.Button.with_label (" " + _("Select All") + " ");
		hbox_theme_actions.pack_start (btn_select_all, true, true, 0);
		btn_select_all.clicked.connect(() => {
			foreach(Theme theme in theme_list_user) {
				if (is_restore_view) {
					if (!theme.is_installed) {
						theme.is_selected = true;
					}
					else {
						//no change
					}
				}
				else {
					theme.is_selected = true;
				}
			}
			tv_theme_refresh();
		});

		//btn_select_none
		btn_select_none = new Gtk.Button.with_label (" " + _("Select None") + " ");
		hbox_theme_actions.pack_start (btn_select_none, true, true, 0);
		btn_select_none.clicked.connect(() => {
			foreach(Theme theme in theme_list_user) {
				if (is_restore_view) {
					if (!theme.is_installed) {
						theme.is_selected = false;
					}
					else {
						//no change
					}
				}
				else {
					theme.is_selected = false;
				}
			}
			tv_theme_refresh();
		});

		//btn_backup
		btn_backup = new Gtk.Button.with_label (" <b>" + _("Backup") + "</b> ");
		btn_backup.no_show_all = true;
		hbox_theme_actions.pack_start (btn_backup, true, true, 0);
		btn_backup.clicked.connect(btn_backup_clicked);

		//btn_restore
		btn_restore = new Gtk.Button.with_label (" <b>" + _("Restore") + "</b> ");
		btn_restore.no_show_all = true;
		hbox_theme_actions.pack_start (btn_restore, true, true, 0);
		btn_restore.clicked.connect(btn_restore_clicked);

		//btn_cancel
		btn_cancel = new Gtk.Button.with_label (" " + _("Close") + " ");
		hbox_theme_actions.pack_start (btn_cancel, true, true, 0);
		btn_cancel.clicked.connect(() => {
			this.close();
		});
	
		set_bold_font_for_buttons();
	}

	private void set_bold_font_for_buttons() {
		//set bold font for some buttons
		foreach(Button btn in new Button[] { btn_backup, btn_restore }) {
			foreach(Widget widget in btn.get_children()) {
				if (widget is Label) {
					Label lbl = (Label)widget;
					lbl.set_markup(lbl.label);
				}
			}
		}
	}

	// backup

	private void backup_init() {
		gtk_set_busy(true, this);

		Theme.load_index(App.backup_dir);
		
		string username = App.all_users ? "" : App.user_login;
		theme_list_user = Theme.list_themes_installed(username);
		
		tv_theme_refresh();

		Theme.save_index(theme_list_user, App.backup_dir);
		
		gtk_set_busy(false, this);
	}
	
	private void btn_backup_clicked() {
		// check if no action required ----------------------
		
		bool none_selected = true;
		foreach(Theme theme in theme_list_user) {
			if (theme.is_selected) {
				none_selected = false;
				break;
			}
		}
		if (none_selected) {
			string title = _("No Themes Selected");
			string msg = _("Select the themes to backup");
			gtk_messagebox(title, msg, this, false);
			return;
		}

		string message = _("Preparing...");

		var dlg = new ProgressWindow.with_parent(this, message, true);
		dlg.show_all();
		gtk_do_events();
		
		// get total file count -------------------------------
		
		App.progress_total = 0;
		App.progress_count = 0;
		foreach(Theme theme in theme_list_user) {
			if (theme.is_selected) {
				App.progress_total += theme.progress_total;
			}
		}

		//dlg.pulse_start();
		dlg.update_message(_("Archiving..."));
		dlg.update_status_line(true);
		
		// zip themes --------------------------------------
		
		int64 count_temp = 0;
		foreach(Theme theme in theme_list_user) {
			if (App.cancelled){
				break;
			}
			
			if (theme.is_selected) {
				theme.zip(App.backup_dir, true);
				while (theme.is_running) {
					App.status_line = theme.status_line;
					App.progress_count = count_temp + theme.progress_count;
					dlg.update_progressbar();
					dlg.update_status_line();
					dlg.sleep(50);
				}
				count_temp += theme.progress_total;
			}
		}

		// finish ----------------------------------

		if (!App.cancelled){
			message = Message.BACKUP_OK;
			dlg.finish(message);
		}
		else{
			dlg.destroy();
		}
		
		gtk_do_events();
	}

	// restore
	
	private void restore_init() {
		
		// begin ---------------------------
		
		string message = _("Checking backups...");
		var dlg = new ProgressWindow.with_parent(this, message, true);
		dlg.show_all();
		gtk_do_events();

		Theme.load_index(App.backup_dir);
		
		// get total count ----------------------------
		
		App.progress_total = 0;
		App.progress_count = 0;
		foreach(string subdir in new string[] { "icons","themes" }){
			string base_dir = "%s%s".printf(App.backup_dir.has_suffix("/") ? App.backup_dir : App.backup_dir + "/", subdir);
			App.progress_total += get_file_count(base_dir);
		}

		try {
			is_running = true;
			Thread.create<void> (restore_init_thread, true);
		} catch (ThreadError e) {
			is_running = false;
			log_error (e.message);
		}

		while (is_running) {
			dlg.update_status_line();
			dlg.update_progressbar();
			dlg.sleep(200);
			gtk_do_events();
		}

		//finish ----------------------------------
		
		tv_theme_refresh();
		
		Theme.save_index(theme_list_user, App.backup_dir);
		
		dlg.destroy();
		gtk_do_events();
	}

	private void restore_init_thread() {
		theme_list_user = Theme.list_themes_archived(App.backup_dir);
		
		foreach(Theme theme in theme_list_user){
			theme.check_installed(App.user_login);
		}
		
		is_running = false;
	}
	
	private void btn_restore_clicked() {
		
		// check if no action required ----------------------------
		
		bool none_selected = true;
		foreach(Theme theme in theme_list_user) {
			if (theme.is_selected && !theme.is_installed) {
				none_selected = false;
				break;
			}
		}
		if (none_selected) {
			string title = _("Nothing To Do");
			string msg = _("Selected themes are already installed");
			gtk_messagebox(title, msg, this, false);
			return;
		}

		// begin ---------------------------------
		
		string message = _("Preparing...");
		var dlg = new ProgressWindow.with_parent(this, message, true);
		dlg.show_all();
		gtk_do_events();

		// get total file count ---------------------
		
		App.progress_total = 0;
		App.progress_count = 0;
		foreach(Theme theme in theme_list_user) {
			if (theme.is_selected && !theme.is_installed) {
				App.progress_total += theme.get_file_count_archived();
			}
		}

		dlg.update_message(_("Extracting..."));
		dlg.update_status_line(true);
		
		// unzip themes -----------------------
		
		int64 count_temp = 0;
		foreach(Theme theme in theme_list_user) {
			if (App.cancelled){
				break;
			}
			if (theme.is_selected && !theme.is_installed) {
				theme.unzip(App.user_login, true);
				while (theme.is_running) {
					App.status_line = theme.status_line;
					App.progress_count = count_temp + theme.progress_count;
					dlg.update_progressbar();
					dlg.update_status_line();
					dlg.sleep(50);
				}
				count_temp += theme.progress_total;
				
				theme.update_permissions();
				theme.update_ownership(App.user_login);
				
				theme.is_selected = false; 
			}
		}

		Theme.fix_nested_folders();

		// finish ----------------------------------
		
		if (!App.cancelled){
			foreach(Theme theme in theme_list_user){
				theme.check_installed(App.user_login);
			}
			
			tv_theme_refresh();

			message = Message.RESTORE_OK;
			dlg.finish(message);
		}
		else{
			dlg.destroy();
		}

		gtk_do_events();
	}
}


