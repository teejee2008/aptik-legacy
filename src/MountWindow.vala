/*
 * MountWindow.vala
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

public class MountWindow : Window {
	private Gtk.Box vbox_main;

	private Button btn_restore;
	private Button btn_backup;
	private Button btn_cancel;
	//private Button btn_select_all;
	//private Button btn_select_none;
	
	private TreeView tv_mount;
	//private TreeViewColumn col_mount_status;
	private ScrolledWindow sw_mount;

	private Gee.ArrayList<FstabEntry> fstab_list;
	
	private int def_width = 550;
	private int def_height = 450;
	private uint tmr_init = 0;
	//private bool is_running = false;
	private bool is_restore_view = false;

	// init
	
	public MountWindow.with_parent(Window parent, bool restore) {
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

		fstab_list = new Gee.ArrayList<FstabEntry>();
		
		if (is_restore_view){
			title = _("Restore Mount Points");
			
			btn_restore.show();
			btn_restore.visible = true;

			restore_init();
		}
		else{
			title = _("Backup Mount Points");
			
			btn_backup.show();
			btn_backup.visible = true;

			backup_init();
		}

		return false;
	}

	private void init_treeview() {
		//tv_mount
		tv_mount = new TreeView();
		tv_mount.get_selection().mode = SelectionMode.MULTIPLE;
		tv_mount.headers_clickable = true;
		tv_mount.set_rules_hint (true);

		//sw_mount
		sw_mount = new ScrolledWindow(null, null);
		sw_mount.set_shadow_type (ShadowType.ETCHED_IN);
		sw_mount.add (tv_mount);
		sw_mount.expand = true;
		vbox_main.add(sw_mount);

		//col_mount_select ----------------------

		TreeViewColumn col_mount_select = new TreeViewColumn();
		col_mount_select.title = "";
		CellRendererToggle cell_mount_select = new CellRendererToggle ();
		cell_mount_select.activatable = true;
		col_mount_select.pack_start (cell_mount_select, false);
		tv_mount.append_column(col_mount_select);

		col_mount_select.set_cell_data_func (cell_mount_select, (cell_layout, cell, model, iter) => {
			bool selected;
			FstabEntry fs;
			model.get (iter, 0, out selected, 1, out fs, -1);
			(cell as Gtk.CellRendererToggle).active = selected;
			(cell as Gtk.CellRendererToggle).sensitive = (fs.mount_point != "/");
		});

		cell_mount_select.toggled.connect((path) => {
			var model = (Gtk.ListStore) tv_mount.model;
			bool selected;
			FstabEntry fs;
			TreeIter iter;

			model.get_iter_from_string (out iter, path);
			model.get (iter, 0, out selected);
			model.get (iter, 1, out fs);
			model.set (iter, 0, !selected);
			fs.is_selected = !selected;
		});

		//col_mount_status ----------------------

		//col_mount_status = new TreeViewColumn();
		//col_mount_status.title = _("");
		//col_mount_status.resizable = true;
		//tv_mount.append_column(col_mount_status);

		//CellRendererPixbuf cell_mount_status = new CellRendererPixbuf ();
		//col_mount_status.pack_start (cell_mount_status, false);
		//col_mount_status.set_attributes(cell_mount_status, "pixbuf", 2);

		//col_device ----------------------

		TreeViewColumn col_device = new TreeViewColumn();
		col_device.title = _("Device");
		col_device.resizable = true;
		col_device.min_width = 180;
		tv_mount.append_column(col_device);

		CellRendererText cell_device = new CellRendererText ();
		cell_device.ellipsize = Pango.EllipsizeMode.END;
		col_device.pack_start (cell_device, false);

		col_device.set_cell_data_func (cell_device, (cell_layout, cell, model, iter) => {
			FstabEntry fs;
			model.get (iter, 1, out fs, -1);
			(cell as Gtk.CellRendererText).text = fs.device;
		});

		//col_mount_point ----------------------

		TreeViewColumn col_mount_point = new TreeViewColumn();
		col_mount_point.title = _("Mount Point");
		col_mount_point.resizable = true;
		col_mount_point.min_width = 180;
		tv_mount.append_column(col_mount_point);

		CellRendererText cell_mount_point = new CellRendererText ();
		cell_mount_point.ellipsize = Pango.EllipsizeMode.END;
		col_mount_point.pack_start (cell_mount_point, false);

		col_mount_point.set_cell_data_func (cell_mount_point, (cell_layout, cell, model, iter) => {
			FstabEntry fs;
			model.get (iter, 1, out fs, -1);
			(cell as Gtk.CellRendererText).text = fs.mount_point;
		});
		
		//col_type ----------------------

		TreeViewColumn col_type = new TreeViewColumn();
		col_type.title = _("Type");
		col_type.resizable = true;
		col_type.min_width = 50;
		tv_mount.append_column(col_type);

		CellRendererText cell_type = new CellRendererText ();
		cell_type.ellipsize = Pango.EllipsizeMode.END;
		col_type.pack_start (cell_type, false);

		col_type.set_cell_data_func (cell_type, (cell_layout, cell, model, iter) => {
			FstabEntry fs;
			model.get (iter, 1, out fs, -1);
			(cell as Gtk.CellRendererText).text = fs.fs_type;
		});

		//col_options ----------------------

		TreeViewColumn col_options = new TreeViewColumn();
		col_options.title = _("Options");
		col_options.resizable = true;
		col_options.min_width = 180;
		tv_mount.append_column(col_options);

		CellRendererText cell_options = new CellRendererText ();
		cell_options.ellipsize = Pango.EllipsizeMode.END;
		col_options.pack_start (cell_options, false);

		col_options.set_cell_data_func (cell_options, (cell_layout, cell, model, iter) => {
			FstabEntry fs;
			model.get (iter, 1, out fs, -1);
			(cell as Gtk.CellRendererText).text = fs.options;
		});

		//col_dump ----------------------

		TreeViewColumn col_dump = new TreeViewColumn();
		col_dump.title = _("Dump");
		col_dump.resizable = true;
		col_dump.min_width = 10;
		tv_mount.append_column(col_dump);

		CellRendererText cell_dump = new CellRendererText ();
		cell_dump.ellipsize = Pango.EllipsizeMode.END;
		col_dump.pack_start (cell_dump, false);

		col_dump.set_cell_data_func (cell_dump, (cell_layout, cell, model, iter) => {
			FstabEntry fs;
			model.get (iter, 1, out fs, -1);
			(cell as Gtk.CellRendererText).text = fs.dump;
		});

		//col_pass ----------------------

		TreeViewColumn col_pass = new TreeViewColumn();
		col_pass.title = _("Pass");
		col_pass.resizable = true;
		col_pass.min_width = 10;
		tv_mount.append_column(col_pass);

		CellRendererText cell_pass = new CellRendererText ();
		cell_pass.ellipsize = Pango.EllipsizeMode.END;
		col_pass.pack_start (cell_pass, false);

		col_pass.set_cell_data_func (cell_pass, (cell_layout, cell, model, iter) => {
			FstabEntry fs;
			model.get (iter, 1, out fs, -1);
			(cell as Gtk.CellRendererText).text = fs.pass;
		});
	}

	private void init_actions() {
		//hbox_mount_actions
		Box hbox_mount_actions = new Box (Orientation.HORIZONTAL, 6);
		vbox_main.add (hbox_mount_actions);

		//btn_select_all
		//btn_select_all = new Gtk.Button.with_label (" " + _("Select All") + " ");
		//hbox_mount_actions.pack_start (btn_select_all, true, true, 0);
	

		//btn_select_none
		//btn_select_none = new Gtk.Button.with_label (" " + _("Select None") + " ");
		//hbox_mount_actions.pack_start (btn_select_none, true, true, 0);


		//btn_backup
		btn_backup = new Gtk.Button.with_label (" <b>" + _("Backup") + "</b> ");
		btn_backup.no_show_all = true;
		hbox_mount_actions.pack_start (btn_backup, true, true, 0);
		btn_backup.clicked.connect(btn_backup_clicked);

		//btn_restore
		btn_restore = new Gtk.Button.with_label (" <b>" + _("Restore") + "</b> ");
		btn_restore.no_show_all = true;
		hbox_mount_actions.pack_start (btn_restore, true, true, 0);
		btn_restore.clicked.connect(btn_restore_clicked);

		//btn_cancel
		btn_cancel = new Gtk.Button.with_label (" " + _("Close") + " ");
		hbox_mount_actions.pack_start (btn_cancel, true, true, 0);
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

	private void tv_mount_refresh() {
		log_msg("here0");
		
		var model = new Gtk.ListStore(2, typeof(bool), typeof(FstabEntry));

		log_msg("here");
		
		TreeIter iter;
		foreach(FstabEntry fs in fstab_list) {
			//add row
			model.append(out iter);
			model.set (iter, 0, fs.is_selected);
			model.set (iter, 1, fs);
		}

		log_msg("here1");
		
		tv_mount.set_model(model);
		tv_mount.columns_autosize();

		log_msg("here2");
	}

	// backup

	private void backup_init() {
		gtk_set_busy(true, this);

		fstab_list = FstabEntry.read_fstab_file();

		if (fstab_list == null){
			log_msg("size=null");
		}
		else{
			log_msg("size=%d".printf(fstab_list.size));
		}
		
		tv_mount_refresh();

		gtk_set_busy(false, this);
	}

	private void btn_backup_clicked() {
		//check if no action required
		bool none_selected = true;
		foreach(FstabEntry fs in fstab_list) {
			if (fs.is_selected) {
				none_selected = false;
				break;
			}
		}
		if (none_selected) {
			string title = _("No Items Selected");
			string msg = _("Select the mounts to backup");
			gtk_messagebox(title, msg, this, false);
			return;
		}

		string message = _("Preparing...");

		var dlg = new ProgressWindow.with_parent(this, message);
		dlg.show_all();
		gtk_do_events();
		
		
		//finish ----------------------------------
		message = _("Backups created successfully");
		dlg.finish(message);
		gtk_do_events();
	}

	// restore
	
	private void restore_init() {
		gtk_set_busy(true, this);

		fstab_list = FstabEntry.read_fstab_file();
		tv_mount_refresh();


		gtk_set_busy(false, this);
	}

	private void btn_restore_clicked() {
		//check if no action required
		bool none_selected = true;
		foreach(FstabEntry fs in fstab_list) {
			if (fs.is_selected) {
				none_selected = false;
				break;
			}
		}
		if (none_selected) {
			string title = _("Nothing To Do");
			string msg = _("Selected mounts are already installed");
			gtk_messagebox(title, msg, this, false);
			return;
		}

		//begin
		string message = _("Preparing...");
		var dlg = new ProgressWindow.with_parent(this, message);
		dlg.show_all();
		gtk_do_events();

	
		//finish ----------------------------------
		message = _("mounts restored successfully");
		dlg.finish(message);
		gtk_do_events();
	}
}


