/*
 * UserDataSettingsDialog.vala
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

public class UserDataSettingsDialog : Gtk.Dialog {
	private Gtk.Box vbox_main;
	private Gtk.TreeView tv_users;
	private Gtk.TreeView tv_exclude;
	private Gtk.ComboBox cmb_dup_mode;
	private Gtk.Notebook notebook;
	private Gtk.Box vbox_gen;
	private Gtk.Box vbox_users;
	private Gtk.Box vbox_exclude;
	
	public Gee.ArrayList<SystemUser> user_list;
	public bool backup_mode = true;
	private uint tmr_init = 0;
	
	public UserDataSettingsDialog.with_parent(Window parent, bool backup_mode) {
		set_transient_for(parent);
		set_modal(true);
		set_skip_taskbar_hint(true);
		set_skip_pager_hint(true);
		window_position = WindowPosition.CENTER_ON_PARENT;
		deletable = false;
		resizable = true;
		
		set_transient_for(parent);
		set_modal(true);

		title = (backup_mode) ? _("Backup") : _("Restore");
		
		this.backup_mode = backup_mode;
		
		//content area
		vbox_main = new Gtk.Box(Orientation.VERTICAL, 6);
		vbox_main.margin = 12;
		vbox_main.set_size_request(450,450);
		get_content_area().add(vbox_main);

		// notebook
		notebook = new Gtk.Notebook();
		notebook.expand = true;
		vbox_main.pack_start(notebook, true, true, 0);
		
		// tab general --------------

		if (backup_mode){
			
			var label = new Label(_("General"));
			label.xalign = (float) 0.0;

			vbox_gen = new Gtk.Box(Orientation.VERTICAL, 6);
			vbox_gen.margin = 12;
			
			notebook.append_page(vbox_gen, label);
		}

		// tab users --------------

		var label = new Label(_("Users"));
		label.xalign = (float) 0.0;

		vbox_users = new Gtk.Box(Orientation.VERTICAL, 6);
		vbox_users.margin = 12;
		
		notebook.append_page(vbox_users, label);

		// tab exclude --------------
		
		if (backup_mode){
			
			label = new Label(_("Exclude"));
			label.xalign = (float) 0.0;

			vbox_exclude = new Gtk.Box(Orientation.VERTICAL, 6);
			vbox_exclude.margin = 12;

			notebook.append_page(vbox_exclude, label);
		}

		// ---------
		
		init_ui();
		
        show_all();
        
		tmr_init = Timeout.add(100, init_delayed);
	}

	private bool init_delayed() {
		/* any actions that need to run after window has been displayed */
		if (tmr_init > 0) {
			Source.remove(tmr_init);
			tmr_init = 0;
		}

		notebook.switch_page.connect((page, num)=>{
			if (num == 1){
				if (App.home_tree == null){
					gtk_set_busy(true, this);
					App.init_home_tree();
					gtk_set_busy(false, this);
				}

				tv_exclude_refresh();
			}
		});

		return false;
	}

	private void init_ui(){
		if (backup_mode){
			init_ui_general();
		}

		init_ui_users();

		if (backup_mode){
			init_ui_exclude();
		}
		
		init_ui_actions();
	}

	private void init_ui_users(){
		
		var label = new Label(_("Select users"));
		label.xalign = (float) 0.0;
		//vbox_users.add (label);

		// add treeview ---------------------------------
		
		var tv = new TreeView();
		tv.get_selection().mode = SelectionMode.MULTIPLE;
		tv.set_tooltip_text (_("Select items to backup and restore"));
		tv.headers_visible = true;
		tv_users = tv;
		//tv.reorderable = true;

		var sw_cols = new ScrolledWindow(tv.get_hadjustment(), tv.get_vadjustment());
		sw_cols.set_shadow_type (ShadowType.ETCHED_IN);
		sw_cols.set_size_request(300,200);
		sw_cols.add (tv);
		vbox_users.pack_start (sw_cols, true, true, 0);
	
		// column -------------------------------------
		
		var col = new TreeViewColumn();
		col.title = "";
		tv.append_column(col);

		// cell toggle
		var cell_select = new CellRendererToggle ();
		cell_select.activatable = true;
		col.pack_start (cell_select, false);
		col.set_cell_data_func (cell_select, (cell_layout, cell, model, iter) => {
			bool selected;
			model.get (iter, 0, out selected, -1);
			(cell as Gtk.CellRendererToggle).active = selected;
		});

		cell_select.toggled.connect((path) => {
			var store = (Gtk.ListStore) tv.model;
			bool selected;
			SystemUser user;

			TreeIter iter;
			store.get_iter_from_string (out iter, path);
			store.get (iter, 0, out selected, 1, out user, -1);

			user.is_selected = !selected;

			store.set(iter, 0, user.is_selected, -1);
		});

		// column -------------------------------------
		
		col = new TreeViewColumn();
		col.title = _("User");
		col.expand = true;
		tv.append_column(col);
		
		// cell text
		var cellText = new CellRendererText();
		cellText.ellipsize = Pango.EllipsizeMode.END;
		col.pack_start (cellText, false);
		col.set_cell_data_func (cellText, (cell_layout, cell, model, iter)=>{
			SystemUser user;
			model.get (iter, 1, out user, -1);
			(cell as Gtk.CellRendererText).text = user.name;
		});

		// column --------------------------------
		
		col = new TreeViewColumn();
		col.title = _("Name");
		col.expand = true;
		tv.append_column(col);

		// cell text
		cellText = new CellRendererText();
		cellText.ellipsize = Pango.EllipsizeMode.END;
		col.pack_start (cellText, false);
		col.set_cell_data_func (cellText, (cell_layout, cell, model, iter)=>{
			SystemUser user;
			model.get (iter, 1, out user, -1);
			(cell as Gtk.CellRendererText).text = user.full_name;
		});

		// add rows ----------------------

		TreeIter iter;
		var store = new Gtk.ListStore (2, typeof(bool), typeof(SystemUser));
		foreach (var user in App.user_list_home) {
			store.append (out iter);
			store.set (iter, 0, user.is_selected);
			store.set (iter, 1, user);
		}
		
		tv.model = store;
	}

	private void init_ui_general(){
		init_ui_mode();
	}
	
	private void init_ui_mode(){
		// hbox
		var hbox = new Box (Orientation.HORIZONTAL, 6);
		vbox_gen.pack_start(hbox, false, true, 0);

		// label
		var label = new Label(_("Backup Mode"));
		label.xalign = (float) 0.0;
		hbox.pack_start (label, false, false, 0);

		// combo
		var combo = new ComboBox();
		var tt = _("Full - Remove previous backup and create new\nIncremental - Keep existing backup and save changes");
		combo.set_tooltip_text(tt);
		hbox.pack_start (combo, false, false, 0);
		cmb_dup_mode = combo;

		var cell_text = new CellRendererText();
		combo.pack_start(cell_text, false );
		combo.set_cell_data_func (cell_text, (cell_text, cell, model, iter) => {
			string text;
			model.get (iter, 0, out text, -1);
			(cell as Gtk.CellRendererText).text = text;
		});

		combo.changed.connect(()=>{
			App.dup_mode_full = (cmb_dup_mode.active == 0);
		});

		// add data ------------

		var store = new Gtk.ListStore(2, typeof (string), typeof (string));
		TreeIter iter;

		store.append(out iter);
		store.set (iter, 0, _("Full"), 1, "full", -1);

		store.append(out iter);
		store.set (iter, 0, _("Incremental"), 1, "incr", -1);
		
		combo.set_model (store);

		if (App.dup_mode_full){
			combo.active = 0;
		}
		else{
			combo.active = 1;
		}
	}

	private void init_ui_exclude(){
		
		var label = new Label(_("Select items to exclude"));
		label.xalign = (float) 0.0;
		vbox_exclude.add (label);

		// add treeview ---------------------------------
		
		var tv = new TreeView();
		tv.get_selection().mode = SelectionMode.MULTIPLE;
		tv.set_tooltip_text (_("Select items to backup and restore"));
		//tv.headers_visible = true;
		tv.headers_visible = false;
		tv.activate_on_single_click = true;
		//tv.reorderable = true;
		tv_exclude = tv;
		
		var sw_cols = new ScrolledWindow(tv.get_hadjustment(), tv.get_vadjustment());
		sw_cols.set_shadow_type (ShadowType.ETCHED_IN);
		sw_cols.set_size_request(300,200);
		sw_cols.add (tv);
		vbox_exclude.pack_start (sw_cols, true, true, 0);
	
		// column -------------------------------------
		
		var col = new TreeViewColumn();
		col.title = _("Item");
		col.expand = true;
		tv.append_column(col);

		// cell toggle
		var cell_select = new CellRendererToggle ();
		cell_select.activatable = true;
		col.pack_start (cell_select, false);
		col.set_cell_data_func (cell_select, (cell_layout, cell, model, iter) => {
			bool selected;
			model.get (iter, 0, out selected, -1);
			(cell as Gtk.CellRendererToggle).active = selected;
		});

		cell_select.toggled.connect((path) => {
			var model = (Gtk.TreeStore) tv.model;
			bool selected;
			FileItem fi;

			TreeIter iter;
			model.get_iter_from_string (out iter, path);
			model.get (iter, 0, out selected, 1, out fi, -1);

			fi.is_selected = !selected;

			model.set(iter, 0, fi.is_selected);
		});
		
		// cell icon
		var cell_pix = new CellRendererPixbuf ();
		cell_pix.xpad = 1;
		col.pack_start (cell_pix, false);
		
		// render icon
		col.set_cell_data_func (cell_pix, (cell_layout, cell, model, iter) => {
			FileItem item;
			model.get (iter, 1, out item, -1);

			if (item.is_dummy) {
				(cell as Gtk.CellRendererPixbuf).icon_name = "gtk-directory";
			}
			else {
				if (item.is_symlink) {
					(cell as Gtk.CellRendererPixbuf).icon_name = "emblem-symbolic-link";
				}
				else if (item.icon != null) {
					(cell as Gtk.CellRendererPixbuf).gicon = item.icon;
				}
				else {
					(cell as Gtk.CellRendererPixbuf).icon_name = "gtk-file";
				}
			}
		});
		
		// cell text
		var cellText = new CellRendererText();
		cellText.ellipsize = Pango.EllipsizeMode.END;
		col.pack_start (cellText, false);

		// render text
		col.set_cell_data_func (cellText, (cell_layout, cell, model, iter)=>{
			FileItem fi;
			model.get (iter, 1, out fi, -1);
			(cell as Gtk.CellRendererText).text = fi.file_name;
		});

		tv_exclude.row_expanded.connect(tv_exclude_row_expanded);
	}

	private void tv_exclude_refresh(){
		TreeIter iter0;
		var model = new Gtk.TreeStore (2, typeof(bool), typeof(FileItem));
		foreach (var fi in App.home_tree.children.values) {
			model.append (out iter0, null);
			model.set (iter0, 0, fi.is_selected);
			model.set (iter0, 1, fi);

			tv_append_to_iter(ref model, ref iter0, fi, false);
		}
		
		tv_exclude.model = model;
	}

	private void tv_exclude_row_expanded(TreeIter iter0, TreePath path){
		TreeStore model = (Gtk.TreeStore) tv_exclude.model;
		FileItem item0, item1;
		model.get (iter0, 1, out item0, -1);

		//log_debug("\nexpand:%s\n".printf(item0.file_name));
		
		TreeIter iter1;
		bool iterExists = model.iter_children (out iter1, iter0);
		while (iterExists) {
			model.get (iter1, 1, out item1, -1);

			//log_debug("\nquery:%s\n".printf(item1.file_name));
			item1.query_children(1);
			
			tv_append_to_iter(ref model, ref iter1, item1, false);

			iterExists = model.iter_next (ref iter1);
		}
	}
	
	private TreeIter? tv_append_to_iter(ref TreeStore model, ref TreeIter iter0, FileItem? item, bool addItem = true) {
		//append sub-directories to the nav pane iter
		
		TreeIter iter1 = iter0;
		if (addItem && (item.parent != null)) {

			if (item.file_name.has_prefix(".")){
				return null;
			}

			//log_debug("append_iter: %s".printf(item.file_name));
			
			model.append (out iter1, iter0);
			model.set (iter1, 0, item.is_selected);
			model.set (iter1, 1, item);
		}

		var list = new ArrayList<FileItem>();
		foreach(string key in item.children.keys) {
			var child = item.children[key];
			//if ((child.file_type == FileType.DIRECTORY) && !child.is_symlink) {
				list.add(child);
			//}
		}

		list.sort((a, b) => {
			if ((a.file_type == FileType.DIRECTORY) && (b.file_type != FileType.DIRECTORY)){
				return -1;
			}
			else if ((a.file_type != FileType.DIRECTORY) && (b.file_type == FileType.DIRECTORY)){
				return 1;
			}
			else{
				return strcmp(a.file_name.down(), b.file_name.down());
			}
		});

		foreach(var child in list) {
			tv_append_to_iter(ref model, ref iter1, child);
		}

		return iter1;
	}

	private void init_ui_actions(){
		// ok
        var button = (Button) add_button ((backup_mode) ? _("Backup") : _("Restore"), Gtk.ResponseType.ACCEPT);
        button.clicked.connect (()=>{
			//save_selection();
			this.close();
		});

		// cancel
        button = (Button) add_button ("gtk-cancel", Gtk.ResponseType.CANCEL);
        button.clicked.connect (()=>{
			this.close();
		});
	}

}


