/*
 * AptikConsole.vala
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

using GLib;
using Gtk;
using Gee;
using Json;

using TeeJee.Logging;
using TeeJee.FileSystem;
using TeeJee.JSON;
using TeeJee.ProcessManagement;
using TeeJee.GtkHelper;
using TeeJee.Multimedia;
using TeeJee.System;
using TeeJee.Misc;

public class AptikGtk : GLib.Object{

	public static int main (string[] args) {
		set_locale();
		
		Gtk.init(ref args);
		
		init_tmp();
		
		if (!user_is_admin()){
			string msg = _("Aptik needs admin access to backup and restore packages.") + "\n";
			msg += _("Please run the application as admin ('gksu aptik-gtk')");
			string title = _("Admin Access Required");
			gtk_messagebox(title, msg, null, true);
			exit(0);
		}
		
		App = new Main(args, true);

		var window = new MainWindow ();
		window.destroy.connect(Gtk.main_quit);
		window.show_all();
				
		//start event loop
		Gtk.main();

		App.exit_app();
		
		return 0;
	}
	
	private static void set_locale(){
		Intl.setlocale(GLib.LocaleCategory.MESSAGES, "aptik");
		Intl.textdomain(GETTEXT_PACKAGE);
		Intl.bind_textdomain_codeset(GETTEXT_PACKAGE, "utf-8");
		Intl.bindtextdomain(GETTEXT_PACKAGE, LOCALE_DIR);
	}
}
