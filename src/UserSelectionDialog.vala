/*
 * UserSelectionDialog.vala
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

public class UserSelectionDialog : Gtk.Dialog {
	private Gtk.Box vbox_main;
	private Gtk.TreeView tv;
	private Gtk.ComboBox cmb_dup_mode;
	
	public Gee.ArrayList<SystemUser> user_list;
	public bool backup_mode = true;
	
	public UserSelectionDialog.with_parent(Window parent, bool backup_mode) {
		set_transient_for(parent);
		set_modal(true);
		set_skip_taskbar_hint(true);
		set_skip_pager_hint(true);
		window_position = WindowPosition.CENTER_ON_PARENT;
		deletable = false;
		resizable = false;
		
		set_transient_for(parent);
		set_modal(true);

		title = (backup_mode) ? _("Backup") : _("Restore");
		
		this.backup_mode = backup_mode;
		
		// get content area

		vbox_main = new Gtk.Box(Orientation.VERTICAL, 6);
		vbox_main.margin = 12;
		//vbox_main.set_size_request(300,300);
		get_content_area().add(vbox_main);
		
		init_ui();
		
        show_all();
	}

	private void init_ui(){
		init_ui_users();
		
		if (backup_mode){
			init_ui_mode();
		}
		
		init_ui_actions();
	}

	private void init_ui_users(){
		var label = new Label(_("Select users"));
		label.xalign = (float) 0.0;
		vbox_main.add (label);

		// add treeview ---------------------------------
		
		tv = new TreeView();
		tv.get_selection().mode = SelectionMode.MULTIPLE;
		tv.set_tooltip_text (_("Select items to backup and restore"));
		tv.headers_visible = true;
		//tv.reorderable = true;

		var sw_cols = new ScrolledWindow(tv.get_hadjustment(), tv.get_vadjustment());
		sw_cols.set_shadow_type (ShadowType.ETCHED_IN);
		sw_cols.set_size_request(300,200);
		sw_cols.add (tv);
		vbox_main.pack_start (sw_cols, true, true, 0);
	
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

	private void init_ui_mode(){
		// hbox
		var hbox = new Box (Orientation.HORIZONTAL, 6);
		vbox_main.pack_start(hbox, false, true, 0);

		// label
		var label = new Label(_("Backup Mode"));
		label.xalign = (float) 0.0;
		hbox.pack_start (label, true, true, 0);

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


