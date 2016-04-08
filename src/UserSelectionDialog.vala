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

	private Gtk.TreeView tv;

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

		this.backup_mode = backup_mode;
		
		// get content area
		var vbox_main = get_content_area();
		vbox_main.spacing = 6;
		vbox_main.margin = 6;
		//vbox_main.margin_bottom = 12;
		vbox_main.set_size_request(300,300);

		var label = new Label(_("Select items to backup and restore"));
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

		// actions -------------------------
		
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

        show_all();
	}
}


