/*
 * LogWindow.vala
 * 
 * Copyright 2012 Tony George <teejee2008@gmail.com>
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

using TeeJee.Logging;
using TeeJee.FileSystem;
using TeeJee.DiskPartition;
using TeeJee.JSON;
using TeeJee.ProcessManagement;
using TeeJee.GtkHelper;
using TeeJee.Multimedia;
using TeeJee.System;
using TeeJee.Misc;

public class LogWindow : Dialog {

	private Box vbox_main;
	private Box hbox_action;
	private Button btn_ok;
	private Button btn_yes;
	private Button btn_no;
	private TreeView tv_log;
	private ScrolledWindow sw_log;
	private string log_msg;
	private Label lblPrompt;
	
	public LogWindow () {
		title = _("Log");
		deletable = false;
		modal = true;
		window_position = WindowPosition.CENTER_ON_PARENT;
        set_destroy_with_parent (true);
		set_default_size (700, 500);	
		skip_taskbar_hint = true;

		// get content area
		vbox_main = get_content_area();
		vbox_main.margin = 6;
				
		//tvInfo
		tv_log = new TreeView();
		tv_log.headers_visible = false;
		tv_log.insert_column_with_attributes(-1, _("Line"), new CellRendererText(), "text", 0);
		sw_log = new ScrolledWindow(tv_log.get_hadjustment(), tv_log.get_vadjustment());
		sw_log.set_shadow_type(ShadowType.ETCHED_IN);
		sw_log.add(tv_log);
		sw_log.set_size_request(-1, 200);
		vbox_main.pack_start(sw_log, true, true, 0);
		
		//lblPrompt
		lblPrompt =  new Label("");
		lblPrompt.halign = Align.START;
		lblPrompt.margin_top = 6;
		vbox_main.add(lblPrompt);
		
		//get action area
		hbox_action = (Box) get_action_area();
		
        //btn_ok
        btn_ok = new Button();
        hbox_action.add(btn_ok);
        btn_ok.set_label (" " + _("Ok"));
        Gtk.Image img_ok = new Image.from_stock("gtk-ok", Gtk.IconSize.BUTTON);
		btn_ok.set_image(img_ok);
        btn_ok.clicked.connect(() => {  response(Gtk.ResponseType.OK);  });

        //btn_yes
        btn_yes = new Button();
        hbox_action.add(btn_yes);
        btn_yes.set_label (" " + _("Yes"));
        btn_yes.no_show_all = true;
        Gtk.Image img_yes = new Image.from_stock("gtk-yes", Gtk.IconSize.BUTTON);
		btn_yes.set_image(img_yes);
        btn_yes.clicked.connect(() => {  response(Gtk.ResponseType.YES);  destroy(); });
        
        //btn_no
        btn_no = new Button();
        hbox_action.add(btn_no);
        btn_no.set_label (" " + _("No"));
        btn_no.no_show_all = true;
        Gtk.Image img_no = new Image.from_stock("gtk-no", Gtk.IconSize.BUTTON);
		btn_no.set_image(img_no);
        btn_no.clicked.connect(() => {  response(Gtk.ResponseType.NO);  });
	}
	
	public void set_log_msg(string _log_msg){
		log_msg = _log_msg;
		
		ListStore store = new ListStore (1, typeof(string));

		TreeIter iter;
		foreach (string line in log_msg.split ("\n")){
			store.append(out iter);
			store.set(iter, 0, line);
		}
		
		tv_log.set_model(store);
		tv_log.expand_all();
	}
	
	public void set_prompt_msg(string prompt_msg){
		lblPrompt.label = prompt_msg;
	}

	public void show_yes_no(){
		btn_ok.visible = false;
		btn_yes.visible = true;
		btn_no.visible = true;
	}
}
