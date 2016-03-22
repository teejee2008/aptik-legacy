/*
 * PpaWindow.vala
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

public class PpaWindow : Window {
	private Gtk.Box vbox_main;

	private Button btn_restore;
	private Button btn_backup;
	private Button btn_cancel;
	private Button btn_select_all;
	private Button btn_select_none;
	
	private TreeView tv_ppa;
	private TreeViewColumn col_ppa_status;
	private ScrolledWindow sw_ppa;

	private int def_width = 550;
	private int def_height = 450;
	private uint tmr_init = 0;
	private bool is_running = false;
	private bool is_restore_view = false;

	private bool skip_pkg_info_update = false;
	
	// init
	
	public PpaWindow.with_parent(Window parent, bool restore) {
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
			title = _("Restore Software Sources");
			
			btn_restore.show();
			btn_restore.visible = true;

			restore_init();
		}
		else{
			title = _("Backup Software Sources");
			
			btn_backup.show();
			btn_backup.visible = true;

			backup_init();
		}

		return false;
	}

	private void init_treeview() {
		//tv_ppa
		tv_ppa = new TreeView();
		tv_ppa.get_selection().mode = SelectionMode.MULTIPLE;
		tv_ppa.headers_clickable = true;
		tv_ppa.set_rules_hint (true);
		tv_ppa.set_tooltip_column(3);

		//sw_ppa
		sw_ppa = new ScrolledWindow(null, null);
		sw_ppa.set_shadow_type (ShadowType.ETCHED_IN);
		sw_ppa.add (tv_ppa);
		sw_ppa.expand = true;
		vbox_main.add(sw_ppa);

		//col_ppa_select ----------------------

		TreeViewColumn col_ppa_select = new TreeViewColumn();
		col_ppa_select.title = "";
		CellRendererToggle cell_ppa_select = new CellRendererToggle ();
		cell_ppa_select.activatable = true;
		col_ppa_select.pack_start (cell_ppa_select, false);
		tv_ppa.append_column(col_ppa_select);

		col_ppa_select.set_cell_data_func (cell_ppa_select, (cell_layout, cell, model, iter) => {
			bool selected;
			Ppa ppa;
			model.get (iter, 0, out selected, 1, out ppa, -1);
			(cell as Gtk.CellRendererToggle).active = selected;
			(cell as Gtk.CellRendererToggle).sensitive = !is_restore_view || !ppa.is_installed;
		});

		cell_ppa_select.toggled.connect((path) => {
			var model = (Gtk.ListStore)tv_ppa.model;
			bool selected;
			Ppa ppa;
			TreeIter iter;

			model.get_iter_from_string (out iter, path);
			model.get (iter, 0, out selected);
			model.get (iter, 1, out ppa);
			model.set (iter, 0, !selected);
			ppa.is_selected = !selected;
		});

		//col_ppa_status ----------------------

		col_ppa_status = new TreeViewColumn();
		//col_ppa_status.title = _("");
		col_ppa_status.resizable = true;
		tv_ppa.append_column(col_ppa_status);

		CellRendererPixbuf cell_ppa_status = new CellRendererPixbuf ();
		col_ppa_status.pack_start (cell_ppa_status, false);
		col_ppa_status.set_attributes(cell_ppa_status, "pixbuf", 2);

		//col_ppa_name ----------------------

		TreeViewColumn col_ppa_name = new TreeViewColumn();
		col_ppa_name.title = _("PPA");
		col_ppa_name.resizable = true;
		col_ppa_name.min_width = 180;
		tv_ppa.append_column(col_ppa_name);

		CellRendererText cell_ppa_name = new CellRendererText ();
		cell_ppa_name.ellipsize = Pango.EllipsizeMode.END;
		col_ppa_name.pack_start (cell_ppa_name, false);

		col_ppa_name.set_cell_data_func (cell_ppa_name, (cell_layout, cell, model, iter) => {
			Ppa ppa;
			model.get (iter, 1, out ppa, -1);
			(cell as Gtk.CellRendererText).text = ppa.name;
		});

		//col_ppa_desc ----------------------

		TreeViewColumn col_ppa_desc = new TreeViewColumn();
		if (is_restore_view){
			col_ppa_desc.title = _("Available Packages");
		}
		else{
			col_ppa_desc.title = _("Installed Packages");
		}
		col_ppa_desc.resizable = true;
		tv_ppa.append_column(col_ppa_desc);

		CellRendererText cell_ppa_desc = new CellRendererText ();
		cell_ppa_desc.ellipsize = Pango.EllipsizeMode.END;
		col_ppa_desc.pack_start (cell_ppa_desc, false);

		col_ppa_desc.set_cell_data_func (cell_ppa_desc, (cell_layout, cell, model, iter) => {
			Ppa ppa;
			model.get (iter, 1, out ppa, -1);
			(cell as Gtk.CellRendererText).text = ppa.description;
		});
	}

	private void init_actions() {
		//hbox_ppa_actions
		Box hbox_ppa_actions = new Box (Orientation.HORIZONTAL, 6);
		vbox_main.add (hbox_ppa_actions);

		//btn_select_all
		btn_select_all = new Gtk.Button.with_label (" " + _("Select All") + " ");
		hbox_ppa_actions.pack_start (btn_select_all, true, true, 0);
		btn_select_all.clicked.connect(() => {
			foreach(Ppa ppa in App.ppa_list_master.values) {
				if (is_restore_view) {
					if (!ppa.is_installed) {
						ppa.is_selected = true;
					}
					else {
						//no change
					}
				}
				else {
					ppa.is_selected = true;
				}
			}
			tv_ppa_refresh();
		});

		//btn_select_none
		btn_select_none = new Gtk.Button.with_label (" " + _("Select None") + " ");
		hbox_ppa_actions.pack_start (btn_select_none, true, true, 0);
		btn_select_none.clicked.connect(() => {
			foreach(Ppa ppa in App.ppa_list_master.values) {
				if (is_restore_view) {
					if (!ppa.is_installed) {
						ppa.is_selected = false;
					}
					else {
						//no change
					}
				}
				else {
					ppa.is_selected = false;
				}
			}
			tv_ppa_refresh();
		});

		//btn_backup
		btn_backup = new Gtk.Button.with_label (" <b>" + _("Backup") + "</b> ");
		btn_backup.no_show_all = true;
		hbox_ppa_actions.pack_start (btn_backup, true, true, 0);
		btn_backup.clicked.connect(btn_backup_clicked);

		//btn_restore
		btn_restore = new Gtk.Button.with_label (" <b>" + _("Restore") + "</b> ");
		btn_restore.no_show_all = true;
		hbox_ppa_actions.pack_start (btn_restore, true, true, 0);
		btn_restore.clicked.connect(btn_restore_clicked);

		//btn_cancel
		btn_cancel = new Gtk.Button.with_label (" " + _("Close") + " ");
		hbox_ppa_actions.pack_start (btn_cancel, true, true, 0);
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

	private void tv_ppa_refresh() {
		var model = new Gtk.ListStore(4, typeof(bool), typeof(Ppa), typeof(Gdk.Pixbuf), typeof(string));

		//sort ppa list
		var ppa_list = new ArrayList<Ppa>();
		foreach(Ppa ppa in App.ppa_list_master.values) {
			if (ppa.name != "official"){
				ppa_list.add(ppa);
			}
		}
		CompareDataFunc<Ppa> func = (a, b) => {
			return strcmp(a.name, b.name);
		};
		ppa_list.sort((owned)func);

		//status icons
		Gdk.Pixbuf pix_enabled = null;
		Gdk.Pixbuf pix_missing = null;
		Gdk.Pixbuf pix_unused = null;
		Gdk.Pixbuf pix_status = null;

		try {
			pix_enabled = new Gdk.Pixbuf.from_file (App.share_dir + "/aptik/images/item-green.png");
			pix_missing = new Gdk.Pixbuf.from_file (App.share_dir + "/aptik/images/item-gray.png");
			pix_unused = new Gdk.Pixbuf.from_file (App.share_dir + "/aptik/images/item-yellow.png");
		}
		catch (Error e) {
			log_error (e.message);
		}

		TreeIter iter;
		string tt = "";
		foreach(Ppa ppa in ppa_list) {
			//check status
			if (ppa.is_installed) {
				if (ppa.description.length > 0) {
					pix_status = pix_enabled;
					tt = _("PPA is Enabled (%d installed packages)").printf(ppa.description.split(" ").length);
				}
				else {
					pix_status = pix_unused;
					tt = _("PPA is Enabled (%d installed packages)").printf(0);
				}
			}
			else {
				pix_status = pix_missing;
				tt = _("PPA is Not Added");
			}

			//add row
			model.append(out iter);
			model.set (iter, 0, ppa.is_selected);
			model.set (iter, 1, ppa);
			model.set (iter, 2, pix_status);
			model.set (iter, 3, tt);
		}

		tv_ppa.set_model(model);
		tv_ppa.columns_autosize();
	}

	// backup

	private void backup_init() {
		var status_msg = _("Preparing...");
		var dlg = new ProgressWindow.with_parent(this, status_msg);
		dlg.show_all();
		gtk_do_events();

		try {
			is_running = true;
			Thread.create<void> (backup_init_thread, true);
		} catch (ThreadError e) {
			is_running = false;
			log_error (e.message);
		}

		dlg.pulse_start();
		dlg.update_status_line(true);
		
		while (is_running) {
			dlg.update_message(App.status_line);
			dlg.sleep(200);
		}

		//un-select unused PPAs
		foreach(Ppa ppa in App.ppa_list_master.values) {
			if (ppa.description.length == 0) {
				ppa.is_selected = false;
			}
			else{
				ppa.is_selected = true;
			}
		}

		tv_ppa_refresh();

		dlg.close();
		gtk_do_events();
	}

	private void backup_init_thread() {
		//App.read_package_info();
		//App.ppa_list_master = App.ppa_list_master;
		App.read_package_info();
		App.ppa_list_master = App.list_ppa();
		App.ppa_list_master = App.ppa_list_master;
		//App.ppa_list_master = App.list_ppa();
		is_running = false;
	}

	private void btn_backup_clicked() {
		//check if no action required
		bool none_selected = true;
		foreach(Ppa ppa in App.ppa_list_master.values) {
			if (ppa.is_selected) {
				none_selected = false;
				break;
			}
		}
		if (none_selected) {
			string title = _("No PPA Selected");
			string msg = _("Select the PPAs to backup");
			gtk_messagebox(title, msg, this, false);
			return;
		}

		gtk_set_busy(true, this);

		if (save_ppa_list_selected(true)) {
			this.close();
		}

		gtk_set_busy(false, this);
	}

	// restore
	
	private void restore_init() {
		var status_msg = _("Preparing...");
		var dlg = new ProgressWindow.with_parent(this, status_msg);
		dlg.show_all();
		gtk_do_events();

		try {
			is_running = true;
			Thread.create<void> (restore_init_thread, true);
		} catch (ThreadError e) {
			is_running = false;
			log_error (e.message);
		}

		dlg.pulse_start();
		dlg.update_status_line(true);
		
		while (is_running) {
			dlg.update_message(App.status_line);
			dlg.sleep(200);
		}

		tv_ppa_refresh();

		dlg.close();
		gtk_do_events();
	}

	private void restore_init_thread() {
		if (!skip_pkg_info_update){
			App.read_package_info();
		}
		skip_pkg_info_update = false;
		
		App.ppa_list_master = App.list_ppa();
		App.read_ppa_list();
		is_running = false;
	}

	private void btn_restore_clicked() {
		//check if no action required
		bool none_selected = true;
		foreach(Ppa ppa in App.ppa_list_master.values) {
			if (ppa.is_selected && !ppa.is_installed) {
				none_selected = false;
				break;
			}
		}
		if (none_selected) {
			string title = _("Nothing To Do");
			string msg = _("Selected PPAs are already enabled on this system");
			gtk_messagebox(title, msg, this, false);
			return;
		}

		if (!check_internet_connectivity()) {
			string title = _("Error");
			string msg = _("Internet connection is not active. Please check the connection and try again.");
			gtk_messagebox(title, msg, this, false);
			return;
		}

		var status_msg = _("Preparing...");
		var dlg = new ProgressWindow.with_parent(this,status_msg);
		dlg.show_all();
		gtk_do_events();

		//get total count
		App.progress_total = 0;
		App.progress_count = 0;
		foreach(Ppa ppa in App.ppa_list_master.values) {
			if (ppa.is_selected && !ppa.is_installed) {
				App.progress_total++;
			}
		}

		var ppa_list_add = new Gee.ArrayList<Ppa>();
		foreach(Ppa ppa in App.ppa_list_master.values) {
			if (ppa.is_selected && !ppa.is_installed) {
				string cmd = "add-apt-repository -y ppa:%s\n".printf(ppa.name);

				App.add_ppa(cmd);

				//dlg.pulse_start();
				dlg.update_message(_("Adding '%s'...").printf(ppa.name));
				dlg.update_status_line(true);

				while (App.is_running) {
					dlg.update_progressbar();
					//dlg.update_status_line();
					dlg.sleep(200);
				}

				App.progress_count++;

				ppa.message = "";
				foreach(string line in App.stdout_lines){
					ppa.message += "%s\n".printf(line);
				}

				ppa_list_add.add(ppa);
			}
		}

		//get total URL count
		App.progress_total = 0;
		App.progress_count = 0;
		string cmd = "apt-get update -y --print-uris";
		string txt = execute_command_sync_get_output(cmd);
		App.progress_total += txt.split("\n").length;

		//dlg.pulse_start();
		dlg.update_message(_("Running 'apt-get update'..."));
		dlg.update_status_line(true);
				
		App.apt_get_update();
		while (App.is_running) {
			dlg.update_progressbar();
			//dlg.update_status_line();
			dlg.sleep(200);
		}
		
		dlg.close();
		dlg.destroy();
		gtk_do_events();
		
		skip_pkg_info_update = true;
		restore_init();

		string error_msg = "";
		foreach(Ppa ppa_to_add in ppa_list_add) {
			if (App.ppa_list_master.has_key(ppa_to_add.name)){
				var ppa = App.ppa_list_master[ppa_to_add.name];
				if (!ppa.is_installed){
					error_msg += "%s\n\n".printf(ppa_to_add.name);
					error_msg += "%s\n\n".printf(ppa_to_add.message);
				}
			}
		}
		
		if (error_msg.length > 0){
			string title = _("Error");
			string msg = _("Following PPAs could not be added") + ":\n\n%s\n".printf(error_msg);
			gtk_messagebox(title, msg, this, false);
		}

		gtk_do_events();
	}

	private bool save_ppa_list_selected(bool show_on_success) {
		string file_name = "ppa.list";

		bool is_success = App.save_ppa_list_selected();

		if (is_success) {
			if (show_on_success) {
				string title = _("Finished");
				string msg = _("Backup created successfully") + ".\n";
				msg += _("List saved with file name") + " '%s'".printf(file_name);
				gtk_messagebox(title, msg, this, false);
			}
		}
		else {
			string title = _("Error");
			string msg = _("Failed to write")  + " '%s'".printf(file_name);
			gtk_messagebox(title, msg, this, true);
		}

		return is_success;
	}

}


