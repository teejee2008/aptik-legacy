/*
 * OneClickSettingsDialog.vala
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
using TeeJee.System;
using TeeJee.Misc;
using TeeJee.GtkHelper;

public class OneClickSettingsDialog : Gtk.Dialog {

	private Gtk.TreeView tv;
	private Gtk.SpinButton spin_size_limit;
	
	public OneClickSettingsDialog.with_parent(Window parent) {
		set_transient_for(parent);
		set_modal(true);
		set_skip_taskbar_hint(true);
		set_skip_pager_hint(true);
		window_position = WindowPosition.CENTER_ON_PARENT;
		deletable = false;
		resizable = false;
		
		set_transient_for(parent);
		set_modal(true);

		title = _("One-Click Settings");
		
		// get content area
		var vbox_main = get_content_area();
		vbox_main.spacing = 6;
		vbox_main.margin = 12;
		//vbox_main.margin_bottom = 12;
		vbox_main.set_size_request(400,400);

		var label = new Label(_("Select items to backup and restore"));
		label.xalign = (float) 0.0;
		vbox_main.add (label);
		
		//add treeview
		tv = new TreeView();
		tv.get_selection().mode = SelectionMode.MULTIPLE;
		tv.set_tooltip_text (_("Select items to backup and restore"));
		tv.headers_visible = false;
		//tv.reorderable = true;

		var sw_cols = new ScrolledWindow(tv.get_hadjustment(), tv.get_vadjustment());
		sw_cols.set_shadow_type (ShadowType.ETCHED_IN);
		sw_cols.add (tv);
		vbox_main.pack_start (sw_cols, true, true, 0);
	
		//colName
		var col = new TreeViewColumn();
		col.title = _("File");
		col.expand = true;
		tv.append_column(col);

		//cell toggle
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
			BackupTask task;

			TreeIter iter;
			store.get_iter_from_string (out iter, path);
			store.get (iter, 0, out selected, 1, out task, -1);

			task.is_selected = !selected;

			store.set(iter, 0, task.is_selected, -1);
		});

		//cell text
		var cellText = new CellRendererText();
		cellText.ellipsize = Pango.EllipsizeMode.END;
		col.pack_start (cellText, false);
		col.set_cell_data_func (cellText, (cell_layout, cell, model, iter)=>{
			BackupTask task;
			model.get (iter, 1, out task, -1);
			(cell as Gtk.CellRendererText).text = task.display_name;
		});
		
		//add rows ----------------------

		TreeIter iter;
		var store = new Gtk.ListStore (2, typeof(bool), typeof(BackupTask));
		foreach(var task in App.task_list){
			store.append (out iter);
			store.set (iter, 0, task.is_selected);
			store.set (iter, 1, task);
		}
		tv.model = store;

		// add size limit ------------------------------------------

		var hbox = new Gtk.Box (Orientation.HORIZONTAL, 6);
		//hbox.homogeneous = true;
		//hbox.margin_left = 6;
		vbox_main.add(hbox);

		var tt = _("[Application Settings Backup]\n\nSome applications such as Steam and Wine store a large amount of data in their configuration directories (~/.local/share/Steam and ~/.wine). Setting a limit will skip the backup for these applications. Keep the limit as 0 to backup the settings for all apps.");
		label = new Label(_("App settings backup limit (KB)"));
		label.xalign = (float) 0.0;
		label.hexpand = true;
		label.set_tooltip_text(tt);
		hbox.add (label);

		//spin_size_limit
		var adj = new Gtk.Adjustment(0, 0, 10000000, 1, 1, 0);
		var spin = new Gtk.SpinButton (adj, 1, 0);
		spin.xalign = (float) 0.5;
		spin.set_tooltip_text(tt);
		hbox.add (spin);
		spin_size_limit = spin;

		// actions -------------------------
		
		// ok
        var button = (Button) add_button ("gtk-ok", Gtk.ResponseType.ACCEPT);
        button.clicked.connect (()=>{
			save_selection();
			this.close();
		});

		// cancel
        button = (Button) add_button ("gtk-cancel", Gtk.ResponseType.CANCEL);
        button.clicked.connect (()=>{
			this.close();
		});

        show_all();
	}

	private void save_selection(){
		string s = "";

		//get ordered list -----------------------
		
		var list = new Gee.ArrayList<BackupTask>();

		TreeIter iter;
		bool iterExists = tv.model.get_iter_first (out iter);
		while (iterExists) {
			BackupTask task;
			tv.model.get (iter, 1, out task, -1);
			list.add(task);
			iterExists = tv.model.iter_next (ref iter);
		}

		// create string of names -------------
		
		foreach(var task in list){
			if (task.is_selected){
				s += task.name + ",";
			}
		}
		if (s.has_suffix(",")){
			s = s[0:s.length - 1];
		}

		App.selected_tasks = s;

		App.arg_size_limit = (uint64) (spin_size_limit.get_value() * 1024);
	}
}


