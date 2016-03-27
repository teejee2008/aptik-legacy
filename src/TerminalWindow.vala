/*
 * TerminalWindow.vala
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

public class TerminalWindow : Gtk.Window {
	private Gtk.Box vbox_main;
	private Gtk.Button btn_cancel;
	private Vte.Terminal term;
	
	private uint tmr_init = 0;
	private int def_width = 800;
	private int def_height = 600;

	private bool allow_close = false;

	private Pid child_pid;
	private Gtk.Window parent_win;
	// init
	
	public TerminalWindow.with_parent(Gtk.Window parent) {
		set_transient_for(parent);
		set_modal(true);
		//set_skip_taskbar_hint(true);
		//set_skip_pager_hint(true);
		window_position = WindowPosition.CENTER;

		parent_win = parent;

		this.delete_event.connect(()=>{
			process_quit(child_pid);
			// allow window to close 
			//return false;

			// do not allow window to close 
			return true;
		});
		
		init_window();
	}

	public void init_window () {
		title = "";
		icon = get_app_icon(16);
		resizable = true;
		//deletable = false;
		
		// vbox_main
		vbox_main = new Box (Orientation.VERTICAL, 6);
		//vbox_main.margin = 12;
		vbox_main.set_size_request (def_width, def_height);
		add (vbox_main);

		term = new Vte.Terminal();
		term.expand = true;
		vbox_main.add(term);
		
		term.input_enabled = true;
		//term.pointer_autohide = true;
		term.backspace_binding = Vte.EraseBinding.AUTO;
		term.cursor_blink_mode = Vte.CursorBlinkMode.SYSTEM;
		term.cursor_shape = Vte.CursorShape.UNDERLINE;
		term.rewrap_on_resize = true;
		term.scroll_on_keystroke = true;
		term.scroll_on_output = true;

		var color = Gdk.RGBA();
		color.parse("#FFFFFF");
		term.set_color_foreground(color);

		color.parse("#404040");
		term.set_color_background(color);

		term.grab_focus();
		 
		/*// hbox
		var hbox = new Box (Orientation.HORIZONTAL, 6);
		hbox.set_homogeneous(true);
		//vbox_main.add (hbox);

		var sizegroup = new SizeGroup(SizeGroupMode.HORIZONTAL);

		// btn_cancel ---------------------------
		
		var button = new Gtk.Button.with_label (_("Cancel"));
		button.margin_top = 6;
		hbox.pack_start (button, false, false, 0);
		btn_cancel = button;
		sizegroup.add_widget(button);
		
		button.clicked.connect(()=>{
			App.cancelled = true;
			btn_cancel.sensitive = false;
		});

		//start_shell();
		*/
		
		show_all();

		//tmr_init = Timeout.add(100, init_delayed);
	}

	private bool init_delayed() {
		
		// any actions that need to run after window has been displayed
		
		if (tmr_init > 0) {
			Source.remove(tmr_init);
			tmr_init = 0;
		}

		return false;
	}

	public void start_shell(){
		string[] argv = new string[1];
		argv[0] = "/bin/sh";

		string[] env = Environ.get();

		try{
			term.spawn_sync(
				Vte.PtyFlags.DEFAULT, //pty_flags
				"/home/teejee", //working_directory
				argv, //argv
				env, //env
				GLib.SpawnFlags.SEARCH_PATH, //spawn_flags
				null, //child_setup
				out child_pid,
				null
			);
		}
		catch (Error e) {
			log_error (e.message);
		}
	}

	public void execute_command(string command){
		term.feed_child("%s\n".printf(command), -1);
	}

	public void execute_script(string script_path){
		//term.feed_child("%s".printf(script_path),-1);

		string[] argv = new string[1];
		//argv[0] = "/bin/sh";
		argv[0] = script_path;
		
		string[] env = Environ.get();

		try{
			term.spawn_sync(
				Vte.PtyFlags.DEFAULT, //pty_flags
				"/home/teejee", //working_directory
				argv, //argv
				env, //env
				GLib.SpawnFlags.SEARCH_PATH, //spawn_flags
				null, //child_setup
				out child_pid,
				null
			);

			term.watch_child(child_pid);
	
			term.child_exited.connect(script_exit);
		}
		catch (Error e) {
			log_error (e.message);
		}
	}

	public void script_exit(int status){
		this.hide();
		//destroying parent will display main window
		//no need to check status again
		parent_win.destroy();
	}
}


