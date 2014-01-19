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
using Soup;
using Json;

using TeeJee.Logging;
using TeeJee.FileSystem;
using TeeJee.DiskPartition;
using TeeJee.JSON;
using TeeJee.ProcessManagement;
using TeeJee.GtkHelper;
using TeeJee.Multimedia;
using TeeJee.System;
using TeeJee.Misc;

//extern void exit(int exit_code);

public class AptikConsole : GLib.Object{

	public static int main (string[] args) {
		set_locale();
		
		LOG_TIMESTAMP = false;
		
		App = new Main(args,false);
		
		var console =  new AptikConsole();
		bool is_success = console.parse_arguments(args);
		App.exit_app();
		
		return (is_success) ? 0 : 1;
	}

	private static void set_locale(){
		Intl.setlocale(GLib.LocaleCategory.MESSAGES, "aptik");
		Intl.textdomain(GETTEXT_PACKAGE);
		Intl.bind_textdomain_codeset(GETTEXT_PACKAGE, "utf-8");
		Intl.bindtextdomain(GETTEXT_PACKAGE, LOCALE_DIR);
	}
	
	public string help_message(){
		string msg = "\n" + AppName + " v" + AppVersion + " by Tony George (teejee2008@gmail.com)" + "\n";
		msg += "\n";
		msg += _("Syntax") + ": aptik [options]\n";
		msg += "\n";
		msg += _("Options") + ":\n";
		msg += "\n";
		msg += "  --list-available     " + _("List available packages") + "\n";
		msg += "  --list-installed     " + _("List installed packages") + "\n";
		msg += "  --list-top           " + _("List top-level installed packages") + "\n";
		msg += "  --list-manual        " + _("List top-level packages installed by user") + "\n";
		msg += "  --list-default       " + _("List default packages for linux distribution") + "\n";
		msg += "  --list-ppa           " + _("List PPAs") + "\n";
		msg += "  --list-themes        " + _("List themes in /usr/share/themes") + "\n";
		msg += "  --list-icons         " + _("List icon themes in /usr/share/icons") + "\n";
		
		msg += "  --backup-ppa         " + _("Backup list of PPAs") + "\n";
		msg += "  --backup-packages    " + _("Backup list of manual and installed packages") + "\n";
		msg += "  --backup-cache       " + _("Backup downloaded packages from APT cache") + "\n";		
		msg += "  --backup-themes      " + _("Backup themes from /usr/share/themes") + "\n";
		msg += "  --backup-icons       " + _("Backup icons from /usr/share/icons") + "\n";
		
		msg += "  --restore-ppa        " + _("Restore PPAs from file 'ppa.list'") + "\n";
		msg += "  --restore-packages   " + _("Restore packages from file 'packages.list'") + "\n";
		msg += "  --restore-cache      " + _("Restore downloaded packages to APT cache") + "\n";
		msg += "  --restore-themes     " + _("Restore themes to /usr/share/themes") + "\n";
		msg += "  --restore-icons      " + _("Restore icons to /usr/share/icons") + "\n";
		
		msg += "  --take-ownership     " + _("Take ownership of files in your home directory") + "\n";
		msg += "  --backup-dir         " + _("Backup directory (defaults to current directory)") + "\n";
		msg += "  --[show-]desc        " + _("Show package description if available") + "\n";
		msg += "  --yes                " + _("Assume Yes for all prompts") + "\n";
		msg += "  --h[elp]             " + _("Show all options") + "\n";
		msg += "\n";
		return msg;
	}
	
	public bool parse_arguments(string[] args){

		bool show_desc = false;
		bool no_prompt = false;

		if (args.length == 1){
			//no args given
			log_msg(help_message());
			return false;
		}
		
		//parse options
		for (int k = 1; k < args.length; k++) // Oth arg is app path 
		{
			switch (args[k].down()){
				case "--desc":
				case "--show-desc":
					show_desc = true;
					break;
				case "--backup-dir":
					k += 1;
					App.backup_dir = args[k] + (args[k].has_suffix("/") ? "" : "/");
					break;
				case "-y":
				case "--yes":
					no_prompt = true;
					break;
				case "--help":
				case "--h":
				case "-h":
					log_msg(help_message());
					return true;
			}
		}
			
		//parse commands
		for (int k = 1; k < args.length; k++) // Oth arg is app path 
		{
			switch (args[k].down()){
				case "--list-available":
					print_package_list(App.list_available(), show_desc);
					break;
					
				case "--list-installed":
					print_package_list(App.list_installed(false), show_desc);
					break;

				case "--list-top":
					print_package_list(App.list_top(), show_desc);
					break;
					
				case "--list-manual":
					print_package_list(App.list_manual(), show_desc);
					break;

				case "--list-default":
					print_package_list(App.list_default(), show_desc);
					break;

				case "--list-ppa":
				case "--list-ppas":
					print_ppa_list(App.list_ppa(), show_desc);
					break;

				case "--list-themes":
					print_theme_list(App.list_themes());
					break;

				case "--list-icons":
					print_theme_list(App.list_icons());
					break;
					
				case "--backup-ppa":
				case "--backup-ppas":
					string file_name = "ppa.list";
					bool is_success = App.save_ppa_list_selected(App.list_ppa());
					if (is_success){
						log_msg(_("File saved") + " '%s'".printf(file_name));
					}
					else{
						log_error(_("Failed to write") + " '%s'".printf(file_name));
					}
					break;
					
				case "--backup-package":
				case "--backup-packages":
					string file_name = "packages.list";
					bool is_success = App.save_package_list_selected(App.list_manual());
					if (is_success){
						log_msg(_("File saved") + " '%s'".printf(file_name));
					}
					else{
						log_error(_("Failed to write") + " '%s'".printf(file_name));
					}
					break;

				case "--backup-cache":
				case "--backup-apt-cache":
					App.backup_apt_cache();
					while(App.is_running){
						Thread.usleep ((ulong) 0.3 * 1000000);
					}
					break;
					
				case "--backup-themes":
					foreach(Theme theme in App.list_themes()){
						if (theme.is_selected){
							App.zip_theme(theme);
							while(App.is_running){
								Thread.usleep ((ulong) 0.3 * 1000000);
							}
						}
					}
					break;
					
				case "--backup-icons":
					foreach(Theme theme in App.list_icons()){
						if (theme.is_selected){
							App.zip_theme(theme);
							while(App.is_running){
								Thread.usleep ((ulong) 0.3 * 1000000);
							}
						}
					}
					break;
					
				case "--restore-ppa":
				case "--restore-ppas":
					restore_ppa();
					break;
					
				case "--restore-package":
				case "--restore-packages":
					restore_packages(no_prompt);
					break;

				case "--restore-cache":
				case "--restore-apt-cache":
					App.restore_apt_cache();
					while(App.is_running){
						Thread.usleep ((ulong) 0.3 * 1000000);
					}
					break;
					
				case "--restore-themes":
					foreach(Theme theme in App.get_themes_from_backup("theme")){
						if (theme.is_selected && !theme.is_installed){
							App.unzip_theme(theme);
							while(App.is_running){
								Thread.usleep ((ulong) 0.3 * 1000000);
							}
							App.update_permissions(theme.system_path);
						}
					}
					break;

				case "--restore-icons":
					foreach(Theme theme in App.get_themes_from_backup("icon")){
						if (theme.is_selected && !theme.is_installed){
							App.unzip_theme(theme);
							while(App.is_running){
								Thread.usleep ((ulong) 0.3 * 1000000);
							}
							App.update_permissions(theme.system_path);
						}
					}
					break;
					
				case "--take-ownership":
					App.take_ownership();
					break;
					
				case "--desc":
				case "--show-desc":
				case "-y":
				case "--yes":
				case "--help":
				case "--h":
				case "-h":
					//handled already - do nothing
					break;
					
				case "--backup-dir":
					k += 1;
					//handled already - do nothing
					break;
					
				default: 
					//unknown option - show help and exit
					log_error(_("Unknown option") + ": %s".printf(args[k]));
					log_msg(help_message());
					return false;
			}
		}

		return true;
	}

	public void print_package_list(Gee.HashMap<string,Package> package_list, bool show_desc){
		var pkg_list = new ArrayList<Package>();
		foreach(Package pkg in package_list.values) {
			pkg_list.add(pkg);
		}
		CompareFunc<Package> func = (a, b) => {
			return strcmp(a.name,b.name);
		};
		pkg_list.sort(func);

		int max_length = 0;
		foreach(Package pkg in pkg_list){
			if (pkg.name.length > max_length){
				max_length = pkg.name.length;
			}
		}
		string fmt = "%%-%ds".printf(max_length + 2);
		
		if (show_desc){
			fmt = fmt + "%s";
			foreach(Package pkg in pkg_list){
				log_msg(fmt.printf(pkg.name, pkg.description));
			}
		}
		else{
			foreach(Package pkg in pkg_list){
				log_msg(fmt.printf(pkg.name));
			}
		}
	}

	public void print_ppa_list(Gee.HashMap<string,Ppa> ppa_list_to_print, bool show_desc){
		var ppa_list = new ArrayList<Ppa>();
		foreach(Ppa ppa in ppa_list_to_print.values) {
			ppa_list.add(ppa);
		}
		CompareFunc<Ppa> func = (a, b) => {
			return strcmp(a.name,b.name);
		};
		ppa_list.sort(func);

		int max_length = 0;
		foreach(Ppa ppa in ppa_list){
			if (ppa.name.length > max_length){
				max_length = ppa.name.length;
			}
		}
		string fmt = "%%-%ds".printf(max_length + 2);
		
		if (show_desc){
			fmt = fmt + "%s";
			foreach(Ppa ppa in ppa_list){
				log_msg(fmt.printf(ppa.name, ppa.description));
			}
		}
		else{
			foreach(Ppa ppa in ppa_list){
				log_msg(fmt.printf(ppa.name));
			}
		}
	}

	public void print_theme_list(Gee.ArrayList<Theme> theme_list){
		int max_length = 0;
		foreach(Theme theme in theme_list){
			if (theme.name.length > max_length){
				max_length = theme.name.length;
			}
		}
		string fmt = "%%-%ds".printf(max_length + 2);
		foreach(Theme theme in theme_list){
			log_msg(fmt.printf(theme.name));
		}
	}
	
	public bool restore_packages(bool no_prompt){
		if (!App.check_backup_file("packages.list")){
			return false;
		}
		
		string list_found = "";
		string list_missing = "";

		var pkg_list = App.read_package_list(App.list_all());
		if (pkg_list.size == 0){
			return false;
		}
		
		foreach(Package pkg in pkg_list.values){
			if (pkg.is_selected && pkg.is_available && !pkg.is_installed){
				list_found += " %s".printf(pkg.name);
			}
		}
		foreach(Package pkg in pkg_list.values){
			if (pkg.is_selected && !pkg.is_available && !pkg.is_installed){
				list_missing += " %s".printf(pkg.name);
			}
		}
		
		list_found = list_found.strip();
		list_missing = list_missing.strip();
		
		if (list_missing.length > 0){
			log_msg(_("Following packages are NOT available") + ":\n%s\n".printf(list_missing));
		}
		
		if (list_found.length > 0){
			log_msg(_("Following packages will be installed") + ":\n%s\n".printf(list_found));
			Posix.system("sudo apt-get%s install %s".printf((no_prompt)? " -y" : "", list_found));
		}
		else{
			log_msg(_("Selected packages are already installed"));
		}

		return true;
	}

	public bool restore_ppa(){
		if (!App.check_backup_file("ppa.list")){
			return false;
		}
		
		var ppa_list = App.read_ppa_list();
		
		bool run_apt_update = false;
		foreach(Ppa ppa in ppa_list.values){
			if (ppa.is_selected && !ppa.is_installed){
				log_msg(_("Adding PPA") + " '%s'".printf(ppa.name));
				
				Posix.system("sudo apt-add-repository -y ppa:%s".printf(ppa.name));
				//exit code is not reliable (always 0?)
				
				run_apt_update = true;
				log_msg("");
			}
		}			
		
		if (run_apt_update){
			log_msg(_("Updating Package Information..."));
			Posix.system("sudo apt-get -y update");
		}
		
		return true;
	}
}
