/*
 * ProgressWindow.vala
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

public class ProgressWindow : Window {
	private Gtk.Box vbox_main;

	private uint tmr_init = 0;
	private uint tmr_close = 0;
	private int def_width = 400;
	private int def_height = 50;
	
	private ProgressBar progressbar;
	private Label lbl_status;
	private string status_message;
	// init
	
	public ProgressWindow.with_parent(Window parent, string message) {
		set_transient_for(parent);
		set_modal(true);
		set_skip_taskbar_hint(true);
		set_skip_pager_hint(true);
		window_position = WindowPosition.CENTER_ON_PARENT;

		App.status_line = "";
		App.progress_count = 0;
		App.progress_total = 0;
		
		status_message = message;
		
		init_window();
	}

	public void init_window () {
		title = "";
		window_position = WindowPosition.CENTER;
		resizable = false;
		deletable = false;
		
		//vbox_main
		vbox_main = new Box (Orientation.VERTICAL, 6);
		vbox_main.margin = 6;
		vbox_main.set_size_request (def_width, def_height);
		add (vbox_main);

		//lbl_status
		lbl_status = new Label (status_message);
		lbl_status.halign = Align.START;
		lbl_status.ellipsize = Pango.EllipsizeMode.END;
		lbl_status.max_width_chars = 50;
		lbl_status.margin_bottom = 3;
		lbl_status.margin_left = 3;
		lbl_status.margin_right = 3;
		vbox_main.pack_start (lbl_status, false, true, 0);

		//progressbar
		progressbar = new ProgressBar();
		progressbar.margin_bottom = 3;
		progressbar.margin_left = 3;
		progressbar.margin_right = 3;
		//progressbar.set_size_request(-1, 25);
		//progressbar.pulse_step = 0.2;
		vbox_main.pack_start (progressbar, false, true, 0);
		
		show_all();

		tmr_init = Timeout.add(100, init_delayed);
	}

	private bool init_delayed() {
		/* any actions that need to run after window has been displayed */
		if (tmr_init > 0) {
			Source.remove(tmr_init);
			tmr_init = 0;
		}

		//start();
		
		return false;
	}


	// common
	
	public void finish(string message = "") {
		progressbar.fraction = 1.0;
		lbl_status.label = message;
		
		gtk_do_events();
		auto_close_window();
	}

	private void auto_close_window() {

		tmr_close = Timeout.add(2000, ()=>{
			if (tmr_init > 0) {
				Source.remove(tmr_init);
				tmr_init = 0;
			}

			this.close();
			return false;
		});
	}
	
	public void update_progress(string message) {
		if (App.progress_total > 0) {
			progressbar.fraction = App.progress_count / (App.progress_total * 1.0);
			lbl_status.label = message + ": %s".printf(App.status_line);
			gtk_do_events();
			Thread.usleep ((ulong) 0.1 * 1000000);
		}
		else {
			progressbar.pulse();
			lbl_status.label = message;
			gtk_do_events();
			Thread.usleep ((ulong) 200000);
		}
	}

}


