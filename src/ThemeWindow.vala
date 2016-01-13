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

	private Button btn_restore;
	private Button btn_backup;
	private Button btn_cancel;
	private Button btn_select_all;
	private Button btn_select_none;
	
	private TreeView tv_theme;
	private TreeViewColumn col_theme_status;
	private ScrolledWindow sw_theme;

	private Gee.ArrayList<Theme> theme_list_user;
	
	private int def_width = 550;
	private int def_height = 450;
	private uint tmr_init = 0;
	//private bool is_running = false;
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
		title = AppName + " v" + AppVersion;
		window_position = WindowPosition.CENTER;
		set_default_size (def_width, def_height);
		resizable = true;
		deletable = true;
		
		//vbox_main
		vbox_main = new Box (Orientation.VERTICAL, 6);
		vbox_main.margin = 6;
		add (vbox_main);

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

		if (is_restore_view){
			title = _("Restore Themes");
			
			btn_restore.show();
			btn_restore.visible = true;

			restore_init();
		}
		else{
			title = _("Backup Themes");
			
			btn_backup.show();
			btn_backup.visible = true;

			backup_init();
		}

		return false;
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
			ListStore model = (ListStore)tv_theme.model;
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
		col_theme_name.min_width = 180;
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
		col_theme_desc.title = _("Path");
		col_theme_desc.resizable = true;
		tv_theme.append_column(col_theme_desc);

		CellRendererText cell_theme_desc = new CellRendererText ();
		cell_theme_desc.ellipsize = Pango.EllipsizeMode.END;
		col_theme_desc.pack_start (cell_theme_desc, false);

		col_theme_desc.set_cell_data_func (cell_theme_desc, (cell_layout, cell, model, iter) => {
			Theme theme;
			model.get (iter, 1, out theme, -1);
			(cell as Gtk.CellRendererText).text = (theme.zip_file_path.length > 0) ? theme.zip_file_path : theme.system_path;
		});
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
		btn_cancel = new Gtk.Button.with_label (" " + _("Cancel") + " ");
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

	// events

	private void tv_theme_refresh() {
		ListStore model = new ListStore(4, typeof(bool), typeof(Theme), typeof(Gdk.Pixbuf), typeof(string));

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

		TreeIter iter;
		string tt = "";
		foreach(Theme theme in theme_list_user) {
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

	// backup

	private void backup_init() {
		gtk_set_busy(true, this);

		theme_list_user = App.list_all_themes();
		tv_theme_refresh();

		gtk_set_busy(false, this);
	}

	private void btn_backup_clicked() {
		//check if no action required
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

		string message = _("Preparing") + "...";

		var dlg = new ProgressWindow.with_parent(this, message);
		dlg.show_all();
		gtk_do_events();
		
		//get total file count
		App.progress_total = 0;
		App.progress_count = 0;
		foreach(Theme theme in theme_list_user) {
			if (theme.is_selected) {
				App.progress_total += (int) get_file_count(theme.system_path);
			}
		}
		
		//zip themes
		foreach(Theme theme in theme_list_user) {
			if (theme.is_selected) {
				App.zip_theme(theme);
				while (App.is_running) {
					dlg.update_progress(_("Archiving"));
				}
			}
		}

		//finish ----------------------------------
		message = _("Backups created successfully");
		dlg.finish(message);
		gtk_do_events();
	}

	// restore
	
	private void restore_init() {
		gtk_set_busy(true, this);

		theme_list_user = App.get_all_themes_from_backup();
		tv_theme_refresh();

		gtk_set_busy(false, this);
	}

	private void btn_restore_clicked() {
		//check if no action required
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

		//begin
		string message = _("Preparing") + "...";
		var dlg = new ProgressWindow.with_parent(this, message);
		dlg.show_all();
		gtk_do_events();

		//get total file count
		App.progress_total = 0;
		App.progress_count = 0;
		foreach(Theme theme in theme_list_user) {
			if (theme.is_selected && !theme.is_installed) {
				string cmd = "tar tvf '%s'".printf(theme.zip_file_path);
				string txt = execute_command_sync_get_output(cmd);
				App.progress_total += txt.split("\n").length;
			}
		}

		//unzip themes
		foreach(Theme theme in theme_list_user) {
			if (theme.is_selected && !theme.is_installed) {
				App.unzip_theme(theme);
				while (App.is_running) {
					dlg.update_progress(_("Extracting"));
				}
				App.update_permissions(theme.system_path);
			}
		}

		//finish ----------------------------------
		message = _("Themes restored successfully");
		dlg.finish(message);
		gtk_do_events();
	}
}


