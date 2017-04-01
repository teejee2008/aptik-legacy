/*
 * DownloadWindow.vala
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
using TeeJee.GtkHelper;

public class DownloadWindow : Dialog {
	private Gtk.Box vbox_main;
	private Gtk.Spinner spinner;
	private Gtk.Label lbl_msg;
	private Gtk.Label lbl_status;
	private Gtk.ProgressBar progressbar;

	private Gtk.TreeView tv_pkg;
	private Gtk.ScrolledWindow sw_pkg;
	private Gtk.TreeViewColumn col_name;
	private Gtk.TreeViewColumn col_size;
	private Gtk.TreeViewColumn col_desc;
	private Gtk.TreeViewColumn col_status;
	
	private uint tmr_init = 0;
	private uint tmr_progress = 0;
	//private uint tmr_close = 0;
	
	private int def_width = 560;
	private int def_height = 400;

	private DownloadTask mgr;
	private bool user_aborted = false;
	//private bool allow_close = false;

	private Gee.ArrayList<Package> package_list;
	
	// init

	public DownloadWindow.with_parent(Window parent, Gee.ArrayList<Package> _package_list) {
		set_transient_for(parent);
		set_modal(true);
		//set_skip_taskbar_hint(true);
		//set_skip_pager_hint(true);
		window_position = WindowPosition.CENTER;

		//build download list ----------------------------
		
		App.status_line = "";
		App.progress_count = 0;
		App.progress_total = 0;

		package_list = _package_list;

		mgr = new DownloadTask();
		mgr.status_in_kb = true;

		mgr.task_complete.connect(() => {
			this.response(Gtk.ResponseType.OK);
		});

		foreach(var pkg in package_list){
			var item = new DownloadItem(pkg.deb_uri, "/var/cache/apt/archives", pkg.deb_file_name);
			item.name = pkg.name;
			mgr.add_to_queue(item);
			
			App.progress_total += pkg.deb_size;
		}

		init_window();
	}

	public void init_window () {
		
		title = _("Download");
		icon = get_app_icon(16);
		set_default_size (def_width, def_height);
		resizable = true;
		deletable = false;
		
		//vbox_main
		vbox_main = get_content_area () as Gtk.Box;
		vbox_main.spacing = 6;
		vbox_main.margin = 6;

		var hbox_status = new Box (Orientation.HORIZONTAL, 6);
		hbox_status.margin_top = 6;
		vbox_main.add (hbox_status);

		//spinner
		spinner = new Gtk.Spinner();
		spinner.active = true;
		hbox_status.add(spinner);
		
		//lbl_msg
		lbl_msg = new Label (_("Downloading packages..."));
		lbl_msg.halign = Align.START;
		lbl_msg.ellipsize = Pango.EllipsizeMode.END;
		lbl_msg.max_width_chars = 50;
		hbox_status.add (lbl_msg);

		//progressbar
		progressbar = new ProgressBar();
		//progressbar.set_size_request(-1, 25);
		progressbar.pulse_step = 0.1;
		vbox_main.pack_start (progressbar, false, true, 0);

		//lbl_status
		lbl_status = new Label ("");
		lbl_status.halign = Align.START;
		lbl_status.ellipsize = Pango.EllipsizeMode.END;
		lbl_status.max_width_chars = 50;
		vbox_main.pack_start (lbl_status, false, true, 0);
		
		init_treeview();

		//actions
		var btn_ok = (Gtk.Button) add_button ("_Cancel", Gtk.ResponseType.CANCEL);
		btn_ok.clicked.connect(()=>{
			user_aborted = true;
			Posix.system("killall aria2c");
			this.response(Gtk.ResponseType.CANCEL);
		});
		
		show_all();
		gtk_do_events();
		
		tmr_init = Timeout.add(100, init_delayed);
	}

	private bool init_delayed() {
		/* any actions that need to run after window has been displayed */
		if (tmr_init > 0) {
			Source.remove(tmr_init);
			tmr_init = 0;
		}

		tv_pkg_refresh();
		
		download_begin();
		
		return false;
	}

	private void init_treeview() {
		//tv_pkg
		tv_pkg = new TreeView();
		tv_pkg.get_selection().mode = SelectionMode.MULTIPLE;
		tv_pkg.headers_clickable = true;
		tv_pkg.set_rules_hint (true);

		//sw_pkg
		sw_pkg = new ScrolledWindow(null, null);
		sw_pkg.set_shadow_type (ShadowType.ETCHED_IN);
		sw_pkg.add (tv_pkg);
		sw_pkg.expand = true;
		//sw_pkg.margin_top = 12;
		vbox_main.add(sw_pkg);

		//Status ------------------
		
		col_status = new TreeViewColumn();
		col_status.title = _("Status");
		col_status.fixed_width = 100;
		tv_pkg.append_column(col_status);
		
		CellRendererProgress2 cell_status = new CellRendererProgress2();
		cell_status.height = 15;
		cell_status.width = 100;
		col_status.pack_start (cell_status, false);
		
		col_status.set_cell_data_func (cell_status, (cell_layout, cell, model, iter) => {
			int percent;
			model.get (iter, 1, out percent, -1);
			(cell as CellRendererProgress2).value = percent;
		});

		//Size ----------------------

		col_size = new TreeViewColumn();
		col_size.title = _("Size");
		col_size.resizable = true;
		//col_size.min_width = 80;
		tv_pkg.append_column(col_size);

		CellRendererText cell_size = new CellRendererText ();
		//cell_size.ellipsize = Pango.EllipsizeMode.END;
		cell_size.xalign = (float) 1.0;
		col_size.pack_start (cell_size, false);

		col_size.set_cell_data_func (cell_size, (cell_layout, cell, model, iter) => {
			DownloadItem item;
			model.get (iter, 0, out item, -1);
			(cell as Gtk.CellRendererText).text = "%s".printf(format_file_size(item.bytes_total));
		});
		
		//Package ----------------------

		col_name = new TreeViewColumn();
		col_name.title = _("Package");
		col_name.resizable = true;
		col_name.expand = true;
		//col_name.min_width = 180;
		tv_pkg.append_column(col_name);

		CellRendererText cell_name = new CellRendererText ();
		cell_name.ellipsize = Pango.EllipsizeMode.END;
		col_name.pack_start (cell_name, false);

		col_name.set_cell_data_func (cell_name, (cell_layout, cell, model, iter) => {
			DownloadItem item;
			model.get (iter, 0, out item, -1);
			(cell as Gtk.CellRendererText).text = item.name;
		});

		//Progress ----------------------

		col_desc = new TreeViewColumn();
		col_desc.title = _("Progress");
		col_desc.resizable = true;
		col_desc.min_width = 200;
		//col_desc.expand = true;
		tv_pkg.append_column(col_desc);

		CellRendererText cell_desc = new CellRendererText ();
		//cell_desc.ellipsize = Pango.EllipsizeMode.END;
		col_desc.pack_start (cell_desc, false);

		col_desc.set_cell_data_func (cell_desc, (cell_layout, cell, model, iter) => {
			string txt;
			model.get (iter, 2, out txt, -1);
			(cell as Gtk.CellRendererText).text = txt;
		});
	}

	private void tv_pkg_refresh() {
		var model = new Gtk.ListStore(3, typeof(DownloadItem),typeof(int),typeof(string));

		TreeIter iter;
		foreach(var item in mgr.downloads) {
			//add row
			model.append(out iter);
			model.set (iter, 0, item, 1, 0, 2, "", -1);
		}

		tv_pkg.set_model(model);
		tv_pkg.columns_autosize();
	}
	
	// do work

	private void download_begin(){

		mgr.execute();
		
		update_timer_start();
	}

	public void update_timer_start(){
		tmr_progress = Timeout.add(1000, update_progress);
	}

	public void update_timer_stop(){
		if (tmr_progress > 0) {
			Source.remove(tmr_progress);
			tmr_progress = 0;
		}
	}
	
	private bool update_progress(){
		
		update_timer_stop();

		int64 downrate = 0;
		App.progress_count = 0;
		foreach(var item in mgr.downloads){
			App.progress_count += item.bytes_received;
			if (item.status == "RUNNING"){
				downrate += item.rate;
			}
		}

		update_progressbar();
		
		lbl_status.label = "Downloaded: %s / %s @ %s/s".printf(
			format_file_size(App.progress_count),
			format_file_size(App.progress_total),
			format_file_size(downrate));
		
		update_status_all();
		gtk_do_events();

		if (!user_aborted){
			update_timer_start();
		}
		return true;
	}

	public void update_status_all(){
		
		var model = (Gtk.ListStore) tv_pkg.model;
		int index = -1;
		TreeIter iter;

		bool iterExists = model.get_iter_first (out iter);
		index++;

		DownloadItem item;

		while (iterExists){
			model.get (iter, 0, out item, -1);
			model.set (iter, 1, (int) (item.progress * 100), -1);
			model.set (iter, 2, item.status_line, -1);

			//log_debug("progress=%d".printf(item.progress));

			iterExists = model.iter_next (ref iter);
			index++;
		}
	}

	// common

	public void update_progressbar(){
		double fraction = App.progress_count / (App.progress_total * 1.0);
		if (fraction > 1.0){
			fraction = 1.0;
		}
		progressbar.fraction = fraction;
	}
}


