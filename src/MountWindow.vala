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

	private Gtk.Button btn_restore;
	private Gtk.Button btn_backup;
	private Gtk.Button btn_cancel;

	private Gtk.RadioButton rbtn_fstab;
	private Gtk.RadioButton rbtn_crypttab;
	 
	private Gtk.TreeView tv_mount;
	private Gtk.ScrolledWindow sw_mount;
	private Gtk.TreeViewColumn col_mapped_name;
	private Gtk.TreeViewColumn col_password;
	private Gtk.TreeViewColumn col_device;
	private Gtk.TreeViewColumn col_fs_type;
	private Gtk.TreeViewColumn col_mount_point;
	private Gtk.TreeViewColumn col_dump;
	private Gtk.TreeViewColumn col_pass;
	
	private Gee.ArrayList<FsTabEntry> fstab_list;
	private Gee.ArrayList<FsTabEntry> crypttab_list;
	private Gee.ArrayList<FsTabEntry> selected_list;
	
	private int def_width = 800;
	private int def_height = 450;
	private uint tmr_init = 0;
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

		init_nav_buttons();
		
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

		fstab_list = new Gee.ArrayList<FsTabEntry>();
		
		if (is_restore_view){
			title = _("Restore Mount Points");
			
			btn_restore.show();
			btn_restore.visible = true;

			restore_init();
		}
		else{
			// not used
		}

		return false;
	}

	private void init_nav_buttons(){
		//hbox
		var hbox = new Box(Orientation.HORIZONTAL, 6);
		vbox_main.add(hbox);

		var rbtn = new Gtk.RadioButton.with_label_from_widget (null, _("Regular Devices (/etc/fstab)"));
		hbox.add (rbtn);
		rbtn_fstab = rbtn;
		rbtn.toggled.connect (btn_fstab_clicked);

		rbtn = new Gtk.RadioButton.with_label_from_widget (rbtn, _("Encrypted Devices (/etc/crypttab)"));
		hbox.add (rbtn);
		rbtn_crypttab = rbtn;
		rbtn.toggled.connect (btn_crypttab_clicked);

		//var btn_fstab = new Gtk.Button.with_label("Regular Devices (/etc/fstab)");
		//hbox.add(btn_fstab);

		//var btn_crypttab = new Gtk.Button.with_label("Encrypted Devices (/etc/crypttab)");
		//hbox.add(btn_crypttab);
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

		var col = new TreeViewColumn();
		col.title = "";
		tv_mount.append_column(col);
		var col_mount_select = col;

		CellRendererToggle cell_mount_select = new CellRendererToggle ();
		cell_mount_select.activatable = true;
		col.pack_start (cell_mount_select, false);
		
		col_mount_select.set_cell_data_func (cell_mount_select, (cell_layout, cell, model, iter) => {
			bool selected;
			FsTabEntry fs;
			model.get (iter, 0, out selected, 1, out fs, -1);
			(cell as Gtk.CellRendererToggle).active = selected;
			(cell as Gtk.CellRendererToggle).sensitive = (fs.action == FsTabEntry.Action.ADD);
			//(cell as Gtk.CellRendererToggle).visible = (fs.action == FsTabEntry.Action.ADD);
		});

		cell_mount_select.toggled.connect((path) => {
			var model = (Gtk.ListStore) tv_mount.model;
			bool selected;
			FsTabEntry fs;
			TreeIter iter;

			model.get_iter_from_string (out iter, path);
			model.get (iter, 0, out selected);
			model.get (iter, 1, out fs);
			model.set (iter, 0, !selected);
			fs.is_selected = !selected;
		});

		//col_mapped_name ----------------------

		col = new TreeViewColumn();
		col.title = _("Mapped Name");
		col.resizable = true;
		tv_mount.append_column(col);
		col_mapped_name = col;
		
		var cell_text = new CellRendererText ();
		cell_text.ellipsize = Pango.EllipsizeMode.END;
		col.pack_start (cell_text, false);

		col.set_cell_data_func (cell_text, (cell_layout, cell, model, iter) => {
			FsTabEntry fs;
			model.get (iter, 1, out fs, -1);
			(cell as Gtk.CellRendererText).text = fs.mapped_name;
		});

		//col_device ----------------------

		col = new TreeViewColumn();
		col.title = _("Device");
		col.resizable = true;
		col.min_width = 180;
		tv_mount.append_column(col);
		col_device = col;
		
		cell_text = new CellRendererText ();
		cell_text.ellipsize = Pango.EllipsizeMode.END;
		col.pack_start (cell_text, false);

		col.set_cell_data_func (cell_text, (cell_layout, cell, model, iter) => {
			FsTabEntry fs;
			model.get (iter, 1, out fs, -1);
			(cell as Gtk.CellRendererText).text = fs.device;
		});

		//col_mount_point ----------------------

		col = new TreeViewColumn();
		col.title = _("Mount Point");
		col.resizable = true;
		col.min_width = 180;
		tv_mount.append_column(col);
		col_mount_point = col;
		
		cell_text = new CellRendererText ();
		cell_text.ellipsize = Pango.EllipsizeMode.END;
		col.pack_start (cell_text, false);

		col.set_cell_data_func (cell_text, (cell_layout, cell, model, iter) => {
			FsTabEntry fs;
			model.get (iter, 1, out fs, -1);
			(cell as Gtk.CellRendererText).text = fs.mount_point;
		});

		// col_password ----------------------

		col = new TreeViewColumn();
		col.title = _("Password / Keyfile");
		col.resizable = true;
		tv_mount.append_column(col);
		col_password = col;
		
		cell_text = new CellRendererText ();
		cell_text.ellipsize = Pango.EllipsizeMode.END;
		col.pack_start (cell_text, false);

		col.set_cell_data_func (cell_text, (cell_layout, cell, model, iter) => {
			FsTabEntry fs;
			model.get (iter, 1, out fs, -1);
			(cell as Gtk.CellRendererText).text = fs.password;
		});
		
		//col_type ----------------------

		col = new TreeViewColumn();
		col.title = _("FS Type");
		col.resizable = true;
		col.min_width = 50;
		tv_mount.append_column(col);
		col_fs_type = col;
		
		cell_text = new CellRendererText ();
		cell_text.ellipsize = Pango.EllipsizeMode.END;
		col.pack_start (cell_text, false);

		col.set_cell_data_func (cell_text, (cell_layout, cell, model, iter) => {
			FsTabEntry fs;
			model.get (iter, 1, out fs, -1);
			(cell as Gtk.CellRendererText).text = fs.fs_type;
		});

		//col_options ----------------------

		col = new TreeViewColumn();
		col.title = _("Options");
		col.resizable = true;
		col.min_width = 180;
		tv_mount.append_column(col);
		//var col_options = col;
		
		cell_text = new CellRendererText ();
		cell_text.ellipsize = Pango.EllipsizeMode.END;
		col.pack_start (cell_text, false);

		col.set_cell_data_func (cell_text, (cell_layout, cell, model, iter) => {
			FsTabEntry fs;
			model.get (iter, 1, out fs, -1);
			(cell as Gtk.CellRendererText).text = fs.options;
		});

		//col_dump ----------------------

		col = new TreeViewColumn();
		col.title = _("Dump");
		col.resizable = true;
		col.min_width = 10;
		tv_mount.append_column(col);
		col_dump = col;
		
		cell_text = new CellRendererText ();
		cell_text.ellipsize = Pango.EllipsizeMode.END;
		col.pack_start (cell_text, false);

		col.set_cell_data_func (cell_text, (cell_layout, cell, model, iter) => {
			FsTabEntry fs;
			model.get (iter, 1, out fs, -1);
			(cell as Gtk.CellRendererText).text = fs.dump;
		});

		//col_pass ----------------------

		col = new TreeViewColumn();
		col.title = _("Pass");
		col.resizable = true;
		col.min_width = 10;
		tv_mount.append_column(col);
		col_pass = col;
		
		cell_text = new CellRendererText ();
		cell_text.ellipsize = Pango.EllipsizeMode.END;
		col.pack_start (cell_text, false);

		col.set_cell_data_func (cell_text, (cell_layout, cell, model, iter) => {
			FsTabEntry fs;
			model.get (iter, 1, out fs, -1);
			(cell as Gtk.CellRendererText).text = fs.pass;
		});
	}

	private void init_actions() {
		//hbox_mount_actions
		Box hbox = new Box (Orientation.HORIZONTAL, 6);
		hbox.homogeneous = true;
		vbox_main.add (hbox);

		var lbl = new Gtk.Label("");
		hbox.pack_start (lbl, true, true, 0);

		lbl = new Gtk.Label("");
		hbox.pack_start (lbl, true, true, 0);
		
		//btn_restore
		btn_restore = new Gtk.Button.with_label (" <b>" + _("Restore") + "</b> ");
		hbox.pack_start (btn_restore, true, true, 0);
		btn_restore.clicked.connect(btn_restore_clicked);

		//btn_cancel
		btn_cancel = new Gtk.Button.with_label (" " + _("Close") + " ");
		hbox.pack_start (btn_cancel, true, true, 0);

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
		var model = new Gtk.ListStore(2, typeof(bool), typeof(FsTabEntry));

		TreeIter iter;
		foreach(FsTabEntry fs in selected_list) {
			//add row
			model.append(out iter);
			model.set (iter, 0, fs.is_selected);
			model.set (iter, 1, fs);
		}

		tv_mount.set_model(model);
		tv_mount.columns_autosize();
	}

	private void btn_fstab_clicked(){
		selected_list = fstab_list;

		col_device.title = _("Device");
		col_mapped_name.visible = false;
		col_password.visible = false;
		col_mount_point.visible = true;
		col_fs_type.visible = true;
		col_dump.visible = true;
		col_pass.visible = true;

		tv_mount_refresh();
	}

	private void btn_crypttab_clicked(){
		selected_list = crypttab_list;

		col_device.title = _("Encrypted Device");
		col_mapped_name.visible = true;
		col_password.visible = true;
		col_mount_point.visible = false;
		col_fs_type.visible = false;
		col_dump.visible = false;
		col_pass.visible = false;

		tv_mount_refresh();
	}

	// restore
	
	private void restore_init() {
		gtk_set_busy(true, this);

		fstab_list = App.create_fstab_list_for_restore();
		crypttab_list = App.create_crypttab_list_for_restore();
		selected_list = fstab_list;
		
		rbtn_fstab.active = true;
		btn_fstab_clicked();
		
		gtk_set_busy(false, this);
	}

	private void btn_restore_clicked() {
		
		// check if no action required ------------------
		
		bool none_selected = true;
		
		foreach(var fs in fstab_list) {
			if (fs.is_selected && (fs.action == FsTabEntry.Action.ADD)){
				none_selected = false;
				break;
			}
		}
		
		foreach(var fs in crypttab_list) {
			if (fs.is_selected && (fs.action == FsTabEntry.Action.ADD)){
				none_selected = false;
				break;
			}
		}
		
		if (none_selected) {
			string title = _("No Changes Required");
			string msg = _("/etc/fstab and /etc/crypttab are already up-to-date");
			gtk_messagebox(title, msg, this, false);
			return;
		}

		// check if key file is used -----------------------
		
		bool keyfile_used = false;

		string mounts_dir = App.backup_dir + "mounts";
		
		foreach(var fs in crypttab_list){
			if (!fs.is_selected || (fs.action != FsTabEntry.Action.ADD)){
				continue;
			}
			
			if (!fs.uses_keyfile()){
				continue;
			}
			
			if (file_exists(fs.password)){
				continue;
			}
			
			string src_file = "%s/%s".printf(mounts_dir, fs.keyfile_archive_name);
			
			if (file_exists(src_file)){
				keyfile_used = true;
				break;
			}
		}

		// get password ---------------------------
		
		string password = "";
		if (keyfile_used){
			password = PasswordWindow.prompt_user(this, false, _("Password Required"), Message.ENTER_PASSWORD_RESTORE);
			if (password == ""){
				return;
			}
		}

		// restore ------------------------------
		
		string err_msg = "";
		bool ok = App.restore_mounts(fstab_list, crypttab_list, password, out err_msg);
		
		if (ok){
			gtk_messagebox(_("Finished"), Message.RESTORE_OK, this, false);
			this.close();
		}
		else{
			gtk_messagebox(_("Error"), Message.RESTORE_ERROR + "\n\n%s".printf(err_msg), this, false);
		}
	}
}


