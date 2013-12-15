/*
 * Main.vala
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

public Main App;
public const string AppName = "Aptik";
public const string AppVersion = "1.0";
public const string AppAuthor = "Tony George";
public const string AppAuthorEmail = "teejee2008@gmail.com";

const string GETTEXT_PACKAGE = "";
const string LOCALE_DIR = "/usr/share/locale";

//extern void exit(int exit_code);

public class Main : GLib.Object{
	public string temp_dir = "/tmp/aptik";

	public static int main (string[] args) {
		set_locale();

		App = new Main(args);
		
		bool success = App.parse_arguments(args);
		
		App.exit_app();
		
		return (success) ? 0 : 1;
	}
	
	private static void set_locale(){
		Intl.setlocale(GLib.LocaleCategory.MESSAGES, "aptik");
		Intl.textdomain(GETTEXT_PACKAGE);
		Intl.bind_textdomain_codeset(GETTEXT_PACKAGE, "utf-8");
		Intl.bindtextdomain(GETTEXT_PACKAGE, LOCALE_DIR);
	}
	
	public Main(string[] args){
		try{
			var f = File.new_for_path(temp_dir);
			if (f.query_exists()){
				f.delete();
			}
			f.make_directory_with_parents();
		}
		catch (Error e) {
			log_error (e.message);
		}
	}

	public string help_message(){
		string msg = "\n" + AppName + " v" + AppVersion + " by Tony George (teejee2008@gmail.com)" + "\n";
		msg += "\n";
		msg += _("Syntax") + ": aptik [options]\n";
		msg += "\n";
		msg += _("Options") + ":\n";
		msg += "\n";
		msg += "  --list-all           " + _("List available packages") + "\n";
		msg += "  --list-installed     " + _("List installed packages") + "\n";
		msg += "  --list-top           " + _("List top-level installed packages") + "\n";
		msg += "  --list-user          " + _("List top-level packages installed by user") + "\n";
		msg += "  --list-default       " + _("List default packages for linux distribution") + "\n";
		msg += "  --list-ppa           " + _("List Personal Package Archives (PPAs)") + "\n";
		msg += "  --backup-ppa         " + _("Create a backup list of PPAs") + "\n";
		msg += "  --backup-packages    " + _("Create a backup list of packages installed by user") + "\n";
		msg += "  --restore-ppa        " + _("Restore PPAs from file 'ppa.list'") + "\n";
		msg += "  --restore-packages   " + _("Reinstall missing packages from file 'packages.list'") + "\n";
		msg += "  --backup-cache       " + _("Backup downloaded packages from APT cache") + "\n";
		msg += "  --restore-cache      " + _("Restore packages to APT cache") + "\n";
		msg += "  --fix-ownership      " + _("Makes current user the owner of all files in her home directory") + "\n";
		msg += "  --[show-]desc        " + _("Show package description if available") + "\n";
		msg += "  --yes                " + _("Assume Yes for all prompts") + "\n";
		msg += "  --h[elp]             " + _("Show all options") + "\n";
		msg += "\n";
		return msg;
	}
	
	private bool parse_arguments(string[] args){
		
		bool show_desc = false;
		bool no_prompt = false;
		
		Gee.ArrayList<Package> list = null;
		
		if (args.length == 1){
			//no args given
			stdout.printf(help_message());
			return false;
		}
		
		for (int k = 1; k < args.length; k++) // Oth arg is app path 
		{
			switch (args[k].down()){
				case "--desc":
				case "--show-desc":
					show_desc = true;
					break;
				case "-y":
				case "--yes":
					no_prompt = true;
					break;
				case "--help":
				case "--h":
				case "-h":
					stdout.printf(help_message());
					return true;
			}
		}
		
		for (int k = 1; k < args.length; k++) // Oth arg is app path 
		{
			switch (args[k].down()){
				case "--list-all":
					list = list_all();
					break;
				case "--list-installed":
					list = list_installed();
					break;

				case "--list-top":
					list = list_top();
					break;
					
				case "--list-user":
					list = list_user();
					break;

				case "--list-default":
					list = list_default();
					break;

				case "--list-ppa":
				case "--list-ppas":
					foreach(string ppa in list_ppa()){
						stdout.printf("%s\n".printf(ppa));
					}
					break;

				case "--backup-ppa":
				case "--backup-ppas":
					backup_ppa();
					break;
					
				case "--backup-package":
				case "--backup-packages":
					backup_packages();
					break;

				case "--restore-ppa":
				case "--restore-ppas":
					restore_ppa();
					break;
					
				case "--restore-package":
				case "--restore-packages":
					restore_packages(no_prompt);
					break;
				
				case "--backup-cache":
				case "--backup-apt-cache":
					backup_apt_cache();
					break;
				
				case "--restore-cache":
				case "--restore-apt-cache":
					restore_apt_cache();
					break;
					
				case "--fix-ownership":
					fix_home_ownership();
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
					
				default: 
					//unknown option - show help and exit
					stdout.printf(_("Unknown option") + ": %s\n".printf(args[k]));
					stdout.printf(help_message());
					return false;
			}
		}
		
		for (int k = 1; k < args.length; k++) // Oth arg is app path 
		{
			switch (args[k].down()){
				case "--list-all":
				case "--list-installed":
				case "--list-top":
				case "--list-user":
				case "--list-default":
					int max_length = 0;
					foreach(Package pkg in list){
						if (pkg.name.length > max_length){
							max_length = pkg.name.length;
						}
					}
					string fmt = "%%-%ds".printf(max_length + 2);
					
					if (show_desc){
						fmt = fmt + "%s\n";
						foreach(Package pkg in list){
							stdout.printf(fmt.printf(pkg.name, pkg.description));
						}
					}
					else{
						fmt = fmt + "\n";
						foreach(Package pkg in list){
							stdout.printf(fmt.printf(pkg.name));
						}
					}
					
					break;
					
				case "--list-ppa":
					//do nothing
					break;
			}
		}
		
		return true;
	}
	
	private Gee.ArrayList<Package> list_all(){
		var pkg_list = new Gee.ArrayList<Package>();
		
		string txt = execute_command_sync_get_output("aptitude search --disable-columns -F '%p|%d' '.'");
		
		foreach(string line in txt.split("\n")){
			if (line.strip() == "") { continue; }
			if (line.index_of("|") == -1) { continue; }

			Package pkg = new Package();
			pkg_list.add(pkg);
			
			pkg.name = line.split("|")[0].strip();
			pkg.description = line.split("|")[1].strip();
		}
		
		return pkg_list;
	}

	private Gee.ArrayList<Package> list_installed(){
		var pkg_list = new Gee.ArrayList<Package>();
		
		string txt = execute_command_sync_get_output("aptitude search --disable-columns -F '%p|%d' '?installed'");
		
		foreach(string line in txt.split("\n")){
			if (line.strip() == "") { continue; }
			if (line.index_of("|") == -1) { continue; }

			Package pkg = new Package();
			pkg_list.add(pkg);
			
			pkg.name = line.split("|")[0].strip();
			pkg.description = line.split("|")[1].strip();
		}
		
		return pkg_list;
	}

	private Gee.ArrayList<Package> list_top(){
		var pkg_list = new Gee.ArrayList<Package>();
		
		string txt = execute_command_sync_get_output("aptitude search --disable-columns -F '%p|%d' '?installed !?automatic !?reverse-depends(?installed)'");
		
		foreach(string line in txt.split("\n")){
			if (line.strip() == "") { continue; }
			if (line.index_of("|") == -1) { continue; }

			Package pkg = new Package();
			pkg_list.add(pkg);
			
			pkg.name = line.split("|")[0].strip();
			pkg.description = line.split("|")[1].strip();
		}
		
		return pkg_list;
	}
	
	private Gee.ArrayList<Package> list_default(){
		var pkg_list = new Gee.ArrayList<Package>();
		
		string txt = "";
		execute_command_script_sync("gzip -dc /var/log/installer/initial-status.gz | sed -n 's/^Package: //p' | sort | uniq", out txt, null);
		
		foreach(string line in txt.split("\n")){
			if (line.strip() == "") { continue; }
			Package pkg = new Package();
			pkg_list.add (pkg);
			pkg.name = line.strip();
		}
		
		return pkg_list;
	}
	
	private Gee.ArrayList<Package> list_user(){
		var pkg_list_default = list_default();
		var pkg_list_top = list_top();
		var pkg_list = new Gee.ArrayList<Package>();
		
		foreach(Package pkg in pkg_list_top){
			bool is_default = false;
			foreach(Package pkg_def in pkg_list_default){
				if (pkg_def.name == pkg.name){
					is_default = true;
					break;
				}
			}
			if (!is_default){
				pkg_list.add(pkg);
			}
		}
		
		return pkg_list;
	}

	private void backup_packages(){
		string pkg_list = "";
		foreach(Package pkg in list_user()){
			pkg_list += "%s\n".printf(pkg.name);
		}
		write_file("packages.list",pkg_list);
		stdout.printf(_("File saved") + ": packages.list\n");
	}
	
	private Gee.ArrayList<string> list_ppa(){
		var ppa_list = new Gee.ArrayList<string>();
		
		string sh =
"""
for listfile in `find /etc/apt/ -name \*.list`; do
    grep -o "^deb http://ppa.launchpad.net/[a-z0-9\-]\+/[a-z0-9.\-]\+" $listfile | while read entry ; do
        user=`echo $entry | cut -d/ -f4`
        ppa=`echo $entry | cut -d/ -f5`
        echo "ppa:$user/$ppa"
    done
done
""";
		string txt = "";
		execute_command_script_sync(sh, out txt, null);
		
		foreach(string line in txt.split("\n")){
			string ppa = line.strip();
			if (ppa.length > 0) {
				ppa_list.add(line.strip());
			}
		}
		
		return ppa_list;
	}

	private void backup_ppa(){
		string ppa_list = "";
		//string script ="#!/bin/bash";
		
		foreach(string ppa in list_ppa()){
			ppa_list += "%s\n".printf(ppa);
			//script += "sudo apt-add-repository -y %s\n".printf(ppa);
		}
		//script += "sudo apt-get update";
		
		write_file("ppa.list",ppa_list);
		//write_file("ppa-restore.sh",script);
		
		//chmod("ppa-restore.sh","u+x");
		
		stdout.printf(_("File saved") + ": ppa.list\n");
	}
	
	private bool restore_ppa(){
		string ppa_list = "ppa.list";
		
		var f = File.new_for_path(ppa_list);
		if (!f.query_exists()){
			stderr.printf("[" + _("Error") + "] " + _("File not found in current directory") + ": ppa.list\n");
			return false;
		}	
		
		int count_success = 0;
		int count_total = 0;
		foreach(string line in read_file(ppa_list).split("\n")){
			if (line.strip() == "") { continue; }
			string ppa = line.strip();

			count_total++;
			
			stdout.printf(_("Adding") + " '%s'\n".printf(ppa));
			stdout.flush();
			
			int exit_code = Posix.system("sudo apt-add-repository -y %s".printf(ppa));

			if (exit_code == 0){
				count_success++;
			}

			stdout.printf("\n");
		}			
		
		Posix.system("sudo apt-get update");
		
		stdout.printf("%d/%d ".printf(count_success, count_total) + _("PPA added successfully") + "\n");
		
		return true;
	}

	private bool restore_packages(bool no_prompt){
		stdout.printf(_("Checking installed packages"));
		stdout.flush();
		var pkg_list_installed = list_installed();	
		stdout.printf(": %d\n".printf(pkg_list_installed.size));
		stdout.flush();
		
		stdout.printf(_("Checking available packages"));
		stdout.flush();
		var pkg_list_all = list_all();
		stdout.printf(": %d\n\n".printf(pkg_list_all.size));
		stdout.flush();
		
		string pkg_list = "packages.list";
		
		var f = File.new_for_path(pkg_list);
		if (!f.query_exists()){
			stderr.printf("[" + _("Error") + "] " + _("File not found in current directory") + ": packages.list\n");
			return false;
		}
		
		string list_found = "";
		string list_missing = "";
		int count_found = 0;
		int count_missing = 0;
		foreach(string line in read_file(pkg_list).split("\n")){
			if (line.strip() == "") { continue; }
			string pkg_name = line.strip();
			
			bool found = false;
			foreach(Package pkg in pkg_list_installed){
				if (pkg.name == pkg_name){
					found = true;
					break;
				}
			}
			if (found){
				continue;
			}
			
			found = false;
			foreach(Package pkg in pkg_list_all){
				if (pkg.name == pkg_name){
					found = true;
					count_found++;
					list_found += " %s".printf(pkg_name);
					break;
				}
			}
			
			if (!found){
				count_missing++;
				list_missing += " %s".printf(pkg_name);
			}
		}	
		
		list_found = list_found.strip();
		list_missing = list_missing.strip();
		
		if (count_missing > 0){
			stdout.printf(_("Following packages are not available") + ":\n%s\n\n".printf(list_missing));
			stdout.flush();
		}
		
		if (count_found > 0){
			stdout.printf(_("Following packages will be installed") + ":\n%s\n\n".printf(list_found));
			stdout.flush();

			Posix.system("sudo apt-get%s install %s".printf((no_prompt)? " -y" : "", list_found));
		}
		else{
			stdout.printf(_("Selected packages are already installed") + "\n");
			stdout.flush();
		}

		return true;
	}

	private bool backup_apt_cache(){
		string archives_dir = "archives";
		int exit_code;
		try {
			//create 'archives' directory
			var f = File.new_for_path(archives_dir);
			if (!f.query_exists()){
				f.make_directory_with_parents();
			}
			
			//run rsync
			string cmd = "rsync -ai --numeric-ids";
			cmd += " --exclude=lock --exclude=partial/";
			cmd += " %s %s".printf("/var/cache/apt/archives/", "archives/");
			Process.spawn_command_line_sync(cmd, null, null, out exit_code);
			
			return true;
		}
		catch (Error e){
			log_error (e.message);
			return false;
		}
	}
	
	private bool restore_apt_cache(){
		string archives_dir = "archives";
		int exit_code;
		
		try {
			//check 'archives' directory
			var f = File.new_for_path(archives_dir);
			if (!f.query_exists()){
				stderr.printf("[" + _("Error") + "] " + _("Cache backup not found in current directory") + "\n");
				return false;
			}
			
			//run rsync
			string cmd = "sudo rsync -ai --numeric-ids";
			cmd += " --exclude=lock --exclude=partial/";
			cmd += " %s %s".printf("archives/","/var/cache/apt/archives/");
			Process.spawn_command_line_sync(cmd, null, null, out exit_code);
			
			return true;
		}
		catch (Error e){
			log_error (e.message);
			return false;
		}
	}

	private bool fix_home_ownership(){
		string home = Environment.get_home_dir();
		string user = get_user_login();

		try {
			string cmd = "sudo chown %s -R %s".printf(user,home);
			int exit_code;
			Process.spawn_command_line_sync(cmd, null, null, out exit_code);
			return true;
		}
		catch (Error e){
			log_error (e.message);
			return false;
		}
	}
	
	private void exit_app(){
		try{
			var f = File.new_for_path(temp_dir);
			if (f.query_exists()){
				f.delete();
			}
		}
		catch (Error e) {
			log_error (e.message);
		}
	}

}

public class Package : GLib.Object{
	public string name = "";
	public string description = "";
}
