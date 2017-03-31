/*
 * PackageWindow.vala
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

public class PackageWindow : Window {
	private Gtk.Box vbox_main;
	private Gtk.Expander expander;

	private Box hbox_filter;
	private Entry txt_filter;
	private ComboBox cmb_pkg_section;
	private ComboBox cmb_pkg_status;
	private Gtk.Label lbl_filter_msg;
	
	private TreeView tv_packages;
	private TreeViewColumn col_pkg_status;
	private TreeViewColumn col_pkg_deb_name;
	private TreeModelFilter filter_packages;
	private ScrolledWindow sw_packages;
	
	private Button btn_restore;
	private Button btn_backup;
	private Button btn_cancel;
	private Button btn_select_all;
	private Button btn_select_none;

	private int def_width = 700;
	private int def_height = 450;
	private uint tmr_init = 0;
	private uint tmr_refilter = 0;
	private bool is_running = false;
	private bool is_restore_view = false;

	private bool is_backup_view{
		get{
			return !is_restore_view;
		}
	}

	private TerminalWindow term;
	
	private const Gtk.TargetEntry[] targets = {
		{ "text/uri-list", 0, 0}
	};
	
	// init
	
	public PackageWindow.with_parent(Window parent, bool restore) {
		set_transient_for(parent);
		set_modal(true);
		is_restore_view = restore;

		Gtk.drag_dest_set (this,Gtk.DestDefaults.ALL, targets, Gdk.DragAction.COPY);
		drag_data_received.connect(on_drag_data_received);
		
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

		//filters
		init_filters();

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
			title = _("Restore");
			
			btn_restore.show();
			btn_restore.visible = true;
			
			restore_init();
		}
		else{
			title = _("Backup");
			
			btn_backup.show();
			btn_backup.visible = true;

			backup_init();
		}

		lbl_filter_msg_update();
		
		return false;
	}

	private void init_filters() {

		expander = new Gtk.Expander(_("Advanced"));
		expander.use_markup = true;
		expander.expanded = false;
		vbox_main.add (expander);
		
		//hbox_filter
		hbox_filter = new Box (Orientation.HORIZONTAL, 6);
		hbox_filter.margin_left = 3;
		hbox_filter.margin_right = 3;
		expander.add (hbox_filter);

		//filter
		Label lbl_filter = new Label(_("Filter"));
		hbox_filter.add (lbl_filter);

		//txt_filter
		txt_filter = new Entry();
		txt_filter.hexpand = true;
		txt_filter.secondary_icon_stock = "gtk-clear";
		hbox_filter.add (txt_filter);

		txt_filter.icon_release.connect((p0, p1) => {
			txt_filter.text = "";
			filter_packages.refilter();
		});

		string tt = _("Search package name and description");
		txt_filter.set_tooltip_markup(tt);
		
		//cmb_pkg_status
		cmb_pkg_status = new ComboBox();
		
		tt = _("<b>Package State</b>\n\n");
		tt += _("<b>Installed</b>\nAll installed packages.") + "\n\n";
		tt += _("<b>Installed (dist)</b>\nPackages that came with your OS.") + "\n\n";
		tt += _("<b>Installed (user)</b>\nExtra packages installed by you. Dependency packages will not be displayed. For example, if you installed package A on your system, and packages B, C, D were installed along with A (as dependencies), then only A will be listed.") + "\n\n";
		tt += _("<b>Installed (auto)</b>\nPackages that were installed automatically for satisfying the dependencies of extra packages that were installed by you. Displays B, C, D from the above example.") + "\n\n";
		tt += _("<b>Installed (deb)</b>\nPackages that were installed from downloaded DEB files.") + "\n\n";
		tt += _("<b>Not Installed</b>\nPackages that are not installed but available for installation.") + "\n\n";
		tt += _("<b>Not Available</b>\nPackages that are not available for installation. These packages are not available in software repositories and there are no DEB files in backup directory.") + "\n\n";
		tt += _("<b>(backup-list)</b>\nPackages in the backup list");
		cmb_pkg_status.set_tooltip_markup(tt);
		
		hbox_filter.add (cmb_pkg_status);

		CellRendererPixbuf cell_cmb_status = new CellRendererPixbuf ();
		cmb_pkg_status.pack_start (cell_cmb_status, false);
		cmb_pkg_status.set_attributes(cell_cmb_status, "pixbuf", 1);
		
		CellRendererText cell_pkg_restore_status = new CellRendererText();
		cmb_pkg_status.pack_start(cell_pkg_restore_status, false );
		cmb_pkg_status.set_cell_data_func (cell_pkg_restore_status, (cell_pkg_restore_status, cell, model, iter) => {
			string status;
			model.get (iter, 0, out status, -1);
			(cell as Gtk.CellRendererText).text = status;
		});

		//cmb_pkg_section
		cmb_pkg_section = new ComboBox();
		cmb_pkg_section.set_tooltip_text(_("Category"));
		hbox_filter.add (cmb_pkg_section);

		CellRendererText cell_pkg_section = new CellRendererText();
		cmb_pkg_section.pack_start(cell_pkg_section, false );
		cmb_pkg_section.set_cell_data_func (cell_pkg_section, (cell_pkg_section, cell, model, iter) => {
			string section;
			model.get (iter, 0, out section, -1);
			(cell as Gtk.CellRendererText).text = section;
		});

		//filter events -------------

		txt_filter.changed.connect(refilter_after_timeout);

		//lbl_filter_msg
		lbl_filter_msg = new Gtk.Label("");
		lbl_filter_msg.xalign = (float) 0.0;
		//vbox_main.add(lbl_filter_msg);
	}

	private void init_treeview() {
		//tv_packages
		tv_packages = new TreeView();
		tv_packages.get_selection().mode = SelectionMode.MULTIPLE;
		tv_packages.headers_clickable = true;
		tv_packages.set_rules_hint (true);
		tv_packages.set_tooltip_column(3);

		//sw_packages
		sw_packages = new ScrolledWindow(null, null);
		sw_packages.set_shadow_type (ShadowType.ETCHED_IN);
		sw_packages.add (tv_packages);
		sw_packages.expand = true;
		vbox_main.add(sw_packages);

		//col_pkg_select ----------------------

		TreeViewColumn col_pkg_select = new TreeViewColumn();
		tv_packages.append_column(col_pkg_select);

		CellRendererToggle cell_pkg_select = new CellRendererToggle ();
		cell_pkg_select.activatable = true;
		col_pkg_select.pack_start (cell_pkg_select, false);

		col_pkg_select.set_cell_data_func (cell_pkg_select, (cell_layout, cell, model, iter) => {
			bool selected;
			Package pkg;
			model.get (iter, 0, out selected, 1, out pkg, -1);
			(cell as Gtk.CellRendererToggle).active = selected;
			if (is_restore_view){
				(cell as Gtk.CellRendererToggle).sensitive = !pkg.is_installed
					&& (pkg.is_available || (pkg.is_deb && pkg.deb_file_name.length > 0));
			}
			else{
				(cell as Gtk.CellRendererToggle).sensitive = true;
			}
		});

		cell_pkg_select.toggled.connect((path) => {
			TreeModel model = filter_packages;
			var store = (Gtk.ListStore) filter_packages.child_model;
			bool selected;
			Package pkg;

			TreeIter iter, child_iter;
			model.get_iter_from_string (out iter, path);
			model.get (iter, 0, out selected, 1, out pkg, -1);

			pkg.is_selected = !selected;

			filter_packages.convert_iter_to_child_iter(out child_iter, iter);
			store.set(child_iter, 0, pkg.is_selected, -1);
		});

		//col_pkg_status ----------------------

		col_pkg_status = new TreeViewColumn();
		//col_pkg_status.title = _("");
		col_pkg_status.resizable = true;
		tv_packages.append_column(col_pkg_status);

		CellRendererPixbuf cell_pkg_status = new CellRendererPixbuf ();
		col_pkg_status.pack_start (cell_pkg_status, false);
		col_pkg_status.set_attributes(cell_pkg_status, "pixbuf", 2);

		//col_pkg_name ----------------------

		TreeViewColumn col_pkg_name = new TreeViewColumn();
		col_pkg_name.title = _("Package");
		col_pkg_name.resizable = true;
		col_pkg_name.min_width = 180;
		tv_packages.append_column(col_pkg_name);

		CellRendererText cell_pkg_name = new CellRendererText ();
		cell_pkg_name.ellipsize = Pango.EllipsizeMode.END;
		col_pkg_name.pack_start (cell_pkg_name, false);

		col_pkg_name.set_cell_data_func (cell_pkg_name, (cell_layout, cell, model, iter) => {
			Package pkg;
			model.get (iter, 1, out pkg, -1);
			
			string display_name = pkg.name;
			if (pkg.is_foreign()){
				display_name += " (%s)".printf(pkg.arch);
			}
			//if (pkg.is_deb && (pkg.deb_file_name.length > 0)){
			//	display_name += " (DEB)";
			//}
			
			(cell as Gtk.CellRendererText).text = display_name;
		});

		//col_pkg_deb_name ----------------------

		col_pkg_deb_name = new TreeViewColumn();
		col_pkg_deb_name.title = _("DEB File Backup");
		col_pkg_deb_name.resizable = true;
		col_pkg_deb_name.min_width = 180;
		tv_packages.append_column(col_pkg_deb_name);

		CellRendererText cell_deb_name = new CellRendererText ();
		cell_deb_name.ellipsize = Pango.EllipsizeMode.END;
		col_pkg_deb_name.pack_start (cell_deb_name, false);

		col_pkg_deb_name.set_cell_data_func (cell_deb_name, (cell_layout, cell, model, iter) => {
			Package pkg;
			model.get (iter, 1, out pkg, -1);
			
			(cell as Gtk.CellRendererText).text = pkg.deb_file_name;
		});

		//col_pkg_desc ----------------------

		TreeViewColumn col_pkg_desc = new TreeViewColumn();
		col_pkg_desc.title = _("Description");
		col_pkg_desc.resizable = true;
		//col_pkg_desc.min_width = 300;
		tv_packages.append_column(col_pkg_desc);

		CellRendererText cell_pkg_desc = new CellRendererText ();
		cell_pkg_desc.ellipsize = Pango.EllipsizeMode.END;
		col_pkg_desc.pack_start (cell_pkg_desc, false);

		col_pkg_desc.set_cell_data_func (cell_pkg_desc, (cell_layout, cell, model, iter) => {
			Package pkg;
			model.get (iter, 1, out pkg, -1);
			(cell as Gtk.CellRendererText).text = pkg.description;
		});
	}

	private void init_actions() {
		//hbox_pkg_actions
		Box hbox_pkg_actions = new Box (Orientation.HORIZONTAL, 6);
		vbox_main.add (hbox_pkg_actions);

		//btn_select_all
		btn_select_all = new Gtk.Button.with_label (" " + _("Select All") + " ");
		hbox_pkg_actions.pack_start (btn_select_all, true, true, 0);
		btn_select_all.clicked.connect(() => {
			foreach(Package pkg in App.pkg_list_master.values) {
				if (pkg.is_visible){
					if (is_restore_view) {
						if (pkg.is_available && !pkg.is_installed) {
							pkg.is_selected = true;
						}
						else {
							//no change
						}
					}
					else {
						pkg.is_selected = true;
					}
				}
			}
			tv_packages_refresh();
		});

		//btn_select_none
		btn_select_none = new Gtk.Button.with_label (" " + _("Select None") + " ");
		hbox_pkg_actions.pack_start (btn_select_none, true, true, 0);
		btn_select_none.clicked.connect(() => {
			foreach(Package pkg in App.pkg_list_master.values) {
				if (pkg.is_visible){
					if (is_restore_view) {
						if (!pkg.is_installed && (pkg.is_available || (pkg.is_deb && (pkg.deb_file_name.length > 0)))) {
							pkg.is_selected = false;
						}
						else {
							//no change
						}
					}
					else {
						pkg.is_selected = false;
					}
				}
			}
			tv_packages_refresh();
		});

		//btn_backup
		btn_backup = new Gtk.Button.with_label (" <b>" + _("Backup") + "</b> ");
		btn_backup.no_show_all = true;
		hbox_pkg_actions.pack_start (btn_backup, true, true, 0);
		btn_backup.clicked.connect(btn_backup_clicked);

		//btn_restore
		btn_restore = new Gtk.Button.with_label (" <b>" + _("Restore") + "</b> ");
		btn_restore.no_show_all = true;
		hbox_pkg_actions.pack_start (btn_restore, true, true, 0);
		btn_restore.clicked.connect(btn_restore_clicked);

		//btn_cancel
		btn_cancel = new Gtk.Button.with_label (" " + _("Close") + " ");
		hbox_pkg_actions.pack_start (btn_cancel, true, true, 0);
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

	private void on_drag_data_received (Gdk.DragContext drag_context, int x, int y, Gtk.SelectionData data, uint info, uint time) {
		int count = 0;
        foreach(string uri in data.get_uris()){
			string file = uri.replace("file://","").replace("file:/","");
			file = Uri.unescape_string (file);

			if (file.has_suffix(".deb")){
				App.copy_deb_file(file);
				count++;
			}
		}

		if (count > 0){
			string msg = _("DEB files were copied to backup location.");
			gtk_messagebox(_("Files Copied"),msg,this,false);
		}

        Gtk.drag_finish (drag_context, true, false, time);
    }


	private void cmb_pkg_status_refresh() {
		log_debug("call: cmb_pkg_status_refresh()");
		var store = new Gtk.ListStore(2, typeof(string), typeof(Gdk.Pixbuf));
		TreeIter iter;

		//status icons
		Gdk.Pixbuf pix_green = null;
		Gdk.Pixbuf pix_gray = null;
		Gdk.Pixbuf pix_red = null;
		Gdk.Pixbuf pix_yellow = null;
		Gdk.Pixbuf pix_blue = null;
		Gdk.Pixbuf pix_pink = null;

		try {
			pix_green = new Gdk.Pixbuf.from_file(App.share_dir + "/aptik/images/item-green.png");
			pix_gray = new Gdk.Pixbuf.from_file(App.share_dir + "/aptik/images/item-gray.png");
			pix_red  = new Gdk.Pixbuf.from_file(App.share_dir + "/aptik/images/item-red.png");
			pix_pink  = new Gdk.Pixbuf.from_file(App.share_dir + "/aptik/images/item-pink.png");
			pix_yellow  = new Gdk.Pixbuf.from_file(App.share_dir + "/aptik/images/item-yellow.png");
			pix_blue  = new Gdk.Pixbuf.from_file(App.share_dir + "/aptik/images/item-blue.png");
		}
		catch (Error e) {
			log_error (e.message);
		}

		if (is_restore_view) {
			//restore
			store.append(out iter);
			store.set (iter, 0, _("All"), 1, null);
			store.append(out iter);
			store.set (iter, 0, _("Installed"), 1, pix_green);
			store.append(out iter);
			store.set (iter, 0, _("Installed (dist)"), 1, null);
			store.append(out iter);
			store.set (iter, 0, _("Installed (user)"), 1, null);
			store.append(out iter);
			store.set (iter, 0, _("Installed (auto)"), 1, null);
			store.append(out iter);
			store.set (iter, 0, _("Installed (deb)"), 1, null);
			store.append(out iter);
			store.set (iter, 0, _("NotInstalled"), 1, pix_gray);
			store.append(out iter);
			store.set (iter, 0, _("NotAvailable"), 1, pix_red);
			store.append(out iter);
			store.set (iter, 0, _("(selected)"), 1, null);
			store.append(out iter);
			store.set (iter, 0, _("(unselected)"), 1, null);
			store.append(out iter);
			store.set (iter, 0, _("(backup-list)"), 1, null);
		}
		else{
			//backup
			store.append(out iter);
			store.set (iter, 0, _("All"), 1, null);
			store.append(out iter);
			store.set (iter, 0, _("Installed"), 1, null);
			store.append(out iter);
			store.set (iter, 0, _("Installed (dist)"), 1, pix_blue);
			store.append(out iter);
			store.set (iter, 0, _("Installed (user)"), 1, pix_green);
			store.append(out iter);
			store.set (iter, 0, _("Installed (auto)"), 1, pix_yellow);
			store.append(out iter);
			store.set (iter, 0, _("Installed (deb)"), 1, pix_pink);
			store.append(out iter);
			store.set (iter, 0, _("(selected)"), 1, null);
			store.append(out iter);
			store.set (iter, 0, _("(unselected)"), 1, null);
		}
		cmb_pkg_status.set_model (store);
		cmb_pkg_status.active = 0;
	}

	private void cmb_pkg_section_refresh() {
		log_debug("call: cmb_pkg_section_refresh()");
		var store = new Gtk.ListStore(1, typeof(string));
		TreeIter iter;
		store.append(out iter);
		store.set (iter, 0, _("All"));
		foreach (string section in App.sections) {
			store.append(out iter);
			store.set (iter, 0, section);
		}
		cmb_pkg_section.set_model (store);
		cmb_pkg_section.active = 0;
	}

	private void cmb_filters_connect() {
		cmb_pkg_status.changed.connect(()=>{
			tv_packages_refilter();
			lbl_filter_msg_update();

			col_pkg_deb_name.visible = (cmb_pkg_status.active == 5);
		});

		cmb_pkg_section.changed.connect(tv_packages_refilter);
		
		log_debug("connected: combo events");
	}

	private void lbl_filter_msg_update(){
		switch (cmb_pkg_status.active) {
		case 0: //all
			//exclude nothing
			lbl_filter_msg.label = _("Showing all available packages");
			break;
		case 1: //Installed
			lbl_filter_msg.label = _("Showing all installed packages");
			break;
		case 2: //Installed, Distribution
			lbl_filter_msg.label = _("Showing packages that were installed with the Linux OS");
			break;
		case 3: //Installed, User
			lbl_filter_msg.label = _("Showing extra packages that were installed by you");
			break;
		case 4: //Installed, Automatic
			lbl_filter_msg.label = _("Showing packages that were automatically installed (required by other packages)");
			break;
		case 5: //Installed, DEB
			lbl_filter_msg.label = _("Showing packages that were installed from DEB files");
			break;
		case 6: //NotInstalled
			lbl_filter_msg.label = _("Showing packages that are not installed but available for installation");
			break;
		case 7: //selected
			lbl_filter_msg.label = _("Showing selected packages");
			break;
		case 8: //unselected
			lbl_filter_msg.label = _("Showing unselected packages");
			break;
		case 9: //backup list
			lbl_filter_msg.label = _("Showing packages from the backup list");
			break;
		}
	}
	
	private void cmb_filters_disconnect() {
		cmb_pkg_status.changed.disconnect(tv_packages_refilter);
		cmb_pkg_section.changed.disconnect(tv_packages_refilter);
		log_debug("disconnected: combo events");
	}

	private void tv_packages_refilter() {
		log_debug("call: tv_packages_refilter()");
		col_pkg_deb_name.visible = (cmb_pkg_status.active == 5);
		filter_packages.refilter();
	}

	private void tv_packages_refresh() {
		var model = new Gtk.ListStore(4, typeof(bool), typeof(Package), typeof(Gdk.Pixbuf), typeof(string));

		var pkg_list = new ArrayList<Package>();
		if (App.pkg_list_master != null) {
			foreach(Package pkg in App.pkg_list_master.values) {
				if (is_backup_view && pkg.is_installed){ continue; }
				if (is_restore_view && !pkg.in_backup_list && !pkg.is_installed){ continue; }
				pkg_list.add(pkg);
			}
		}
		CompareDataFunc<Package> func = (a, b) => {
			return strcmp(a.name, b.name);
		};
		pkg_list.sort((owned)func);

		//status icons
		Gdk.Pixbuf pix_green = null;
		Gdk.Pixbuf pix_gray = null;
		Gdk.Pixbuf pix_red = null;
		Gdk.Pixbuf pix_yellow = null;
		Gdk.Pixbuf pix_blue = null;
		Gdk.Pixbuf pix_status = null;
		Gdk.Pixbuf pix_pink = null;
		
		try {
			pix_green = new Gdk.Pixbuf.from_file(App.share_dir + "/aptik/images/item-green.png");
			pix_gray = new Gdk.Pixbuf.from_file(App.share_dir + "/aptik/images/item-gray.png");
			pix_red  = new Gdk.Pixbuf.from_file(App.share_dir + "/aptik/images/item-red.png");
			pix_pink  = new Gdk.Pixbuf.from_file(App.share_dir + "/aptik/images/item-pink.png");
			pix_yellow  = new Gdk.Pixbuf.from_file(App.share_dir + "/aptik/images/item-yellow.png");
			pix_blue  = new Gdk.Pixbuf.from_file(App.share_dir + "/aptik/images/item-blue.png");
		}
		catch (Error e) {
			log_error (e.message);
		}

		TreeIter iter;
		string tt = "";
		foreach(Package pkg in pkg_list) {
			tt = "";

			if (is_restore_view) {
				if (pkg.is_installed) {
					tt += _("Installed");
					pix_status = pix_green;
				}
				else if (pkg.is_available && pkg.is_deb){
					tt += _("Available") + ", " + _("Not Installed");
					pix_status = pix_pink;
				}
				else if(pkg.is_available || (pkg.is_deb && pkg.deb_file_name.length > 0)){
					tt += _("Available") + ", " + _("Not Installed");
					pix_status = pix_gray;
				}
				else{
					tt += _("Not Available");
					pix_status = pix_red;
				}
			}
			else {
				if (pkg.is_installed && pkg.is_deb) {
					tt += _("This package was installed from a DEB file");
					pix_status = pix_pink;
				}
				else if (pkg.is_installed && pkg.is_default) {
					tt += _("This package is part of the Linux distribution");
					pix_status = pix_blue;
				}
				else if (pkg.is_installed && pkg.is_manual) {
					tt += _("This package was installed by user");
					pix_status = pix_green;
				}
				else if (pkg.is_installed && pkg.is_automatic) {
					tt += _("This package was installed as a dependency for other packages");
					pix_status = pix_yellow;
				}
				else {
					tt += _("Available") + ", " + _("Not Installed");
					pix_status = pix_gray;
				}
			}

			//add row
			model.append(out iter);
			model.set (iter, 0, pkg.is_selected);
			model.set (iter, 1, pkg);
			model.set (iter, 2, pix_status);
			model.set (iter, 3, tt);
		}

		filter_packages = new TreeModelFilter (model, null);
		filter_packages.set_visible_func(filter_packages_filter);
		tv_packages.set_model (filter_packages);
		tv_packages.columns_autosize();
	}

	private bool filter_packages_filter (Gtk.TreeModel model, Gtk.TreeIter iter) {
		Package pkg;
		model.get (iter, 1, out pkg, -1);
		bool display = true;

		string search_string = txt_filter.text.strip().down();
		if ((search_string != null) && (search_string.length > 0)) {
			try {
				Regex regexName = new Regex (search_string, RegexCompileFlags.CASELESS);
				MatchInfo match_name;
				MatchInfo match_desc;
				if (!regexName.match (pkg.name, 0, out match_name) && !regexName.match (pkg.description, 0, out match_desc)) {
					display = false;
				}
			}
			catch (Error e) {
				//ignore
			}
		}

		switch (cmb_pkg_status.active) {
		case 0: //all
			//exclude nothing
			break;
		case 1: //Installed
			if (!pkg.is_installed) {
				display = false;
			}
			break;
		case 2: //Installed, Distribution
			if (!(pkg.is_installed && pkg.is_default)) {
				display = false;
			}
			break;
		case 3: //Installed, User
			if (!(pkg.is_installed && pkg.is_manual)) {
				display = false;
			}
			break;
		case 4: //Installed, Automatic
			if (!(pkg.is_installed && pkg.is_automatic && !pkg.is_default)) {
				display = false;
			}
			break;
		case 5: //Installed, DEB
			if (!(pkg.is_installed && pkg.is_deb && !pkg.is_automatic)) {
				display = false;
			}
			break;
		case 6: //NotInstalled
			if (!(!pkg.is_installed && !pkg.is_foreign())) {
				display = false;
			}
			break;
		case 7: //NotAvailable
			if (is_restore_view){
				if (!(!pkg.is_available && !(pkg.is_deb && (pkg.deb_file_name.length > 0)) && !pkg.is_installed)) {
					display = false;
				}
			}
			else{
				if (!(!pkg.is_available && !(pkg.is_deb && (pkg.deb_file_name.length > 0)))) {
					display = false;
				}
			}
			break;
		case 8: //selected
			if (!pkg.is_selected) {
				display = false;
			}
			break;
		case 9: //unselected
			if (pkg.is_selected) {
				display = false;
			}
			break;
		case 10: //backup-list
			if (!(pkg.in_backup_list)) {
				display = false;
			}
			break;
		}

		switch (cmb_pkg_section.active) {
		case 0: //all
			//exclude nothing
			break;
		default:
			if (pkg.section != gtk_combobox_get_value(cmb_pkg_section, 0, ""))
			{
				display = false;
			}
			break;
		}

		pkg.is_visible = display;
		
		return display;
	}

	private void refilter_after_timeout() {
		//remove pending action
		if (tmr_refilter > 0) {
			Source.remove(tmr_refilter);
			tmr_refilter = 0;
		}

		//add timed action
		tmr_refilter = Timeout.add(500, ()=>{
			if (tmr_refilter > 0) {
				Source.remove(tmr_refilter);
				tmr_refilter = 0;
			}
			
			filter_packages.refilter();
			
			return true;
		});
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

		if (App.default_list_missing) {
			string title = _("File Missing");
			string msg = _("The list of default packages is missing on this system") + ":\n'%s'\n\n".printf(Main.DEF_PKG_LIST);
			msg += _("It is not possible to determine whether a package was installed by you, or whether it was installed along with the Linux distribution.") + "\n\n";
			msg += _("All top-level installed packages have been selected by default.") + " ";
			msg += _("Please un-select the packages that are not required.") + "\n";
			gtk_messagebox(title, msg, this, false);
		}

		//select manual
		foreach(Package pkg in App.pkg_list_master.values) {
			pkg.is_selected = pkg.is_manual;
		}

		tv_packages_refresh();

		//disconnect combo events
		cmb_filters_disconnect();
		//refresh combos
		cmb_pkg_status_refresh();
		cmb_pkg_status.active = 3;
		cmb_pkg_section_refresh();
		//re-connect combo events
		cmb_filters_connect();

		tv_packages_refilter();

		dlg.destroy();
		gtk_do_events();

		string deb_list = "";
		foreach(Package pkg in App.pkg_list_master.values){
			if (pkg.is_installed && pkg.is_deb && (pkg.deb_file_name.length == 0)){
				deb_list += pkg.id + " ";
			}
		}
		if (deb_list.length > 0){
			string deb_msg = _("Following packages are not available in software repositories") + ":\n\n";
			deb_msg += deb_list + "\n\n";
			deb_msg += _("If you have the DEB files for these packages, you can drag-and-drop the files on this window. Files will be saved to backup location and used for restore.");
			gtk_messagebox(_("Unknown Source"), deb_msg, this, false);
		}
	}

	private void backup_init_thread() {
		App.read_package_info();
		App.pkg_list_master = App.pkg_list_master;
		is_running = false;
	}

	private void btn_backup_clicked() {
		//check if no action required
		bool none_selected = true;
		foreach(Package pkg in App.pkg_list_master.values) {
			if (pkg.is_selected) {
				none_selected = false;
				break;
			}
		}
		if (none_selected) {
			string title = _("No Packages Selected");
			string msg = _("Select the packages to backup");
			gtk_messagebox(title, msg, this, false);
			return;
		}

		var status_msg = _("Saving...");
		var dlg = new ProgressWindow.with_parent(this,status_msg,true);
		dlg.show_all();
		gtk_do_events();
			
		bool ok = App.save_package_list_selected();
		App.save_package_list_installed(); // status can be ignored
		var message = "";
		
		if (ok){
			message = Message.BACKUP_OK;
		}
		else{
			message = Message.BACKUP_ERROR;
		}

		dlg.finish(message);
		
		gtk_set_busy(true, this);
	}
	
	// restore
	
	private void restore_init() {
		var status_msg = _("Preparing...");
		var dlg = new ProgressWindow.with_parent(this, status_msg);
		dlg.show_all();
		gtk_do_events();

		gtk_set_busy(true, this);
		
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

		tv_packages_refresh();

		//disconnect combo events
		cmb_filters_disconnect();
		//refresh combos
		cmb_pkg_status_refresh();
		cmb_pkg_status.active = 10;
		cmb_pkg_section_refresh();
		//re-connect combo events
		cmb_filters_connect();

		tv_packages_refilter();

		if (App.pkg_list_missing.length > 0) {
			var title = _("Missing Packages");
			var msg = _("Following packages are not available (missing PPA):\n\n%s").printf(App.pkg_list_missing);
			gtk_messagebox(title, msg, this, false);
		}

		gtk_set_busy(false, this);
		
		dlg.destroy();
		gtk_do_events();
	}

	private void restore_init_thread() {
		App.read_package_info();
		App.update_pkg_list_master_for_restore(true);
		is_running = false;
	}

	private void btn_restore_clicked() {
		
		// check if no action required ------------------------------
		
		bool none_selected = true;
		foreach(Package pkg in App.pkg_list_master.values) {
			if (pkg.is_selected && !pkg.is_installed) {
				none_selected = false;
				break;
			}
		}
		
		if (none_selected) {
			string title = _("Nothing To Do");
			string msg = _("There are no packages selected for installation2");
			gtk_messagebox(title, msg, this, false);
			return;
		}

		if (!check_internet_connectivity()) {
			string title = _("Error");
			string msg = Message.INTERNET_OFFLINE;
			gtk_messagebox(title, msg, this, false);
			return;
		}

		gtk_set_busy(true, this);
		
		App.update_pkg_list_master_for_restore(false);

		gtk_set_busy(false, this);

		if ((App.pkg_list_install.length == 0) && (App.pkg_list_deb.length == 0)) {
			string title = _("Nothing To Do");
			string msg = "";
			if (App.pkg_list_missing.length > 0) {
				msg += _("Following packages are NOT available") + ":\n\n" + App.pkg_list_missing + "\n\n";
			}
			msg += _("There are no packages selected for installation");
			gtk_messagebox(title, msg, this, false);
			return;
		}

		this.hide();

		bool continue_installation = true;
		
		var download_list = App.get_download_uris(App.pkg_list_install);
		if (download_list.size > 0){
			var dlg = new DownloadWindow.with_parent(this,download_list);
			int response_code = dlg.run();
			dlg.close();
			dlg.destroy();
			gtk_do_events();
			
			if (response_code == Gtk.ResponseType.OK){
				continue_installation = true;
			}
			else{
				continue_installation = false;
			}
		}
		
		if (continue_installation){
			execute_in_terminal_window();
			//success/error will be displayed by apt-get in terminal
		}
		else{
			this.destroy(); //will display main window
		}
	}
	
	private void execute_in_terminal_window(){
		string cmd = "";
		if (App.pkg_list_install.length > 0){
			cmd += "echo '%s'\n".printf(string.nfill(70, '*'));
			cmd += "echo '%s:'\n".printf(_("Installing packages from repos"));
			cmd += "echo '%s'\n".printf(string.nfill(70, '*'));
			cmd += "apt-get install %s\n".printf(App.pkg_list_install);
			
			log_debug("exec: apt-get install %s".printf(App.pkg_list_install));
		}
		if (App.pkg_list_deb.length > 0){
			cmd += "echo '%s'\n".printf(string.nfill(70, '*'));
			cmd += "echo '%s:'\n".printf(_("Installing packages from DEB files"));
			cmd += "echo '%s'\n".printf(string.nfill(70, '*'));
			cmd += "echo ''\n";
			
			foreach(string line in App.gdebi_list.split("\n")){
				cmd += "gdebi -n %s\n".printf(line);
				log_debug("exec: gdebi -n %s\n".printf(line));
			}
		}
		cmd += "echo ''\n";
		cmd += "echo '%s'\n".printf(string.nfill(70, '*'));
		cmd += "echo '" + _("Finished installing packages") + ".'\n";
		cmd += "echo '%s'\n".printf(string.nfill(70, '*'));
		cmd += "echo ''\n";
		cmd += "echo '" + _("Press ENTER to exit...") + "'\n";
		cmd += "read dummy\n";

		this.hide();
		
		term = new TerminalWindow.with_parent(this);
		term.script_complete.connect(close_terminal);
		term.execute_script(save_bash_script_temp(cmd));
	}

	public void close_terminal(){
		term.destroy();
		this.destroy(); //close this window and display main window
	}
}


