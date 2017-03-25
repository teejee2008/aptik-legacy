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

public class AdminWindow : Gtk.Window {

	private Gtk.TreeView tv;
	private Gtk.SpinButton spin_size_limit;
	
	public AdminWindow.with_parent(Window parent) {
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
		
		init_ui();
	}

	private void init_ui() {
		title = _("Admin");
		//set_default_size (450, 550);

		window_position = WindowPosition.CENTER;
		destroy_with_parent = true;
		skip_taskbar_hint = true;
		modal = true;
		icon = get_app_icon(16);

		this.delete_event.connect(on_delete_event);

		//get content area
		vbox_main = get_content_area();

		// add widgets ---------------------------------------------

		/* Note: Setting tab button padding to 0 causes problems with some GTK themes like Mint-X */
		
		init_ui_navpane ();

		init_ui_ppa();

		

		show_all();

        tmr_init = Timeout.add(100, init_delayed);
	}

	private void init_ui_navpane(){
		pane = new Gtk.Paned (Gtk.Orientation.HORIZONTAL);
		pane.margin = 6;
		vbox_main.add(pane);

		//tv_pages
		tv_pages = new TreeView();
		tv_pages.get_selection().mode = SelectionMode.SINGLE;
		tv_pages.headers_visible = false;
		tv_pages.activate_on_single_click = true;

		var sw_pages = new ScrolledWindow(tv_pages.get_hadjustment(), tv_pages.get_vadjustment());
		sw_pages.set_shadow_type (ShadowType.ETCHED_IN);
		sw_pages.add (tv_pages);
		//sw_pages.margin_right = 3;
		sw_pages.set_size_request (150, -1);
		pane.pack1(sw_pages, false, false); //resize, shrink

		TreeViewColumn col;
		CellRendererPixbuf cellPix;
		CellRendererText cellText;
		
		//col_dir
		col = new TreeViewColumn();
		col.expand = true;
		tv_pages.append_column(col);

		cellPix = new CellRendererPixbuf ();
		cellPix.xpad = 1;
		col.pack_start (cellPix, false);

		cellText = new CellRendererText ();
		cellText.ellipsize = Pango.EllipsizeMode.END;
		col.pack_start (cellText, false);

		//render icon
		col.set_attributes(cellPix, "pixbuf", 2);

		//render text
		col.set_cell_data_func (cellText, (cell_layout, cell, model, iter) => {
			string name;
			model.get (iter, 0, out name, -1);
			(cell as Gtk.CellRendererText).text = name;
		});

		//row activated event
		tv_pages.row_activated.connect(tv_pages_row_activated);


		tv_pages.get_selection().changed.connect(tv_pages_selection_changed);
		
		//notebook
		notebook = new Notebook();
		notebook.tab_pos = PositionType.TOP;
		notebook.show_border = true;
		notebook.scrollable = true;
		notebook.show_tabs = false;
		notebook.margin_left = 3;
		pane.pack2(notebook, true, true); //resize, shrink

		refresh_navpane();
	}
}


