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
public const string AppVersion = "1.2";
public const string AppAuthor = "Tony George";
public const string AppAuthorEmail = "teejee2008@gmail.com";

const string GETTEXT_PACKAGE = "";
const string LOCALE_DIR = "/usr/share/locale";

//extern void exit(int exit_code);

public class Main : GLib.Object{
	public string temp_dir = "";
	public string backup_dir = "";
	public string share_dir = "/usr/share";
	public bool gui_mode = false;//TODO:Remove

	public string err_line;
	public string out_line;
	public string status_line;
	public string status_summary;
	public Gee.ArrayList<string> stdout_lines;
	public Gee.ArrayList<string> stderr_lines;
	public Pid proc_id;
	public DataInputStream dis_out;
	public DataInputStream dis_err;
	public int progress_count;
	public int progress_total;
	public bool is_running;

	private Regex rex_aptget_download;
	private Regex rex_pkg_installed;
	private MatchInfo match;
			
	public Main(string[] args){
		try{
			temp_dir = get_temp_file_path();
			
			var f = File.new_for_path(temp_dir);
			if (f.query_exists()){
				Posix.system("sudo rm -rf %s".printf(temp_dir));
			}
			f.make_directory_with_parents();

			rex_aptget_download = new Regex("""([^%]*)%[ \t]*\[([^\]]*)\]""");
		}
		catch (Error e) {
			log_error (e.message);
		}
	}
	
	/* Common */
	
	private bool check_backup_file(string file_name){
		string backup_file = backup_dir + (backup_dir.has_suffix("/") ? "" : "/") + file_name;
		var f = File.new_for_path(backup_file);
		if (!f.query_exists()){
			log_error(_("File not found in backup directory") + ": '%s'".printf(file_name));
			return false;
		}
		else{
			return true;
		}
	}
	
	/* Package selections */
	
	public Gee.HashMap<string,Package> list_all(){
		var pkg_list_available = list_available();
		var pkg_list_installed = list_installed(true);
		var pkg_list_default = list_default();
		var pkg_list_top = list_top();
		var pkg_list_manual = list_manual();
		
		var pkg_list_all = pkg_list_available;
		
		foreach(Package pkg in pkg_list_installed.values){
			if (pkg_list_all.has_key(pkg.name)){
				pkg_list_all[pkg.name].is_installed = true;
				pkg_list_all[pkg.name].server = pkg.server;
				pkg_list_all[pkg.name].repo = pkg.repo;
			}
		}

		foreach(Package pkg in pkg_list_default.values){
			if (pkg_list_all.has_key(pkg.name)){
				pkg_list_all[pkg.name].is_default = true;
			}
		}

		foreach(Package pkg in pkg_list_top.values){
			if (pkg_list_all.has_key(pkg.name)){
				pkg_list_all[pkg.name].is_top = true;
			}
		}

		foreach(Package pkg in pkg_list_manual.values){
			if (pkg_list_all.has_key(pkg.name)){
				pkg_list_all[pkg.name].is_manual = true;
			}
		}

		return pkg_list_all;
	}
	
	public Gee.HashMap<string,Package> list_available(){
		var pkg_list = new Gee.HashMap<string,Package>();

		string txt = execute_command_sync_get_output("aptitude search --disable-columns -F '%p|%d' '.'");
		
		foreach(string line in txt.split("\n")){
			if (line.strip() == "") { continue; }
			if (line.index_of("|") == -1) { continue; }
			
			string pkg_name = line.split("|")[0].strip();
			string pkg_desc = line.split("|")[1].strip();
			
			Package pkg = new Package(pkg_name);
			pkg.description = pkg_desc;
			pkg.is_available = true;
			pkg_list[pkg.name] = pkg;
		}

		return pkg_list;
	}

	public Gee.HashMap<string,Package> list_installed(bool get_ppa_info){
		
		var pkg_list = new Gee.HashMap<string,Package>();

		string cmd = "aptitude search --disable-columns -F '%p|%d' '?installed'";
		string txt = execute_command_sync_get_output(cmd);
		
		foreach(string line in txt.split("\n")){
			if (line.strip() == "") { continue; }
			if (line.index_of("|") == -1) { continue; }

			string pkg_name = line.split("|")[0].strip();
			string pkg_desc = line.split("|")[1].strip();
			
			Package pkg = new Package(pkg_name);
			pkg.description = pkg_desc;
			pkg.is_installed = true;
			pkg_list[pkg.name] = pkg;
		}

		//get ppa info ---------------------------
		
		if (get_ppa_info){
			
			cmd =
"""apt-cache policy $(dpkg -l | awk 'NR >= 6 { print $2 }') |
  awk '/^[^ ]/    { split($1, a, ":"); pkg = a[1] }
	nextline == 1 { nextline = 0; printf("%-40s %-50s %s\n", pkg, $2, $3) }
	/\*\*\*/      { nextline = 1 }'
""";

			string txtout, txterr;
			int exit_code = execute_command_script_sync(cmd, out txtout, out txterr);

			if (exit_code == 0){;
				string pkg_name;
				string pkg_server;
				string pkg_repo;
				
				try{
					rex_pkg_installed = new Regex("""([^ \t]*)[ \t]*([^ \t]*)[ \t]*([^ \t]*)[ \t]*""");
				}
				catch (Error e) {
					log_error (e.message);
				}
				
				foreach(string line in txtout.split("\n")){
					if (line.strip().length == 0) { continue; }

					if (rex_pkg_installed.match (line, 0, out match)){
						pkg_name = match.fetch(1).strip();
						pkg_server = match.fetch(2).strip();
						pkg_repo = match.fetch(3).strip();

						if (pkg_list.has_key(pkg_name)){
							pkg_list[pkg_name].server = pkg_server;
							pkg_list[pkg_name].repo = pkg_repo;
						}				
					}
				}
			}
		}
		
		return pkg_list;
	}

	public Gee.HashMap<string,Package> list_top(){
		var pkg_list = new Gee.HashMap<string,Package>();
		
		string txt = execute_command_sync_get_output("aptitude search --disable-columns -F '%p|%d' '?installed !?automatic !?reverse-depends(?installed)'");
		
		foreach(string line in txt.split("\n")){
			if (line.strip() == "") { continue; }
			if (line.index_of("|") == -1) { continue; }

			string pkg_name = line.split("|")[0].strip();
			string pkg_desc = line.split("|")[1].strip();
			
			Package pkg = new Package(pkg_name);
			pkg.description = pkg_desc;
			pkg.is_top = true;
			pkg_list[pkg.name] = pkg;
		}
		
		return pkg_list;
	}
	
	public Gee.HashMap<string,Package> list_default(){
		var pkg_list = new Gee.HashMap<string,Package>();
		
		string txt = "";
		execute_command_script_sync("gzip -dc /var/log/installer/initial-status.gz | sed -n 's/^Package: //p' | sort | uniq", out txt, null);
		
		foreach(string line in txt.split("\n")){
			if (line.strip() == "") { continue; }
			
			Package pkg = new Package(line.strip());
			pkg.is_default = true;
			pkg_list[pkg.name] = pkg;
		}

		return pkg_list;
	}
	
	public Gee.HashMap<string,Package> list_manual(){
		var pkg_list_default = list_default();
		var pkg_list_top = list_top();
		var pkg_list = new Gee.HashMap<string,Package>();
		
		foreach(Package pkg in pkg_list_top.values){
			if (!pkg_list_default.has_key(pkg.name)){
				pkg_list[pkg.name] = pkg;
				pkg.is_selected = true;
			}
		}

		return pkg_list;
	}

	public bool save_package_list_selected(Gee.HashMap<string,Package> package_list){
		string file_name = "packages.list";
		string list_file = backup_dir + (backup_dir.has_suffix("/") ? "" : "/") + file_name;

		var pkg_list = new ArrayList<Package>();
		foreach(Package pkg in package_list.values) {
			pkg_list.add(pkg);
		}
		CompareFunc<Package> func = (a, b) => {
			return strcmp(a.name,b.name);
		};
		pkg_list.sort(func);
		
		string text = "";
		foreach(Package pkg in pkg_list){
			if (pkg.is_selected){
				text += "%s\n".printf(pkg.name);
			}
			else{
				text += "#%s\n".printf(pkg.name);
			}
		}
		
		bool is_success = write_file(list_file,text);
		
		if (is_success){
			log_msg(_("File saved") + " '%s'".printf(file_name));
		}
		else{
			log_error(_("Failed to write")  + " '%s'".printf(file_name));
		}
		
		return is_success;
	}

	public bool save_package_list_installed(Gee.HashMap<string,Package> package_list){
		string file_name = "packages-installed.list";
		string list_file = backup_dir + (backup_dir.has_suffix("/") ? "" : "/") + file_name;
		
		var pkg_list = new ArrayList<Package>();
		foreach(Package pkg in package_list.values) {
			pkg_list.add(pkg);
		}
		CompareFunc<Package> func = (a, b) => {
			return strcmp(a.name,b.name);
		};
		pkg_list.sort(func);
		
		string text = "";
		foreach(Package pkg in pkg_list){
			if (pkg.is_installed){
				text += "%s\n".printf(pkg.name);
			}
		}
		
		bool is_success = write_file(list_file,text);
		
		if (is_success){
			log_msg(_("File saved") + " '%s'".printf(file_name));
		}
		else{
			log_error(_("Failed to write")  + " '%s'".printf(file_name));
		}
		
		return is_success;
	}
	
	public Gee.HashMap<string,Package> read_package_list(Gee.HashMap<string,Package> pkg_list_all){
		string file_name = "packages.list";
		string pkg_list_file = backup_dir + (backup_dir.has_suffix("/") ? "" : "/") + file_name;
		var pkg_list = new Gee.HashMap<string,Package>();
		
		//check file
		if (!check_backup_file(file_name)){
			return pkg_list;
		}

		//read package names
		foreach(string line in read_file(pkg_list_file).split("\n")){
			if (line.strip() == "") { continue; }
			
			bool pkg_selected;
			string pkg_name;
			if (line.strip().has_prefix("#")){
				pkg_selected = false;
				pkg_name = line.split("#")[1].strip();
			}
			else{
				pkg_selected = true;
				pkg_name = line.strip();
			}

			Package pkg = new Package(pkg_name);
			pkg_list[pkg_name] = pkg;
			pkg.is_selected = pkg_selected;
			
			//check if available/installed/top/default/manual
			if (pkg_list_all.has_key(pkg_name)){
				Package pkg_ref = pkg_list_all[pkg_name];
				//copy description and flags
				pkg.description = pkg_ref.description;
				pkg.is_available = pkg_ref.is_available;
				pkg.is_installed = pkg_ref.is_installed;
				pkg.is_top = pkg_ref.is_top;
				pkg.is_default = pkg_ref.is_default;
				pkg.is_manual = pkg_ref.is_manual;
			}
			else{
				//pkg is NOT available/installed/top/default/manual
			}
		}
		
		return pkg_list;
	}

	public bool download_packages (string pkg_list){
		string[] argv = new string[1];
		argv[0] = create_temp_bash_script("apt-get install -d -y %s".printf(pkg_list));
		
		Pid child_pid;
		int input_fd;
		int output_fd;
		int error_fd;

		try {
			//execute script file
			Process.spawn_async_with_pipes(
			    null, //working dir
			    argv, //argv
			    null, //environment
			    SpawnFlags.SEARCH_PATH,
			    null,   // child_setup
			    out child_pid,
			    out input_fd,
			    out output_fd,
			    out error_fd);
			
			is_running = true;
			
			proc_id = child_pid;

			//create stream readers
			UnixInputStream uis_out = new UnixInputStream(output_fd, false);
			UnixInputStream uis_err = new UnixInputStream(error_fd, false);
			dis_out = new DataInputStream(uis_out);
			dis_err = new DataInputStream(uis_err);
			dis_out.newline_type = DataStreamNewlineType.ANY;
			dis_err.newline_type = DataStreamNewlineType.ANY;
			
			progress_count = 0;
			//stdout_lines = new Gee.ArrayList<string>();
			stderr_lines = new Gee.ArrayList<string>();
			
        	try {
				//start thread for reading output stream
			    Thread.create<void> (apt_read_output_line, true);
		    } catch (Error e) {
		        log_error (e.message);
		    }
		    
		    try {
				//start thread for reading error stream
			    Thread.create<void> (apt_read_error_line, true);
		    } catch (Error e) {
		        log_error (e.message);
		    }
		    
        	return true;
		}
		catch (Error e) {
			log_error (e.message);
			return false;
		}
	}

	/* PPA */
	
	public Gee.HashMap<string,Ppa> list_ppa(){
		var ppa_list = new Gee.HashMap<string,Ppa>();
		var pkg_list_installed = App.list_installed(true);
		
		string sh =
"""
for listfile in `find /etc/apt/ -name \*.list`; do
    grep -o "^deb http://ppa.launchpad.net/[a-z0-9\-]\+/[a-z0-9.\-]\+" $listfile | while read entry ; do
        user=`echo $entry | cut -d/ -f4`
        ppa=`echo $entry | cut -d/ -f5`
        echo "$user/$ppa"
    done
done
""";
		string txt = "";
		execute_command_script_sync(sh, out txt, null);
		
		foreach(string line in txt.split("\n")){
			string ppa_name = line.strip();
			if (ppa_name.length > 0) {
				var ppa = new Ppa(ppa_name);
				ppa.is_selected = true;
				ppa.is_installed = true;
				ppa_list[ppa_name] = ppa;
				
				foreach (Package pkg in pkg_list_installed.values) {
					if (pkg.server.contains(ppa.name)){
						ppa.description += " %s".printf(pkg.name);
					}
				}
				ppa.description = ppa.description.strip();
			}
		}

		return ppa_list;
	}

	public bool save_ppa_list_selected(Gee.HashMap<string,Ppa> ppa_list_to_save){
		string file_name = "ppa.list";
		string ppa_list_file = backup_dir + (backup_dir.has_suffix("/") ? "" : "/") + file_name;

		var ppa_list = new ArrayList<Ppa>();
		foreach(Ppa ppa in ppa_list_to_save.values) {
			ppa_list.add(ppa);
		}
		CompareFunc<Ppa> func = (a, b) => {
			return strcmp(a.name,b.name);
		};
		ppa_list.sort(func);
		
		string text = "";
		foreach(Ppa ppa in ppa_list){
			if (ppa.is_selected){
				text += "%s #%s\n".printf(ppa.name, ppa.description);
			}
			else{
				text += "#%s #%s\n".printf(ppa.name, ppa.description);
			}
		}
		
		bool is_success = write_file(ppa_list_file,text);
		
		if (is_success){
			log_msg(_("File saved") + " '%s'".printf(file_name));
		}
		else{
			log_error(_("Failed to write")  + " '%s'".printf(file_name));
		}
		
		return is_success;
	}

	public Gee.HashMap<string,Ppa> read_ppa_list(){
		string file_name = "ppa.list";
		string ppa_list_file = backup_dir + (backup_dir.has_suffix("/") ? "" : "/") + file_name;
		var ppa_list = new Gee.HashMap<string,Ppa>();
		
		//check file
		if (!check_backup_file(file_name)){
			return ppa_list;
		}
		
		//get installed list
		var ppa_list_installed = list_ppa();
		
		//read file
		foreach(string line in read_file(ppa_list_file).split("\n")){
			if (line.strip() == "") { continue; }
			
			string ppa_name = "";
			string ppa_desc = "";
			bool ppa_selected;
			if (line.strip().has_prefix("#")){
				ppa_selected = false;
				ppa_name = line.split("#")[1].strip();
				if (line.split("#").length == 3){
					ppa_desc = line.split("#")[2].strip();
				}
			}
			else{
				ppa_selected = true;
				if (line.split("#").length == 2){
					ppa_name = line.split("#")[0].strip();
					ppa_desc = line.split("#")[1].strip();
				}
				else{
					ppa_name = line.strip();
				}
			}
			
			Ppa ppa = new Ppa(ppa_name);
			ppa.description = ppa_desc;
			ppa.is_selected = ppa_selected;
			ppa_list[ppa_name] = ppa;
			
			//check if installed
			if (ppa_list_installed.has_key(ppa_name)){
				ppa.is_installed = true;
			}		
		}
		
		return ppa_list;
	}

	public bool run_apt_update (){
		string[] argv = new string[1];
		argv[0] = create_temp_bash_script("apt-get -y update");
		
		Pid child_pid;
		int input_fd;
		int output_fd;
		int error_fd;

		try {
			//execute script file
			Process.spawn_async_with_pipes(
			    null, //working dir
			    argv, //argv
			    null, //environment
			    SpawnFlags.SEARCH_PATH,
			    null,   // child_setup
			    out child_pid,
			    out input_fd,
			    out output_fd,
			    out error_fd);
			
			is_running = true;
			
			proc_id = child_pid;

			//create stream readers
			UnixInputStream uis_out = new UnixInputStream(output_fd, false);
			UnixInputStream uis_err = new UnixInputStream(error_fd, false);
			dis_out = new DataInputStream(uis_out);
			dis_err = new DataInputStream(uis_err);
			dis_out.newline_type = DataStreamNewlineType.ANY;
			dis_err.newline_type = DataStreamNewlineType.ANY;
			
			progress_count = 0;
			//stdout_lines = new Gee.ArrayList<string>();
			stderr_lines = new Gee.ArrayList<string>();
			
        	try {
				//start thread for reading output stream
			    Thread.create<void> (apt_read_output_line, true);
		    } catch (Error e) {
		        log_error (e.message);
		    }
		    
		    try {
				//start thread for reading error stream
			    Thread.create<void> (apt_read_error_line, true);
		    } catch (Error e) {
		        log_error (e.message);
		    }
		    
        	return true;
		}
		catch (Error e) {
			log_error (e.message);
			return false;
		}
	}

	private void apt_read_error_line(){
		try{
			err_line = dis_err.read_line (null);
		    while (err_line != null) {
		        if (gui_mode){
					stderr_lines.add(err_line); //save
				}
				else{
					stderr.printf(err_line + "\n"); //print
				}
				
		        err_line = dis_err.read_line (null); //read next
			}
		}
		catch (Error e) {
			log_error (e.message);
		}	
	}

	private void apt_read_output_line(){
		try{
			out_line = dis_out.read_line (null);
		    while (out_line != null) {
				if (gui_mode){
					if (rex_aptget_download.match (out_line, 0, out match)){
						progress_count = int.parse(match.fetch(1).strip());
						status_line = match.fetch(2).strip();
					}
				}
				else{
					stdout.printf(out_line + "\n"); //print
				}

				out_line = dis_out.read_line (null);  //read next
			}

			is_running = false;
		}
		catch (Error e) {
			log_error (e.message);
		}	
	}

	/* APT Cache */
	
	public bool backup_apt_cache(){
		string archives_dir = backup_dir + (backup_dir.has_suffix("/") ? "" : "/") + "archives";

		try {
			//create 'archives' directory
			var f = File.new_for_path(archives_dir);
			if (!f.query_exists()){
				f.make_directory_with_parents();
			}
			
			string cmd = "rsync -ai --numeric-ids --list-only";
			cmd += " --exclude=lock --exclude=partial/";
			cmd += " %s %s".printf("/var/cache/apt/archives/", archives_dir + "/");

			if (gui_mode){
				//run rsync to get total count
				string txt = execute_command_sync_get_output(cmd);
				progress_total = txt.split("\n").length;

				//run rsync
				run_rsync(cmd.replace(" --list-only",""));
			}
			else{
				int status = Posix.system(cmd);
				return (status == 0);
			}

			return true;
		}
		catch (Error e){
			log_error (e.message);
			return false;
		}
	}
	
	public bool restore_apt_cache(){
		string archives_dir = backup_dir + (backup_dir.has_suffix("/") ? "" : "/") + "archives";

		//check 'archives' directory
		var f = File.new_for_path(archives_dir);
		if (!f.query_exists()){
			log_error(_("Cache backup not found in backup directory"));
			return false;
		}
		
		string cmd = "rsync -ai --numeric-ids --list-only";
		cmd += " --exclude=lock --exclude=partial/";
		cmd += " %s %s".printf(archives_dir + "/","/var/cache/apt/archives/");
		
		if (gui_mode){
			//run rsync to get total count
			string txt = execute_command_sync_get_output(cmd);
			progress_total = txt.split("\n").length;
			
			//run rsync
			return run_rsync(cmd.replace(" --list-only",""));
		}
		else{
			int status = Posix.system(cmd);
			return (status == 0);
		}
	}
	
	
	private bool run_rsync (string cmd){
		string[] argv = new string[1];
		argv[0] = create_temp_bash_script(cmd);
		
		Pid child_pid;
		int input_fd;
		int output_fd;
		int error_fd;

		try {
			//execute script file
			Process.spawn_async_with_pipes(
			    null, //working dir
			    argv, //argv
			    null, //environment
			    SpawnFlags.SEARCH_PATH,
			    null,   // child_setup
			    out child_pid,
			    out input_fd,
			    out output_fd,
			    out error_fd);
			
			is_running = true;
			
			proc_id = child_pid;

			//create stream readers
			UnixInputStream uis_out = new UnixInputStream(output_fd, false);
			UnixInputStream uis_err = new UnixInputStream(error_fd, false);
			dis_out = new DataInputStream(uis_out);
			dis_err = new DataInputStream(uis_err);
			dis_out.newline_type = DataStreamNewlineType.ANY;
			dis_err.newline_type = DataStreamNewlineType.ANY;
			
			progress_count = 0;
			//stdout_lines = new Gee.ArrayList<string>();
			//stderr_lines = new Gee.ArrayList<string>();
			
        	try {
				//start thread for reading output stream
			    Thread.create<void> (rysnc_read_output_line, true);
		    } catch (Error e) {
		        log_error (e.message);
		    }
		    
		    try {
				//start thread for reading error stream
			    Thread.create<void> (rysnc_read_error_line, true);
		    } catch (Error e) {
		        log_error (e.message);
		    }
		    
        	return true;
		}
		catch (Error e) {
			log_error (e.message);
			return false;
		}
	}

	private void rysnc_read_error_line(){
		try{
			err_line = dis_err.read_line (null);
		    while (err_line != null) {
		        stderr.printf(err_line + "\n"); //print
		        err_line = dis_err.read_line (null); //read next
			}
		}
		catch (Error e) {
			log_error (e.message);
		}	
	}
	
	private void rysnc_read_output_line(){
		try{
			out_line = dis_out.read_line (null);
		    while (out_line != null) {
				if (gui_mode){
					progress_count += 1; //count
					if (out_line.contains(" ")){
						status_line = out_line.split(" ")[1].strip(); //package name
					}
				}
				else{
					stdout.printf(out_line + "\n"); //print
				}
				
				out_line = dis_out.read_line (null);  //read next
			}

			is_running = false;
		}
		catch (Error e) {
			log_error (e.message);
		}	
	}
	
	/* Themes */
	
	public Gee.ArrayList<Theme> list_all_themes(){
		var theme_list = list_themes();
		foreach(Theme theme in list_icons()){
			theme_list.add(theme);
		}
		return theme_list;
	}
	
	public Gee.ArrayList<Theme> list_themes(){
		var theme_list = new Gee.ArrayList<Theme>();
		
		try{
			string share_path = "/usr/share/themes";
			var directory = File.new_for_path(share_path);
			var enumerator = directory.enumerate_children(FileAttribute.STANDARD_NAME, 0);
			FileInfo info;
			
			while ((info = enumerator.next_file()) != null) {
				if (info.get_file_type() == FileType.DIRECTORY){
					string theme_name = info.get_name();
					string theme_path = share_path + "/" + theme_name;
					
					switch (theme_name.down()){
						case "default":
						case "emacs":
						case "highcontrast":
							continue;
					}
					
					Theme theme = new Theme(theme_name, false);
					theme.system_path = theme_path;
					theme.is_selected = true;
					theme.is_installed = true;
					theme_list.add(theme);
				}
			}
		}
        catch(Error e){
	        log_error (e.message);
	    }
	    
	    return theme_list;
	}

	public Gee.ArrayList<Theme> list_icons(){
		var theme_list = new Gee.ArrayList<Theme>();
		
		try{
			string share_path = "/usr/share/icons";
			var directory = File.new_for_path(share_path);
			var enumerator = directory.enumerate_children(FileAttribute.STANDARD_NAME, 0);
			FileInfo info;
			
			while ((info = enumerator.next_file()) != null) {
				if (info.get_file_type() == FileType.DIRECTORY){
					string theme_name = info.get_name();
					string theme_path = share_path + "/" + theme_name;
					
					switch (theme_name.down()){
						case "default":
						case "mini":
						case "large":
						case "hicolor":
						case "locolor":
						case "scalable":
						case "highcontrast":
						case "gnome":
							continue;
					}
					
					Theme theme = new Theme(theme_name, true);
					theme.system_path = theme_path;
					theme.is_selected = true;
					theme.is_installed = true;
					theme_list.add(theme);
				}
			}
		}
        catch(Error e){
	        log_error (e.message);
	    }
	    
	    return theme_list;
	}
	
	public Gee.ArrayList<Theme> read_themes(){
		var themes_list = new Gee.ArrayList<Theme>();
		var themes_installed = list_all_themes();
		
		foreach(string folder_name in new string[] {"themes","icons"}){
			 
			string themes_dir = backup_dir + (backup_dir.has_suffix("/") ? "" : "/") + folder_name;

			//check directory
			var f = File.new_for_path(themes_dir);
			if (!f.query_exists()){
				log_error(_("Themes not found in backup directory"));
				return themes_list;
			}//TODO:use func

			try{
				var directory = File.new_for_path(themes_dir);
				var enumerator = directory.enumerate_children(FileAttribute.STANDARD_NAME, 0);
				FileInfo info;
				
				while ((info = enumerator.next_file()) != null) {
					if (info.get_file_type() == FileType.REGULAR){
						string zip_file_path = "%s/%s".printf(themes_dir, info.get_name());
						string theme_name = info.get_name().replace(".tar.gz","");

						Theme theme = new Theme(theme_name, (folder_name == "themes") ? false : true);
						theme.zip_file_path = zip_file_path;
						theme.is_selected = true;
						foreach (Theme th in themes_installed){
							if (th.name == theme_name){
								theme.is_installed = true;
								break;
							}
						}
						themes_list.add(theme);
					}
				}
			}
			catch(Error e){
				log_error (e.message);
			}
	    }
		
		return themes_list;
	}
	
	public bool zip_theme(Theme theme){
		string theme_dir = backup_dir + (backup_dir.has_suffix("/") ? "" : "/") + (theme.is_icon_theme ? "icons" : "themes");
		string theme_dir_system = "/usr/share/%s".printf(theme.is_icon_theme ? "icons" : "themes");
		string file_name = theme.name + ".tar.gz";
		string zip_file = theme_dir + "/" + file_name;
		
		try {
			//create theme directory
			var f = File.new_for_path(theme_dir);
			if (!f.query_exists()){
				f.make_directory_with_parents();
			}
			
			string cmd = "tar -czvf '%s' -C '%s' '%s'".printf(zip_file, theme_dir_system, theme.name);

			if (gui_mode){
				//get total count
				progress_total = (int) get_file_count(theme.system_path);
				status_line = theme.system_path;
				
				//zip it
				run_gzip(cmd);
			}
			else{
				int status = Posix.system(cmd);
				return (status == 0);
			}

			return true;
		}
		catch (Error e){
			log_error (e.message);
			return false;
		}
	}
	
	public bool unzip_theme(Theme theme){
		string theme_dir_system = "/usr/share/%s".printf(theme.is_icon_theme ? "icons" : "themes");
		
		//check file
		if (!file_exists(theme.zip_file_path)){
			log_error(_("File not found") + ": '%s'".printf(theme.zip_file_path));
			return false;
		}
		
		string cmd = "tar -xzvf '%s' --directory='%s'".printf(theme.zip_file_path, theme_dir_system);

		if (gui_mode){
			//get total count
			string txt = execute_command_sync_get_output(cmd.replace("-xzvf","-tvf"));
			progress_total = txt.split("\n").length;
			status_line = theme.system_path;
			
			//unzip it
			return run_gzip(cmd);
		}
		else{
			int status = Posix.system(cmd);
			return (status == 0);
		}
	}
	
	private bool run_gzip (string cmd){
		string[] argv = new string[1];
		argv[0] = create_temp_bash_script(cmd);
		
		Pid child_pid;
		int input_fd;
		int output_fd;
		int error_fd;

		try {
			//execute script file
			Process.spawn_async_with_pipes(
			    null, //working dir
			    argv, //argv
			    null, //environment
			    SpawnFlags.SEARCH_PATH,
			    null,   // child_setup
			    out child_pid,
			    out input_fd,
			    out output_fd,
			    out error_fd);
			
			is_running = true;
			
			proc_id = child_pid;

			//create stream readers
			UnixInputStream uis_out = new UnixInputStream(output_fd, false);
			UnixInputStream uis_err = new UnixInputStream(error_fd, false);
			dis_out = new DataInputStream(uis_out);
			dis_err = new DataInputStream(uis_err);
			dis_out.newline_type = DataStreamNewlineType.ANY;
			dis_err.newline_type = DataStreamNewlineType.ANY;
			
			progress_count = 0;
			//stdout_lines = new Gee.ArrayList<string>();
			//stderr_lines = new Gee.ArrayList<string>();
			
        	try {
				//start thread for reading output stream
			    Thread.create<void> (gzip_read_output_line, true);
		    } catch (Error e) {
		        log_error (e.message);
		    }
		    
		    try {
				//start thread for reading error stream
			    Thread.create<void> (gzip_read_error_line, true);
		    } catch (Error e) {
		        log_error (e.message);
		    }
		    
        	return true;
		}
		catch (Error e) {
			log_error (e.message);
			return false;
		}
	}

	private void gzip_read_error_line(){
		try{
			err_line = dis_err.read_line (null);
		    while (err_line != null) {
		        stderr.printf(err_line + "\n"); //print
		        err_line = dis_err.read_line (null); //read next
			}
		}
		catch (Error e) {
			log_error (e.message);
		}	
	}
	
	private void gzip_read_output_line(){
		try{
			out_line = dis_out.read_line (null);
		    while (out_line != null) {
				if (gui_mode){
					progress_count += 1; //count
				}
				else{
					stdout.printf(out_line + "\n"); //print
				}
				out_line = dis_out.read_line (null);  //read next
			}

			is_running = false;
		}
		catch (Error e) {
			log_error (e.message);
		}	
	}
	
	/* Misc */
	
	public bool take_ownership(){
		string home = Environment.get_home_dir();
		string user = get_user_login();

		try {
			string cmd = "chown %s -R %s".printf(user,home);
			int exit_code;
			Process.spawn_command_line_sync(cmd, null, null, out exit_code);
			
			if (exit_code == 0){
				log_msg(_("Ownership changed to '%s' for files in directory '%s'").printf(user,home));
				return true;
			}
			else{
				log_msg(_("Failed to change file ownership"));
				return false;
			}
		}
		catch (Error e){
			log_error (e.message);
			return false;
		}
	}
	
	public void exit_app(){
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
	public string server = "";
	public string repo = "";
	public bool is_selected = false;
	public bool is_available = false;
	public bool is_installed = false;
	public bool is_top = false;
	public bool is_default = false;
	public bool is_manual = false;
	
	public Package(string _name){
		name = _name;
	}
}

public class Ppa : GLib.Object{
	public string name = "";
	public string description = "";
	public bool is_selected = false;
	public bool is_installed = false;
	
	public Ppa(string _name){
		name = _name;
	}
}

public class Theme : GLib.Object{
	public string name = "";
	public string description = "";
	public string system_path = "";
	public string zip_file_path = "";
	public bool is_selected = false;
	public bool is_installed = false;
	public bool is_icon_theme = false;
	
	public Theme(string _name, bool _is_icon_theme){
		name = _name;
		is_icon_theme = _is_icon_theme;
	}
}
