/*
 * UserAccountWindow.vala
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

public class UserAccountWindow : Window {
	private Gtk.Box vbox_main;

	private Gtk.Button btn_restore;
	private Gtk.Button btn_backup;
	private Gtk.Button btn_cancel;

	private Gtk.RadioButton rbtn_users;
	private Gtk.RadioButton rbtn_groups;
	 
	private Gtk.TreeView tv;
	private Gtk.ScrolledWindow sw_mount;
	private Gtk.TreeViewColumn col_name;
	private Gtk.TreeViewColumn col_id;
	private Gtk.TreeViewColumn col_type;
	private Gtk.TreeViewColumn col_list;

	//private Gee.ArrayList<FsTabEntry> fstab_list;
	//private Gee.ArrayList<FsTabEntry> crypttab_list;
	//private Gee.ArrayList<FsTabEntry> selected_list;
	
	private int def_width = 400;
	private int def_height = 350;
	private uint tmr_init = 0;
	private bool is_restore_view = false;

	// init
	
	public UserAccountWindow.with_parent(Window parent, bool restore) {
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

		//fstab_list = new Gee.ArrayList<FsTabEntry>();
		
		if (is_restore_view){
			title = _("Restore");
			
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

		var rbtn = new Gtk.RadioButton.with_label_from_widget (null, _("Users"));
		hbox.add (rbtn);
		rbtn_users = rbtn;
		rbtn.toggled.connect (btn_users_clicked);

		rbtn = new Gtk.RadioButton.with_label_from_widget (rbtn, _("Groups"));
		hbox.add (rbtn);
		rbtn_groups = rbtn;
		rbtn.toggled.connect (btn_groups_clicked);
	}
	
	private void init_treeview() {
		//tv
		tv = new TreeView();
		tv.get_selection().mode = SelectionMode.MULTIPLE;
		tv.headers_clickable = true;
		tv.set_rules_hint (true);

		//sw_mount
		sw_mount = new ScrolledWindow(null, null);
		sw_mount.set_shadow_type (ShadowType.ETCHED_IN);
		sw_mount.add (tv);
		sw_mount.expand = true;
		vbox_main.add(sw_mount);

		//col_mount_select ----------------------

		var col = new TreeViewColumn();
		col.title = "";
		tv.append_column(col);
		var col_mount_select = col;

		CellRendererToggle cell_mount_select = new CellRendererToggle ();
		cell_mount_select.activatable = true;
		col.pack_start (cell_mount_select, false);
		
		col_mount_select.set_cell_data_func (cell_mount_select, (cell_layout, cell, model, iter) => {
			bool selected;
			if (rbtn_users.active){
				SystemUser user;
				model.get (iter, 0, out selected, 1, out user, -1);
				(cell as Gtk.CellRendererToggle).active = selected;
				(cell as Gtk.CellRendererToggle).visible = (user.is_installed == false);
			}
			else{
				SystemGroup group;
				model.get (iter, 0, out selected, 1, out group, -1);
				(cell as Gtk.CellRendererToggle).active = selected;
				(cell as Gtk.CellRendererToggle).visible = (group.is_installed == false);
			}
		});

		cell_mount_select.toggled.connect((path) => {
			bool selected;
			TreeIter iter;
			
			var model = (Gtk.ListStore) tv.model;
			model.get_iter_from_string (out iter, path);
			model.get (iter, 0, out selected);
			model.set (iter, 0, !selected);
			
			if (rbtn_users.active){
				SystemUser user;
				model.get (iter, 1, out user);
				user.is_selected = !selected;
			}
			else{
				SystemGroup group;
				model.get (iter, 1, out group);
				group.is_selected = !selected;
			}
		});

		//col_name ----------------------

		col = new TreeViewColumn();
		col.title = _("Name");
		col.min_width = 100;
		col.resizable = true;
		tv.append_column(col);
		col_name = col;

		var cell_pix = new CellRendererPixbuf ();
		col.pack_start (cell_pix, false);
		col.set_attributes(cell_pix, "pixbuf", 2);
		
		var cell_text = new CellRendererText ();
		cell_text.ellipsize = Pango.EllipsizeMode.END;
		col.pack_start (cell_text, false);

		col.set_cell_data_func (cell_text, (cell_layout, cell, model, iter) => {
			if (rbtn_users.active){
				SystemUser user;
				model.get (iter, 1, out user, -1);
				(cell as Gtk.CellRendererText).text = user.name;
			}
			else{
				SystemGroup group;
				model.get (iter, 1, out group, -1);
				(cell as Gtk.CellRendererText).text = group.name;
			}
		});

		//col_id ----------------------

		col = new TreeViewColumn();
		col.title = _("ID");
		col.resizable = true;
		col.min_width = 100;
		tv.append_column(col);
		col_id = col;
		
		cell_text = new CellRendererText ();
		cell_text.ellipsize = Pango.EllipsizeMode.END;
		cell_text.xalign = (float) 1.0;
		col.pack_start (cell_text, false);

		col.set_cell_data_func (cell_text, (cell_layout, cell, model, iter) => {
			if (rbtn_users.active){
				SystemUser user;
				model.get (iter, 1, out user, -1);
				(cell as Gtk.CellRendererText).text = "%d".printf(user.uid);
			}
			else{
				SystemGroup group;
				model.get (iter, 1, out group, -1);
				(cell as Gtk.CellRendererText).text = "%d".printf(group.gid);
			}
		});

		//col_type ----------------------

		col = new TreeViewColumn();
		col.title = _("Type");
		col.resizable = true;
		col.min_width = 150;
		tv.append_column(col);
		col_type = col;
		
		cell_text = new CellRendererText ();
		cell_text.ellipsize = Pango.EllipsizeMode.END;
		col.pack_start (cell_text, false);

		col.set_cell_data_func (cell_text, (cell_layout, cell, model, iter) => {
			if (rbtn_users.active){
				SystemUser user;
				model.get (iter, 1, out user, -1);
				(cell as Gtk.CellRendererText).text = (user.is_system) ? _("System") : _("Normal");
			}
			else{
				SystemGroup group;
				model.get (iter, 1, out group, -1);
				(cell as Gtk.CellRendererText).text = (group.is_system) ? _("System") : _("Normal");
			}
		});

		//col_list ----------------------

		col = new TreeViewColumn();
		col.title = _("List");
		col.resizable = true;
		//col.min_width = 180;
		tv.append_column(col);
		col_list = col;
		
		cell_text = new CellRendererText ();
		cell_text.ellipsize = Pango.EllipsizeMode.END;
		col.pack_start (cell_text, false);

		col.set_cell_data_func (cell_text, (cell_layout, cell, model, iter) => {
			if (rbtn_users.active){
				SystemUser user;
				model.get (iter, 1, out user, -1);
				(cell as Gtk.CellRendererText).text = user.group_names;
			}
			else{
				SystemGroup group;
				model.get (iter, 1, out group, -1);
				(cell as Gtk.CellRendererText).text = group.user_names;
			}
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

	private void tv_refresh() {
		//status icons
		Gdk.Pixbuf pix_enabled = null;
		Gdk.Pixbuf pix_missing = null;
		Gdk.Pixbuf pix_unused = null;

		try {
			pix_enabled = new Gdk.Pixbuf.from_file (App.share_dir + "/aptik/images/item-green.png");
			pix_missing = new Gdk.Pixbuf.from_file (App.share_dir + "/aptik/images/item-gray.png");
			pix_unused = new Gdk.Pixbuf.from_file (App.share_dir + "/aptik/images/item-yellow.png");
		}
		catch (Error e) {
			log_error (e.message);
		}
		
		if (rbtn_users.active){
			var model = new Gtk.ListStore(3, typeof(bool), typeof(SystemUser), typeof(Gdk.Pixbuf));

			var list = new Gee.ArrayList<SystemUser>();
			foreach(var user in App.user_list_bak.values) {
				list.add(user);
			}
			CompareDataFunc<Ppa> func = (a, b) => {
				return strcmp(a.name, b.name);
			};
			list.sort((owned)func);

			TreeIter iter;
			foreach(var user in list) {
				if (user.is_system){
					continue;
				}
				
				//add row
				model.append(out iter);
				model.set (iter, 0, user.is_selected);
				model.set (iter, 1, user);
				if (user.is_installed){
					model.set (iter, 2, pix_enabled);
				}
				else{
					model.set (iter, 2, pix_missing);
				}
			}
			
			tv.set_model(model);
		}
		else{
			var model = new Gtk.ListStore(3, typeof(bool), typeof(SystemGroup), typeof(Gdk.Pixbuf));

			var list = new Gee.ArrayList<SystemGroup>();
			foreach(var group in App.group_list_bak.values) {
				list.add(group);
			}
			CompareDataFunc<Ppa> func = (a, b) => {
				return strcmp(a.name, b.name);
			};
			list.sort((owned)func);
			
			TreeIter iter;
			foreach(var group in list) {
				if (group.is_system){
					continue;
				}
				
				//add row
				model.append(out iter);
				model.set (iter, 0, group.is_selected);
				model.set (iter, 1, group);
				if (group.is_installed){
					model.set (iter, 2, pix_enabled);
				}
				else{
					model.set (iter, 2, pix_missing);
				}
			}

			tv.set_model(model);
		}

		tv.columns_autosize();
	}

	private void btn_users_clicked(){
		col_name.title = _("User");
		col_id.title = _("UID");
		col_type.title = _("Type");
		col_list.title = _("Groups");

		col_id.visible = false;
		col_type.visible = false;
		col_list.visible = false;
		
		tv_refresh();
	}

	private void btn_groups_clicked(){
		col_name.title = _("Group");
		col_id.title = _("GID");
		col_type.title = _("Type");
		col_list.title = _("Users");

		col_id.visible = false;
		col_type.visible = false;
		col_list.visible = true;
		
		tv_refresh();
	}

	// restore
	
	private void restore_init() {
		gtk_set_busy(true, this);

		rbtn_users.active = true;
		btn_users_clicked();
		
		gtk_set_busy(false, this);
	}

	private void btn_restore_clicked() {
		
		// check if no action required ------------------
		
		bool none_selected = true;
		
		foreach(var item in App.user_list_bak.values) {
			if (item.is_selected && !item.is_installed){
				none_selected = false;
				break;
			}
		}
		
		foreach(var item in App.group_list_bak.values) {
			if (item.is_selected && !item.is_installed){
				none_selected = false;
				break;
			}
		}
		
		if (none_selected) {
			string title = _("No Changes Required");
			string msg = _("Users and Groups are already up-to-date");
			gtk_messagebox(title, msg, this, false);
			return;
		}
		
		// restore ------------------------------
		
		string err_msg = "";
		bool ok = App.restore_users_and_groups();
		
		if (ok){
			gtk_messagebox(_("Finished"), Message.RESTORE_OK, this, false);
			this.close();
		}
		else{
			gtk_messagebox(_("Error"), Message.RESTORE_ERROR + "\n\n%s".printf(err_msg), this, false);
		}
	}
}


