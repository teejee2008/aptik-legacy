/*
 * ConfigWindow.vala
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

public class ConfigWindow : Window {
	private Gtk.Box vbox_main;

	private Button btn_restore;
	private Button btn_reset; //TODO: Rename to 'delete'
	private Button btn_backup;
	private Button btn_cancel;
	private Button btn_select_all;
	private Button btn_select_none;
	private TreeView tv_config;
	
	private Gee.ArrayList<AppConfig> config_list_user;
	
	private int def_width = 600;
	private int def_height = 500;
	private uint tmr_init = 0;
	//private bool is_running = false;
	private bool is_restore_view = false;

	// init
	
	public ConfigWindow.with_parent(Window parent, bool restore) {
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
			title = _("Restore Application Settings");
			
			btn_restore.show();
			btn_restore.visible = true;
			btn_reset.show();
			btn_reset.visible = true;
			
			restore_init();
		}
		else{
			title = _("Backup Application Settings");
			
			btn_backup.show();
			btn_backup.visible = true;

			backup_init();
		}

		return false;
	}

	private void init_treeview() {
		//tv_config
		tv_config = new TreeView();
		tv_config.get_selection().mode = SelectionMode.MULTIPLE;
		tv_config.headers_clickable = true;
		tv_config.set_rules_hint (true);
		//tv_config.set_tooltip_column(3);

		//sw_config
		ScrolledWindow sw_config = new ScrolledWindow(null, null);
		sw_config.set_shadow_type (ShadowType.ETCHED_IN);
		sw_config.add (tv_config);
		sw_config.expand = true;
		vbox_main.add(sw_config);

		//col_config_select ----------------------

		TreeViewColumn col_config_select = new TreeViewColumn();
		col_config_select.title = "";
		CellRendererToggle cell_config_select = new CellRendererToggle ();
		cell_config_select.activatable = true;
		col_config_select.pack_start (cell_config_select, false);
		tv_config.append_column(col_config_select);

		col_config_select.set_cell_data_func (cell_config_select, (cell_layout, cell, model, iter) => {
			bool selected;
			AppConfig config;
			model.get (iter, 0, out selected, 1, out config, -1);
			(cell as Gtk.CellRendererToggle).active = selected;
		});

		cell_config_select.toggled.connect((path) => {
			ListStore model = (ListStore)tv_config.model;
			bool selected;
			AppConfig config;
			TreeIter iter;

			model.get_iter_from_string (out iter, path);
			model.get (iter, 0, out selected);
			model.get (iter, 1, out config);
			model.set (iter, 0, !selected);
			config.is_selected = !selected;
		});

		//col_config_name ----------------------

		TreeViewColumn col_config_name = new TreeViewColumn();
		col_config_name.title = _("Path");
		col_config_name.resizable = true;
		col_config_name.min_width = 180;
		tv_config.append_column(col_config_name);

		CellRendererText cell_config_name = new CellRendererText ();
		cell_config_name.ellipsize = Pango.EllipsizeMode.END;
		col_config_name.pack_start (cell_config_name, false);

		col_config_name.set_cell_data_func (cell_config_name, (cell_layout, cell, model, iter) => {
			AppConfig config;
			model.get (iter, 1, out config, -1);
			(cell as Gtk.CellRendererText).text = config.name;
		});

		TreeViewColumn col_config_size = new TreeViewColumn();
		col_config_size.title = _("Size");
		col_config_size.resizable = true;
		tv_config.append_column(col_config_size);

		CellRendererText cell_config_size = new CellRendererText ();
		cell_config_size.xalign = (float) 1.0;
		col_config_size.pack_start (cell_config_size, false);

		col_config_size.set_cell_data_func (cell_config_size, (cell_layout, cell, model, iter) => {
			AppConfig config;
			model.get (iter, 1, out config, -1);
			(cell as Gtk.CellRendererText).text = config.size;
			if (config.size.contains("M") || config.size.contains("G")) {
				(cell as Gtk.CellRendererText).foreground = "red";
			}
			else {
				(cell as Gtk.CellRendererText).foreground = null;
			}
		});

		//col_config_desc ----------------------

		TreeViewColumn col_config_desc = new TreeViewColumn();
		col_config_desc.title = _("Description");
		col_config_desc.resizable = true;
		tv_config.append_column(col_config_desc);

		CellRendererText cell_config_desc = new CellRendererText ();
		cell_config_desc.ellipsize = Pango.EllipsizeMode.END;
		col_config_desc.pack_start (cell_config_desc, false);

		col_config_desc.set_cell_data_func (cell_config_desc, (cell_layout, cell, model, iter) => {
			AppConfig config;
			model.get (iter, 1, out config, -1);
			(cell as Gtk.CellRendererText).text = config.description;
		});
	}

	private void init_actions() {
		//hbox_config_actions
		Box hbox_config_actions = new Box (Orientation.HORIZONTAL, 6);
		vbox_main.add (hbox_config_actions);

		//btn_select_all
		btn_select_all = new Gtk.Button.with_label (" " + _("Select All") + " ");
		hbox_config_actions.pack_start (btn_select_all, true, true, 0);
		btn_select_all.clicked.connect(() => {
			foreach(AppConfig config in config_list_user) {
				config.is_selected = true;
			}
			tv_config_refresh();
		});

		//btn_select_none
		btn_select_none = new Gtk.Button.with_label (" " + _("Select None") + " ");
		hbox_config_actions.pack_start (btn_select_none, true, true, 0);
		btn_select_none.clicked.connect(() => {
			foreach(AppConfig config in config_list_user) {
				config.is_selected = false;
			}
			tv_config_refresh();
		});

		//btn_backup
		btn_backup = new Gtk.Button.with_label (" <b>" + _("Backup") + "</b> ");
		btn_backup.no_show_all = true;
		hbox_config_actions.pack_start (btn_backup, true, true, 0);
		btn_backup.clicked.connect(btn_backup_clicked);

		//btn_restore
		btn_restore = new Gtk.Button.with_label (" <b>" + _("Restore") + "</b> ");
		btn_restore.no_show_all = true;
		btn_restore.set_tooltip_text(_("Restore the settings for an application (Eg: Chromium Browser) by replacing the settings directory (~/.config/chromium) with files from backup. Use the 'Reset' button to delete the restored files in case of issues."));
		hbox_config_actions.pack_start (btn_restore, true, true, 0);
		btn_restore.clicked.connect(btn_restore_clicked);

		//btn_reset
		btn_reset = new Gtk.Button.with_label (" " + _("Reset") + " ");
		btn_reset.no_show_all = true;
		btn_reset.set_tooltip_text(_("Reset the settings for an application (Eg: Chromium Browser) by deleting the settings directory (~/.config/chromium). The directory will be created automatically with default configuration files on the next run of the application."));
		hbox_config_actions.pack_start (btn_reset, true, true, 0);
		btn_reset.clicked.connect(btn_reset_clicked);

		//btn_cancel
		btn_cancel = new Gtk.Button.with_label (" " + _("Cancel") + " ");
		hbox_config_actions.pack_start (btn_cancel, true, true, 0);
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

	private void tv_config_refresh() {
		ListStore model = new ListStore(2, typeof(bool), typeof(AppConfig));
		tv_config.model = model;

		foreach(AppConfig entry in config_list_user) {
			TreeIter iter;
			model.append(out iter);
			model.set (iter, 0, entry.is_selected, 1, entry, -1);
		}
	}

	// backup

	private void backup_init() {
		gtk_set_busy(true, this);

		config_list_user = App.list_app_config_directories_from_home();
		tv_config_refresh();

		gtk_set_busy(false, this);
	}

	private void btn_backup_clicked() {
		//check if no action required
		bool none_selected = true;
		foreach(AppConfig config in config_list_user) {
			if (config.is_selected) {
				none_selected = false;
				break;
			}
		}
		if (none_selected) {
			string title = _("No Directories Selected");
			string msg = _("Select the directories to backup");
			gtk_messagebox(title, msg, this, false);
			return;
		}

		//begin
		string message = _("Preparing") + "...";

		var dlg = new ProgressWindow.with_parent(this,message);
		dlg.show_all();
		gtk_do_events();

		//backup
		App.backup_app_settings_init(config_list_user);
		
		foreach(AppConfig config in config_list_user){
			if (!config.is_selected) { continue; }
			
			App.backup_app_settings_single(config);
			while (App.is_running) {
				dlg.update_progress(_("Archiving"));
			}
		}

		//finish ----------------------------------

		//string title = _("Finished");
		//string msg = _("Backups created successfully");
		//gtk_messagebox(title, msg, this, false);

		dlg.close();
		//this.close();
		gtk_do_events();
	}

	// restore
	
	private void restore_init() {
		gtk_set_busy(true, this);

		config_list_user = App.list_app_config_directories_from_backup();
		tv_config_refresh();

		gtk_set_busy(false, this);
	}

	private void btn_restore_clicked() {
		//check if no action required
		bool none_selected = true;
		foreach(AppConfig conf in config_list_user) {
			if (conf.is_selected) {
				none_selected = false;
				break;
			}
		}
		if (none_selected) {
			string title = _("Nothing To Do");
			string msg = _("Please select the directories to restore");
			gtk_messagebox(title, msg, this, false);
			return;
		}

		//prompt for confirmation
		string title = _("Warning");
		string msg = _("Selected directories will be replaced with files from backup.") + "\n" + ("Do you want to continue?");
		var dlg2 = new Gtk.MessageDialog.with_markup(null, Gtk.DialogFlags.MODAL, Gtk.MessageType.QUESTION, Gtk.ButtonsType.YES_NO, msg);
		dlg2.set_title(title);
		dlg2.set_default_size (200, -1);
		dlg2.set_transient_for(this);
		dlg2.set_modal(true);
		int response = dlg2.run();
		dlg2.destroy();

		if (response == Gtk.ResponseType.NO) {
			//progress_hide("Cancelled");
			return;
		}

		//begin
		string message = _("Preparing") + "...";
		var dlg = new ProgressWindow.with_parent(this,message);
		dlg.show_all();
		gtk_do_events();
		
		//extract
		App.restore_app_settings_init(config_list_user);

		foreach(AppConfig config in config_list_user){
			if (!config.is_selected) { continue; }
			
			App.restore_app_settings_single(config);
			while (App.is_running) {
				dlg.update_progress(_("Extracting"));
			}
		}

		//update ownership
		dlg.update_progress(_("Updating file ownership") + "...");
		App.update_ownership(config_list_user);

		//finish ----------------------------------

		//title = _("Finished");
		//msg = _("Application settings restored successfully");
		//gtk_messagebox(title, msg, this, false);

		dlg.close();
		//this.close();
		gtk_do_events();
	}

	//reset

	private void btn_reset_clicked() {
		//check if no action required
		bool none_selected = true;
		foreach(AppConfig conf in config_list_user) {
			if (conf.is_selected) {
				none_selected = false;
				break;
			}
		}
		if (none_selected) {
			string title = _("Nothing To Do");
			string msg = _("Please select the directories to reset");
			gtk_messagebox(title, msg, this, false);
			return;
		}

		//prompt for confirmation
		string title = _("Warning");
		string msg = _("Selected directories will be deleted.") + "\n" + ("Do you want to continue?");
		var dlg2 = new Gtk.MessageDialog.with_markup(null, Gtk.DialogFlags.MODAL, Gtk.MessageType.QUESTION, Gtk.ButtonsType.YES_NO, msg);
		dlg2.set_title(title);
		dlg2.set_default_size (200, -1);
		dlg2.set_transient_for(this);
		dlg2.set_modal(true);
		int response = dlg2.run();
		dlg2.destroy();

		if (response == Gtk.ResponseType.NO) {
			//progress_hide("Cancelled");
			return;
		}

		//begin
		string message = _("Preparing") + "...";
		var dlg = new ProgressWindow.with_parent(this,message);
		dlg.show_all();
		gtk_do_events();
		
		//extract
		App.reset_app_settings(config_list_user);
		while (App.is_running) {
			dlg.update_progress(_("Deleting"));
		}

		//finish

		//title = _("Finished");
		//msg = _("Selected directories were deleted successfully");
		//gtk_messagebox(title, msg, this, false);

		//show_home_page();

		dlg.close();
		//this.close();
		gtk_do_events();
	}
}


