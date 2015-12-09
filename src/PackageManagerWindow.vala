/*
 * PackageManagerWindow.vala
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

public class PackageManagerWindow : Window {
	private Box vbox_main;
	private Box vbox_actions;
	private Box hbox_filter;
	private Box hbox_pkg_actions;

	private Gtk.Paned pane;
	private TreeView tv_packages;
	private ScrolledWindow sw_packages;
	private TreeViewColumn col_pkg_status;
	private TreeModelFilter filter_packages;

	private TreeView tv_ppa;
	private ScrolledWindow sw_ppa;
	private TreeViewColumn col_ppa_status;

	private Button btn_restore_packages;
	private Button btn_restore_packages_exec;
	private Button btn_backup_packages;
	private Button btn_backup_packages_exec;
	private Button btn_backup_packages_cancel;
	private Button btn_backup_packages_select_all;
	private Button btn_backup_packages_select_none;
	//private ComboBox cmb_pkg_level;
	private ComboBox cmb_pkg_status;
	private ComboBox cmb_pkg_section;
	private Entry txt_filter;
	private Button btn_actions;
	private Button btn_selections;

	private ProgressBar progressbar;
	private Label lbl_status;

	//private Gee.HashMap<string,Package> pkg_list_user;
	private Gee.HashMap<string,Package> pkg_list_all;

	int def_width = 700;
	int def_height = 500;
	int icon_size_list = 22;
	int button_width = 85;
	int button_height = 15;
	bool is_running = false;
	uint timer_pkg_info = 0;
	int count_available = 0;
	int count_installed = 0;
	int count_listed = 0;

	public PackageManagerWindow() {
		destroy.connect(Gtk.main_quit);
		init_window();
	}

	public PackageManagerWindow.with_parent(Window parent) {
		set_transient_for(parent);
		set_modal(true);
		init_window();
		init_window_for_parent();
	}

	// init widgets ------------------------------------------------------------

	public void init_window () {
		title = "Aptik Package Manager" + " v" + AppVersion;
    window_position = WindowPosition.CENTER;
    resizable = true;
    set_default_size (def_width, def_height);

		//icon = get_app_icon(16);

    //vbox_main
    vbox_main = new Box (Orientation.VERTICAL, 6);
    vbox_main.margin = 6;
    add (vbox_main);

		//vbox_actions
    vbox_actions = new Box (Gtk.Orientation.VERTICAL, 6);
    //vbox_actions.margin = 12;
		vbox_main.add (vbox_actions);

		init_section_filters();

		pane = new Gtk.Paned (Gtk.Orientation.VERTICAL);
		vbox_actions.add (pane);

		init_section_tv_ppa();

		init_section_tv_packages();

		//init_section_actions();

		init_section_status();

		refresh_all();

		log_msg("Created: PackageManagerWindow");

		timer_pkg_info = Timeout.add(100, timer_refresh_package_info);
	}

	public void init_window_for_parent(){
		btn_actions.hide();
		btn_selections.hide();
	}

	public bool timer_refresh_package_info(){
		if (timer_pkg_info > 0){
			Source.remove(timer_pkg_info);
			timer_pkg_info = 0;
		}
		refresh_package_information();
		//log_msg("Refreshing view...");
		//refresh_all();
		return true;
	}

	public void init_section_filters(){
		//hbox_filter
		hbox_filter = new Box (Orientation.HORIZONTAL, 6);
		hbox_filter.margin_left = 3;
		hbox_filter.margin_right = 3;
		vbox_actions.pack_start (hbox_filter, false, true, 0);

		//filter
		Label lbl_filter = new Label(_("Filter"));
		hbox_filter.add (lbl_filter);

		txt_filter = new Entry();
		txt_filter.hexpand = true;
		hbox_filter.add (txt_filter);

		//cmb_pkg_status
		cmb_pkg_status = new ComboBox();
		cmb_pkg_status.set_tooltip_text(_("Package State\n\nInstalled\t\t\tAll installed packages\nInstalled (dist)\t\tPackages that are part of the base distribution\nInstalled (user)\t\tExtra packages that were installed by user\nInstalled (auto)\t\tPackages that were installed automatically\n\t\t\t\t\t(as a dependency for other packages)\nInstalled (updates)\tPackages that have updates available\nNot Installed\t\tPackages which are not installed"));
		hbox_filter.add (cmb_pkg_status);

		CellRendererText cell_pkg_restore_status = new CellRendererText();
    cmb_pkg_status.pack_start(cell_pkg_restore_status, false );
    cmb_pkg_status.set_cell_data_func (cell_pkg_restore_status, (cell_pkg_restore_status, cell, model, iter) => {
			string status;
			model.get (iter, 0, out status,-1);
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
			model.get (iter, 0, out section,-1);
			(cell as Gtk.CellRendererText).text = section;
			});

		//filter events -------------

		txt_filter.changed.connect(()=>{
			filter_packages.refilter();
			count_listed = gtk_treeview_model_count(tv_packages.model);
			update_status();
		});

		//ToDO: Refilter after half-second of last keystroke

		//btn_selections
		btn_selections = new Gtk.Button.from_icon_name("gtk-select-all", Gtk.IconSize.BUTTON);
		btn_selections.always_show_image = true;
		hbox_filter.add (btn_selections);

		//btn_actions
		btn_actions = new Gtk.Button.from_icon_name("gtk-execute", Gtk.IconSize.BUTTON);
		btn_actions.always_show_image = true;
		hbox_filter.add (btn_actions);
	}

	public void init_section_tv_ppa(){
		//tv_ppa
		tv_ppa = new TreeView();
		tv_ppa.get_selection().mode = SelectionMode.MULTIPLE;
		tv_ppa.headers_clickable = true;
		tv_ppa.set_rules_hint (true);
		tv_ppa.set_tooltip_column(3);
		tv_ppa.set_activate_on_single_click(true);

		//sw_ppa
		sw_ppa = new ScrolledWindow(null, null);
		sw_ppa.set_shadow_type (ShadowType.ETCHED_IN);
		sw_ppa.add (tv_ppa);
		sw_ppa.expand = true;
		pane.add1(sw_ppa);

		TreeSelection sel = tv_ppa.get_selection();
		sel.changed.connect(()=>{
			tv_packages_refresh();
		});

		/*tv_ppa.row_activated.connect((path,column)=>{
			tv_packages_refresh();
			});*/

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
			//(cell as Gtk.CellRendererToggle).active = selected;
			//(cell as Gtk.CellRendererToggle).sensitive = !is_restore_view || !ppa.is_installed;
		});

		cell_ppa_select.toggled.connect((path) => {
			ListStore model = (ListStore)tv_ppa.model;
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
		col_ppa_desc.title = _("Packages");
		col_ppa_desc.resizable = true;
		tv_ppa.append_column(col_ppa_desc);

		CellRendererText cell_ppa_desc = new CellRendererText ();
		cell_ppa_desc.ellipsize = Pango.EllipsizeMode.END;
		col_ppa_desc.pack_start (cell_ppa_desc, false);

		col_ppa_desc.set_cell_data_func (cell_ppa_desc, (cell_layout, cell, model, iter) => {
			Ppa ppa;
			model.get (iter, 1, out ppa, -1);
			int installed_count = ppa.description.strip().split(" ").length;
			int available_count = ppa.all_packages.strip().split(" ").length;
			(cell as Gtk.CellRendererText).text =  "%d ".printf(available_count) + _("available")
			+ ", %d ".printf(installed_count) + _("installed");
		});
	}

	public void init_section_tv_packages(){
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
		pane.add2(sw_packages);

		//col_pkg_select ----------------------

		TreeViewColumn col_pkg_select = new TreeViewColumn();
		tv_packages.append_column(col_pkg_select);

		CellRendererToggle cell_pkg_select = new CellRendererToggle ();
		cell_pkg_select.activatable = true;
		col_pkg_select.pack_start (cell_pkg_select, false);

		col_pkg_select.set_cell_data_func (cell_pkg_select, (cell_layout, cell, model, iter) => {
			bool selected;
			Package pkg;
			model.get (iter, 0, out selected, 1, out pkg,-1);
			(cell as Gtk.CellRendererToggle).active = selected;
			//(cell as Gtk.CellRendererToggle).sensitive = !is_restore_view || (pkg.is_available && !pkg.is_installed);
			});

		cell_pkg_select.toggled.connect((path) => {
			TreeModel model = filter_packages;
			ListStore store = (ListStore) filter_packages.child_model;
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
		col_pkg_name.min_width = 150;
		tv_packages.append_column(col_pkg_name);

		CellRendererText cell_pkg_name = new CellRendererText ();
		cell_pkg_name.ellipsize = Pango.EllipsizeMode.END;
		col_pkg_name.pack_start (cell_pkg_name, false);

		col_pkg_name.set_cell_data_func (cell_pkg_name, (cell_layout, cell, model, iter) => {
			Package pkg;
			model.get (iter, 1, out pkg, -1);
			(cell as Gtk.CellRendererText).text = pkg.name;
			});

		//col_pkg_installed ----------------------

		TreeViewColumn col_pkg_installed = new TreeViewColumn();
		col_pkg_installed.title = _("Installed");
		col_pkg_installed.resizable = true;
		col_pkg_installed.min_width = 120;
		tv_packages.append_column(col_pkg_installed);

		CellRendererText cell_pkg_installed = new CellRendererText ();
		cell_pkg_installed.ellipsize = Pango.EllipsizeMode.END;
		col_pkg_installed.pack_start (cell_pkg_installed, false);

		col_pkg_installed.set_cell_data_func (cell_pkg_installed, (cell_layout, cell, model, iter) => {
			Package pkg;
			model.get (iter, 1, out pkg, -1);
			(cell as Gtk.CellRendererText).text = pkg.version_installed;
		});

		//col_pkg_latest ----------------------

		TreeViewColumn col_pkg_latest = new TreeViewColumn();
		col_pkg_latest.title = _("Latest");
		col_pkg_latest.resizable = true;
		col_pkg_latest.min_width = 120;
		tv_packages.append_column(col_pkg_latest);

		CellRendererText cell_pkg_latest = new CellRendererText ();
		cell_pkg_latest.ellipsize = Pango.EllipsizeMode.END;
		col_pkg_latest.pack_start (cell_pkg_latest, false);

		col_pkg_latest.set_cell_data_func (cell_pkg_latest, (cell_layout, cell, model, iter) => {
			Package pkg;
			model.get (iter, 1, out pkg, -1);
			(cell as Gtk.CellRendererText).text = pkg.version_available;
		});

		//col_pkg_desc ----------------------

		TreeViewColumn col_pkg_desc = new TreeViewColumn();
		col_pkg_desc.title = _("Description");
		col_pkg_desc.resizable = true;
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

	public void init_section_actions(){
		//hbox_pkg_actions
		hbox_pkg_actions = new Box (Orientation.HORIZONTAL, 6);
    vbox_actions.add (hbox_pkg_actions);

		//btn_backup_packages_select_all
		btn_backup_packages_select_all = new Gtk.Button.with_label (" " + _("Select All") + " ");
		hbox_pkg_actions.pack_start (btn_backup_packages_select_all, true, true, 0);
		btn_backup_packages_select_all.clicked.connect(()=>{
			foreach(Package pkg in pkg_list_all.values){
				pkg.is_selected = true;
			}
			tv_packages_refresh();
			});

		//btn_backup_packages_select_none
		btn_backup_packages_select_none = new Gtk.Button.with_label (" " + _("Select None") + " ");
		hbox_pkg_actions.pack_start (btn_backup_packages_select_none, true, true, 0);
		btn_backup_packages_select_none.clicked.connect(()=>{
			foreach(Package pkg in pkg_list_all.values){
				pkg.is_selected = false;
			}
			tv_packages_refresh();
			});

		//btn_backup_packages_exec
		btn_backup_packages_exec = new Gtk.Button.with_label (" <b>" + _("Backup") + "</b> ");
		btn_backup_packages_exec.no_show_all = true;
		hbox_pkg_actions.pack_start (btn_backup_packages_exec, true, true, 0);
		//btn_backup_packages_exec.clicked.connect(btn_backup_packages_exec_clicked);

		//btn_restore_packages_exec
		btn_restore_packages_exec = new Gtk.Button.with_label (" <b>" + _("Restore") + "</b> ");
		btn_restore_packages_exec.no_show_all = true;
		hbox_pkg_actions.pack_start (btn_restore_packages_exec, true, true, 0);
		//btn_restore_packages_exec.clicked.connect(btn_restore_packages_exec_clicked);

		//btn_backup_packages_cancel
		btn_backup_packages_cancel = new Gtk.Button.with_label (" " + _("Cancel") + " ");
		hbox_pkg_actions.pack_start (btn_backup_packages_cancel, true, true, 0);
		btn_backup_packages_cancel.clicked.connect(()=>{
			//show_home_page();
		});
	}

	public void init_section_status(){
		//lbl_status
		lbl_status = new Label ("");
		lbl_status.halign = Align.START;
		lbl_status.max_width_chars = 50;
		lbl_status.ellipsize = Pango.EllipsizeMode.END;
		//lbl_status.no_show_all = true;
		lbl_status.visible = false;
		lbl_status.margin_top = 3;
		lbl_status.margin_left = 3;
		lbl_status.margin_right = 3;
		vbox_main.pack_start (lbl_status, false, true, 0);

		//progressbar
		progressbar = new ProgressBar();
		progressbar.no_show_all = true;
		progressbar.margin_bottom = 3;
		progressbar.margin_left = 3;
		progressbar.margin_right = 3;
		progressbar.set_size_request(-1,25);
		//progressbar.pulse_step = 0.2;
		vbox_main.pack_start (progressbar, false, true, 0);
	}

	// refresh package information ----------------------------------------------

	private void refresh_package_information(){
		log_debug("call: refresh_package_information()");

		string status = _("Checking installed and available packages...");
		progress_begin(status);

		try {
			is_running = true;
			Thread.create<void> (refresh_package_information_thread, true);
		} catch (ThreadError e) {
			is_running = false;
			log_error (e.message);
		}

		while(is_running){
			update_progress(status);
			sleep(100);
		}

		refresh_all();
		progress_hide();

		//fix for column header resize issue
		gtk_do_events();
		//cmb_pkg_status.active = 1;
		//cmb_pkg_status.active = 0;
	}

	private void refresh_package_information_thread(){
		log_debug("call: refresh_package_information_thread()");

		App.read_package_info();
		pkg_list_all = App.pkg_list_master;

		count_available = pkg_list_all.size;
		count_installed = 0;
		foreach (Package pkg in pkg_list_all.values) {
			if (pkg.is_installed){
				count_installed++;
			}
		}

		is_running = false;
	}

	//refresh treeview and comboboxes -------------------------------------------

	private void refresh_all(){
		log_debug("call: refresh_all()");

		tv_ppa_refresh();
		tv_packages_refresh();
		update_status();

		//disconnect combo events
		cmb_filters_disconnect();

		/*cmb_pkg_level.show();
		cmb_pkg_level_refresh();*/

		cmb_pkg_status.show();
		cmb_pkg_status_refresh();

		cmb_pkg_section.show();
		cmb_pkg_section_refresh();

		//re-connect combo events
		cmb_filters_connect();
	}

	private void tv_packages_refresh(){
		log_debug("call: tv_packages_refresh()");

		ListStore model = new ListStore(4, typeof(bool), typeof(Package), typeof(Gdk.Pixbuf), typeof(string));

		var pkg_list = new ArrayList<Package>();
		if (pkg_list_all != null){
			foreach(Package pkg in pkg_list_all.values) {
				pkg_list.add(pkg);
			}
		}

		CompareDataFunc<Package> func = (a, b) => {
			return strcmp(a.name,b.name);
		};
		pkg_list.sort((owned)func);

		//status icons
		Gdk.Pixbuf pix_installed = null;
		Gdk.Pixbuf pix_available = null;
		Gdk.Pixbuf pix_unavailable = null;
		Gdk.Pixbuf pix_default = null;
		Gdk.Pixbuf pix_manual = null;
		Gdk.Pixbuf pix_status = null;

		try{
			pix_installed = new Gdk.Pixbuf.from_file(App.share_dir + "/aptik/images/item-green.png");
			pix_available = new Gdk.Pixbuf.from_file(App.share_dir + "/aptik/images/item-gray.png");
			pix_unavailable  = new Gdk.Pixbuf.from_file(App.share_dir + "/aptik/images/item-red.png");
			pix_default  = new Gdk.Pixbuf.from_file(App.share_dir + "/aptik/images/item-yellow.png");
			pix_manual  = new Gdk.Pixbuf.from_file(App.share_dir + "/aptik/images/item-green.png");
		}
    catch(Error e){
      log_error (e.message);
  	}

		TreeIter iter;
		string tt = "";
		int count = 0;
		foreach(Package pkg in pkg_list) {
			tt = "";

			if (pkg.is_installed){
				tt += _("Installed");
				pix_status = pix_installed;
			}
			else if (pkg.is_available){
				tt += _("Available") + ", " + _("Not Installed");
				pix_status = pix_available;
			}
			else{
				tt += _("Not Available! Check if PPA needs to be added");
				pix_status = pix_unavailable;
			}

			//add row
			model.append(out iter);
			model.set (iter, 0, pkg.is_selected);
			model.set (iter, 1, pkg);
			model.set (iter, 2, pix_status);
			model.set (iter, 3, tt);
		}

		filter_packages = new TreeModelFilter (model, null);
		filter_packages.set_visible_func(tv_packages_filter);
		tv_packages.set_model (filter_packages);
		tv_packages.columns_autosize();
	}

	private void tv_packages_refilter(){
		log_debug("call: tv_packages_refilter()");
		//gtk_set_busy(true,this);
		//vbox_actions.sensitive = false;

		filter_packages.refilter();
		//log_debug("end: refilter();");
		update_status();

		//gtk_set_busy(false,this);
		//vbox_actions.sensitive = true;
	}

	private bool tv_packages_filter (Gtk.TreeModel model, Gtk.TreeIter iter){
		Package pkg;
		model.get (iter, 1, out pkg, -1);
		bool display = true;

		string search_string = txt_filter.text.strip().down();
		if ((search_string != null) && (search_string.length > 0)){
			try{
				Regex regexName = new Regex (search_string, RegexCompileFlags.CASELESS);
				MatchInfo match_name;
				MatchInfo match_desc;
				if (!regexName.match (pkg.name, 0, out match_name) && !regexName.match (pkg.description, 0, out match_desc)) {
					return false;
				}
			}
			catch (Error e) {
				//ignore
			}
		}

		TreeModel ppa_model;
		TreeIter ppa_iter;
		Ppa ppa;
		var selection = tv_ppa.get_selection();
		selection.set_mode(SelectionMode.SINGLE);
		if (selection.count_selected_rows() == 1){
			selection.get_selected(out ppa_model, out ppa_iter);
			ppa_model.get (ppa_iter, 1, out ppa, -1);
			if (ppa.name != pkg.repo){
				return false;
			}
		}

		switch(cmb_pkg_status.active){
			case 0: //all
				//exclude nothing
				break;
			case 1: //Installed
				if (!pkg.is_installed){
					return false;
				}
				break;
			case 2: //Installed, Distribution
					if (!(pkg.is_installed && pkg.is_default)){
						return false;
					}
					break;
			case 3: //Installed, User
				if (!(pkg.is_installed && pkg.is_manual)){
					return false;
				}
				break;
			case 4: //Installed, Automatic
					if (!(pkg.is_installed && pkg.is_automatic)){
						return false;
					}
					break;
			case 5: //Installed, Updates
					if (!(pkg.is_installed && (pkg.version_available.length > 0) && (pkg.version_installed.length > 0)
					&& (strcmp(pkg.version_available,pkg.version_installed) > 0))){
						return false;
					}
					break;
			case 6: //NotInstalled
					if (pkg.is_installed){
						return false;
					}
					break;
			case 7: //selected
					if (!pkg.is_selected){
						return false;
					}
					break;
			case 8: //unselected
					if (pkg.is_selected){
						return false;
					}
					break;
		}

		switch(cmb_pkg_section.active){
			case 0: //all
				//exclude nothing
				break;
			default:
				if (pkg.section != gtk_combobox_get_value(cmb_pkg_section,0,""))
				{
					return false;
				}
				break;
		}

		return true;
	}

	private void tv_ppa_refresh(){
		ListStore model = new ListStore(4, typeof(bool), typeof(Ppa), typeof(Gdk.Pixbuf), typeof(string));

		//sort ppa list
		var ppa_list = new ArrayList<Ppa>();
		foreach(Ppa ppa in App.ppa_list_master.values) {
			ppa_list.add(ppa);
		}
		CompareDataFunc<Ppa> func = (a, b) => {
			return strcmp(a.name,b.name);
		};
		ppa_list.sort((owned)func);

		//status icons
		Gdk.Pixbuf pix_enabled = null;
		Gdk.Pixbuf pix_missing = null;
		Gdk.Pixbuf pix_unused = null;
		Gdk.Pixbuf pix_status = null;

		try{
			pix_enabled = new Gdk.Pixbuf.from_file (App.share_dir + "/aptik/images/item-green.png");
			pix_missing = new Gdk.Pixbuf.from_file (App.share_dir + "/aptik/images/item-gray.png");
			pix_unused = new Gdk.Pixbuf.from_file (App.share_dir + "/aptik/images/item-yellow.png");
		}
        catch(Error e){
	        log_error (e.message);
	    }

		TreeIter iter;
		string tt = "";
		foreach(Ppa ppa in ppa_list) {
			//check status
			if(ppa.is_installed){
				if (ppa.description.length > 0){
					pix_status = pix_enabled;
					tt = _("PPA is Enabled (%d installed packages)").printf(ppa.description.split(" ").length);
				}
				else{
					pix_status = pix_unused;
					tt = _("PPA is Enabled (%d installed packages)").printf(0);
				}
			}
			else{
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

	private void cmb_pkg_status_refresh(){
		log_debug("call: cmb_pkg_status_refresh()");
		var store = new ListStore(1, typeof(string));
		TreeIter iter;
		store.append(out iter);
		store.set (iter, 0, _("All"));
		store.append(out iter);
		store.set (iter, 0, _("Installed"));
		store.append(out iter);
		store.set (iter, 0, _("Installed (dist)"));
		store.append(out iter);
		store.set (iter, 0, _("Installed (user)"));
		store.append(out iter);
		store.set (iter, 0, _("Installed (auto)"));
		store.append(out iter);
		store.set (iter, 0, _("Installed (updates)"));
		store.append(out iter);
		store.set (iter, 0, _("Not Installed"));
		store.append(out iter);
		store.set (iter, 0, _("(selected)"));
		store.append(out iter);
		store.set (iter, 0, _("(unselected)"));
		cmb_pkg_status.set_model (store);
		cmb_pkg_status.active = 0;
	}

	private void cmb_pkg_section_refresh(){
		log_debug("call: cmb_pkg_section_refresh()");
		var store = new ListStore(1, typeof(string));
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

	// combobox events ----------------------------------------------------------

	public void cmb_filters_connect(){
		cmb_pkg_status.changed.connect(tv_packages_refilter);
		cmb_pkg_section.changed.connect(tv_packages_refilter);
		log_debug("connected: combo events");
	}

	public void cmb_filters_disconnect(){
		cmb_pkg_status.changed.disconnect(tv_packages_refilter);
		cmb_pkg_section.changed.disconnect(tv_packages_refilter);
		log_debug("disconnected: combo events");
	}

	// statusbar ----------------------------------------------------------

	private void progress_begin(string message = ""){
		//lbl_status.visible = true;
		progressbar.visible = true;

		App.progress_total = 0;
		progressbar.fraction = 0.0;
		lbl_status.label = message;

		vbox_actions.sensitive = false;

		gtk_set_busy(true, this);
		gtk_do_events();
	}

	private void progress_hide(string message = ""){
		//lbl_status.visible = false;
		progressbar.visible = false;

		vbox_actions.sensitive = true;

		update_status();

		gtk_set_busy(false, this);
		gtk_do_events();
	}

	private void progress_end(string message = ""){
		progressbar.fraction = 1.0;
		lbl_status.label = message;

		//lbl_status.visible = true;
		progressbar.visible = true;

		vbox_actions.sensitive = true;

		update_status();

		gtk_set_busy(false, this);
		gtk_do_events();
	}

	private void update_progress(string? message = null){
		if (App.progress_total > 0){
			progressbar.fraction = App.progress_count / (App.progress_total * 1.0);
			if (message != null){
				lbl_status.label = message + ": %s".printf(App.status_line);
			}
			gtk_do_events();
		}
		else{
			progressbar.pulse();
			if (message != null){
				lbl_status.label = message;
			}
			gtk_do_events();
		}
	}

	private void update_status(){
		count_listed = gtk_treeview_model_count(tv_packages.model);
		lbl_status.label =
		  "%d ".printf(count_listed) + _("packages listed")
		+ " | %d ".printf(count_available) + _("available")
		+ ", %d ".printf(count_installed) + _("installed");
	}
}
