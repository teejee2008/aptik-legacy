/*
 * DownloadWindow.vala
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

	private Gee.ArrayList<DownloadManager> download_list;
	private int job_count = 0;
	private int job_count_max = 3;
	private bool user_aborted = false;
	//private bool allow_close = false;
	
	// init

	public DownloadWindow.with_parent(Window parent, Gee.ArrayList<Package> pkg_download_list) {
		set_transient_for(parent);
		set_modal(true);
		//set_skip_taskbar_hint(true);
		//set_skip_pager_hint(true);
		window_position = WindowPosition.CENTER;

		//build download list ----------------------------
		
		App.status_line = "";
		App.progress_count = 0;
		App.progress_total = 0;

		download_list = new Gee.ArrayList<DownloadManager>();
		foreach(var pkg in pkg_download_list){
			var mgr = new DownloadManager(pkg.deb_file_name,"/var/cache/apt/archives","/var/cache/apt/archives/partial",pkg.deb_uri);
			mgr.size = pkg.deb_size;
			mgr.md5hash = pkg.deb_md5hash;
			download_list.add(mgr);
			
			App.progress_total += mgr.size;
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

		//col_status ------------------
		
		col_status = new TreeViewColumn();
		col_status.title = _("Status");
		col_status.fixed_width = 100;
		tv_pkg.append_column(col_status);
		
		CellRendererProgress2 cell_status = new CellRendererProgress2();
		cell_status.height = 15;
		cell_status.width = 100;
		col_status.pack_start (cell_status, false);
		
		col_status.set_cell_data_func (cell_status, (cell_layout, cell, model, iter) => {
			DownloadManager mgr;
			int progress_percent;
			model.get (iter, 0, out mgr, 1, out progress_percent, -1);
			(cell as CellRendererProgress2).value = progress_percent;
		});

		//col_size ----------------------

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
			DownloadManager mgr;
			model.get (iter, 0, out mgr, -1);
			//(cell as Gtk.CellRendererText).text = "%'.0f KB".printf((mgr.size / 1000.0));
			(cell as Gtk.CellRendererText).text = "%s".printf(format_file_size(mgr.size));
		});
		
		//col_name ----------------------

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
			DownloadManager mgr;
			model.get (iter, 0, out mgr, -1);
			(cell as Gtk.CellRendererText).text = mgr.name;
		});

		//col_ppa_desc ----------------------

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
			string desc;
			DownloadManager mgr;
			model.get (iter, 0, out mgr, 2, out desc, -1);
			if (mgr.status == DownloadManager.Status.STARTED){
				(cell as Gtk.CellRendererText).text = desc;
			}
			else{
				(cell as Gtk.CellRendererText).text = "";
			}
		});
	}

	private void tv_pkg_refresh() {
		var model = new Gtk.ListStore(3, typeof(DownloadManager),typeof(int),typeof(string));

		TreeIter iter;
		foreach(DownloadManager mgr in download_list) {
			//add row
			model.append(out iter);
			model.set (iter, 0, mgr, 1, 0, 2, "", -1);
		}

		tv_pkg.set_model(model);
		tv_pkg.columns_autosize();
	}
	
	// do work

	private void download_begin(){
		job_count = 0;
		update_timer_start();
		start_next();
	}

	private void start_next(){
		while ((job_count < job_count_max) && (!user_aborted)){
			bool assigned = false;
			foreach(var mgr in download_list){
				if (mgr.status == DownloadManager.Status.PENDING){
					mgr.download_complete.connect(download_complete_callback);
					mgr.download_begin();
					job_count++;
					assigned = true;
					break;
				}
			}
			if (!assigned){
				break; //nothing left to assign
			}
		}
	}

	private void download_complete_callback(){
		job_count--;
		start_next();
		bool all_done = true;
		foreach(var mgr in download_list){
			if (mgr.status != DownloadManager.Status.FINISHED){
				all_done = false;
				break;
			}
		}
		if (all_done){
			this.response(Gtk.ResponseType.OK);
		}
	}
	
	public void update_timer_start(){
		tmr_progress = Timeout.add(100, update_progress);
	}

	private bool update_progress(){
		if (tmr_progress > 0) {
			Source.remove(tmr_progress);
			tmr_progress = 0;
		}

		int64 downrate = 0;
		App.progress_count = 0;
		foreach(var mgr in download_list){
			App.progress_count += mgr.progress_count;
			if (mgr.status == DownloadManager.Status.STARTED){
				downrate += mgr.download_rate;
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
			tmr_progress = Timeout.add(1000, update_progress);
		}
		return true;
	}

	public void update_status_all(){
		var model = (Gtk.ListStore) tv_pkg.model;
		DownloadManager mgr = null;
		int index = -1;
		TreeIter iter;

		bool iterExists = model.get_iter_first (out iter);
		index++;

		while (iterExists){
			model.get (iter, 0, out mgr, -1);
			model.set (iter, 1, (int) (mgr.progress_percent));
			model.set (iter, 2, mgr.status_line);

			iterExists = model.iter_next (ref iter);
			index++;
		}
	}
	
	public void update_timer_stop(){
		if (tmr_progress > 0) {
			Source.remove(tmr_progress);
			tmr_progress = 0;
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


