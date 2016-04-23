/*
 * Theme.vala
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

public class Theme : GLib.Object{
	public string name = "";
	public string description = "";
	
	public string base_path = "";
	public string theme_dir_path = "";
	public string archive_path = "";
	
	public bool is_selected = false;
	public bool is_installed = false;
	
	public string dir_type = ""; //'icons' or 'themes'
	
	public Gee.ArrayList<ThemeType> type_list = null;
	public string type_desc = "";

	// static members --------------------

	public static Gee.HashMap<string,string> type_index = null;
	
	// zip/unzip progress --------
	
	public string err_line;
	public string out_line;
	public string status_line;
	public string status_summary;
	public Gee.ArrayList<string> stdout_lines;
	public Gee.ArrayList<string> stderr_lines;
	public Pid proc_id;
	public DataInputStream dis_out;
	public DataInputStream dis_err;
	public int64 progress_count;
	public int64 progress_total;
	public bool is_running;
	
	public Theme.from_system(string _name, string _base_path){
		name = _name;
		base_path = _base_path;
		theme_dir_path = "%s/%s".printf(_base_path, _name);
		dir_type = _base_path.has_suffix("icons") ? "icons" : "themes";
		is_installed = true;
		
		get_theme_type_from_installed();
		get_file_count_installed();
	}
	
	public Theme.from_archive(string _name, string _archive_path, string _type){
		name = _name;
		dir_type = _type;
		archive_path = _archive_path;

		check_installed("");
		
		if (App.gui_mode){
			get_theme_type_from_archive();
		}
		//base_path = _base_path;
		//theme_dir_path = "%s/%s".printf(_base_path, name);
	}
	
	public Theme(string _name, string _type, string _base_path){
		name = _name;
		dir_type = _type;
		base_path = _base_path;
		theme_dir_path = "%s/%s".printf(_base_path, name);
	}

	public void load_type_from_index(){
		clear_type_list();
		
		string type_name = "%s/%s".printf(dir_type,name);
		if (!type_index.has_key(type_name)){
			return;
		}
			
		string txt = type_index[type_name];
		foreach(string part in txt.split(",")){
			add_type(part.strip());
		}

		type_desc = type_desc.strip();
		if (type_desc.length > 0){
			type_desc = type_desc[0:type_desc.length - 1];
		}
	}

	public void clear_type_list(){
		type_list = new Gee.ArrayList<ThemeType>();
		type_desc = "";
	}

	// static ----------------------

	public static void init(){
		if (type_index == null){
			type_index = new Gee.HashMap<string,string>();
		}
	}
	
	public static void load_index(string backup_dir){
		foreach(string subdir in new string[] { "icons","themes" }){
			string base_dir = "%s%s".printf(backup_dir, subdir);
			string index_file = "%s/%s".printf(base_dir,"index.list");
			if (file_exists(index_file)){
				Theme.load_index_file(index_file);
			}
		}
		//log_msg("load:index.list:%d".printf(type_index.size));
	}

	private static void load_index_file(string file_path){
		if (file_exists(file_path)){
			string txt = file_read(file_path);
			foreach(string line in txt.split("\n")){
				string[] arr = line.split(":");
				if (arr.length == 2){
					string key = arr[0];
					if (!type_index.has_key(key) || (arr[1].strip().length > 0)){
						type_index[key] = arr[1];
					}
				}
			}
		}
	}

	public static void save_index(Gee.ArrayList<Theme> theme_list, string backup_dir){
		foreach(Theme theme in theme_list){
			string key = "%s/%s".printf(theme.dir_type, theme.name);
			if (!type_index.has_key(key) || (theme.type_desc.strip().length > 0)){
				type_index[key] = theme.type_desc;
			}
		}
		
		string txt = "";
		foreach(string key in type_index.keys){
			if (key.has_prefix("icons")){
				txt += "%s:%s\n".printf(key, type_index[key]);
			}
		}

		string index_file = "%s%s/index.list".printf(backup_dir, "icons");
		file_write(index_file, txt);
		//log_msg("write:icons/index.list:%d".printf(type_index.size));
		
		txt = "";
		foreach(string key in type_index.keys){
			if (key.has_prefix("themes")){
				txt += "%s:%s\n".printf(key, type_index[key]);
			}
		}

		index_file = "%s%s/index.list".printf(backup_dir, "themes");
		file_write(index_file, txt);
		//log_msg("write:themes/index.list:%d".printf(type_index.size));
	}
	
	//list installed themes ---------
	
	public static Gee.ArrayList<Theme> list_themes_installed(string username = "", bool sort_by_group = false){
		var list = new Gee.ArrayList<Theme>();

		if (username.length == 0){
			//common
			foreach(string subdir in new string[] { "icons","themes" }){
				string base_dir = "%s/%s".printf("/usr/share", subdir);

				foreach(var theme in list_themes_from_path(base_dir)){
					list.add(theme);
				}
			}
		}
		else{
			//user
			foreach(string subdir in new string[] { ".icons",".themes", ".local/share/icons", ".local/share/themes" }){
				string base_dir = "%s/%s/%s".printf("/home", username, subdir);
				foreach(var theme in list_themes_from_path(base_dir)){
					list.add(theme);
				}
			}
		}
		
		//sort the list
		if (sort_by_group){
			CompareDataFunc<Theme> entry_compare = (a, b) => {
				return strcmp(a.dir_type + "/" + a.name, b.dir_type + "/" + b.name);
			};
			list.sort((owned) entry_compare);
		}
		else{
			CompareDataFunc<Theme> entry_compare = (a, b) => {
				return strcmp(a.name, b.name);
			};
			list.sort((owned) entry_compare);
		}
		
		return list;
	}
	
	public static Gee.ArrayList<Theme> list_themes_from_path(string _base_path){
		var list = new Gee.ArrayList<Theme>();

		try {
			var directory = File.new_for_path(_base_path);
			if (!directory.query_exists()){
				return list;
			}
			
			var enumerator = directory.enumerate_children("%s".printf(FileAttribute.STANDARD_NAME), 0);
			FileInfo info;

			while ((info = enumerator.next_file()) != null) {
				if (info.get_file_type() == FileType.DIRECTORY) {
					string theme_name = info.get_name();
					switch (theme_name.down()) {
					case "default":
					case "default-hdpi":
					case "default-xdpi":
					case "emacs":
					case "hicolor":
					case "locolor":
					case "highcontrast":
						continue;
					}
					
					var theme = new Theme.from_system(theme_name, _base_path);
					theme.is_selected = true;
					list.add(theme);
					//Add theme even if type_list size is 0. There may be unknown types (for other desktops like KDE, etc)
				}
			}

			//sort the list
			CompareDataFunc<Theme> entry_compare = (a, b) => {
				return strcmp(a.name, b.name);
			};
			list.sort((owned) entry_compare);
		}
		catch (Error e) {
			log_error (e.message);
			log_error ("In: list_themes_from_path()");
		}

		return list;
	}
	
	private void get_theme_type_from_installed(){
		type_list = new Gee.ArrayList<ThemeType>();
		
		try {
			var directory = File.new_for_path(theme_dir_path);
			if (!directory.query_exists()){
				return;
			}
			
			var enumerator = directory.enumerate_children("%s".printf(FileAttribute.STANDARD_NAME), 0);
			FileInfo info;
			
			type_desc = "";
			
			while ((info = enumerator.next_file()) != null) {
				if ((info.get_file_type() == FileType.DIRECTORY) || (info.get_file_type() == FileType.SYMBOLIC_LINK)){
					string dir_name = info.get_name();
					
					switch (dir_name.down()) {
					case "gtk-2.0":
						type_list.add(ThemeType.GTK20);
						type_desc += "%s, ".printf(dir_name.down());
						break;
					case "gtk-3.0":
						type_list.add(ThemeType.GTK30);
						type_desc += "%s, ".printf(dir_name.down());
						break;
					case "metacity-1":
						type_list.add(ThemeType.METACITY1);
						type_desc += "%s, ".printf(dir_name.down());
						break;
					case "unity":
						type_list.add(ThemeType.UNITY);
						type_desc += "%s, ".printf(dir_name.down());
						break;
					case "cinnamon":
						type_list.add(ThemeType.CINNAMON);
						type_desc += "%s,".printf(dir_name.down());
						break;
					case "gnome-shell":
						type_list.add(ThemeType.GNOMESHELL);
						type_desc += "%s, ".printf(dir_name.down());
						break;
					case "xfce-notify-4.0":
						type_list.add(ThemeType.XFCENOTIFY40);
						type_desc += "%s, ".printf(dir_name.down());
						break;
					case "xfwm4":
						type_list.add(ThemeType.XFWM4);
						type_desc += "%s, ".printf(dir_name.down());
						break;
					case "cursors":
						type_list.add(ThemeType.CURSOR);
						type_desc += "%s, ".printf(dir_name.down());
						break;
					case "actions":
					case "apps":
					case "categories":
					case "devices":
					case "emblems":
					case "mimetypes":
					case "places":
					case "status":
					case "stock":
					case "16x16":
					case "22x22":
					case "24x24":
					case "32x32":
					case "48x48":
					case "64x64":
					case "128x128":
					case "256x256":
					case "scalable":
						if (!type_list.contains(ThemeType.ICON)){
							type_list.add(ThemeType.ICON);
							type_desc += "%s, ".printf("icons");
						}
						break;
					}
				}
			}
			
			type_desc = type_desc.strip();
			if (type_desc.length > 0){
				type_desc = type_desc[0:type_desc.length - 1];
			}
		}
		catch (Error e) {
			log_error (e.message);
			log_error ("In: get_theme_type_from_installed()");
		}
	}
	

	private void add_type(string dir_name){
		switch (dir_name.down()) {
		case "gtk-2.0":
			type_list.add(ThemeType.GTK20);
			type_desc += "%s, ".printf(dir_name.down());
			break;
		case "gtk-3.0":
			type_list.add(ThemeType.GTK30);
			type_desc += "%s, ".printf(dir_name.down());
			break;
		case "metacity-1":
			type_list.add(ThemeType.METACITY1);
			type_desc += "%s, ".printf(dir_name.down());
			break;
		case "unity":
			type_list.add(ThemeType.UNITY);
			type_desc += "%s, ".printf(dir_name.down());
			break;
		case "cinnamon":
			type_list.add(ThemeType.CINNAMON);
			type_desc += "%s,".printf(dir_name.down());
			break;
		case "gnome-shell":
			type_list.add(ThemeType.GNOMESHELL);
			type_desc += "%s, ".printf(dir_name.down());
			break;
		case "xfce-notify-4.0":
			type_list.add(ThemeType.XFCENOTIFY40);
			type_desc += "%s, ".printf(dir_name.down());
			break;
		case "xfwm4":
			type_list.add(ThemeType.XFWM4);
			type_desc += "%s, ".printf(dir_name.down());
			break;
		case "cursors":
			type_list.add(ThemeType.CURSOR);
			type_desc += "%s, ".printf(dir_name.down());
			break;
		case "actions":
		case "apps":
		case "categories":
		case "devices":
		case "emblems":
		case "mimetypes":
		case "places":
		case "status":
		case "stock":
		case "16x16":
		case "22x22":
		case "24x24":
		case "32x32":
		case "48x48":
		case "64x64":
		case "128x128":
		case "256x256":
		case "scalable":
		case "icons":
			if (!type_list.contains(ThemeType.ICON)){
				type_list.add(ThemeType.ICON);
				type_desc += "%s, ".printf("icons");
			}
			break;
		}
	}
	
	private int64 get_file_count_installed(){
		progress_total = (int64) get_file_count(theme_dir_path);
		progress_count = 0;
		return progress_total;
	}
	
	//list archived themes ----------
	
	public static Gee.ArrayList<Theme> list_themes_archived(string backup_dir) {
		var list = new Gee.ArrayList<Theme>();
		
		foreach(string subdir in new string[] { "icons","themes" }){
			string base_dir = "%s%s".printf(backup_dir.has_suffix("/") ? backup_dir : backup_dir + "/", subdir);

			foreach(var theme in list_themes_archived_from_path(base_dir, subdir)){
				list.add(theme);
			}
		}
		
		//sort the list
		CompareDataFunc<Theme> entry_compare = (a, b) => {
			return strcmp(a.name, b.name);
		};
		list.sort((owned) entry_compare);
		
		return list;
	}
	
	public static Gee.ArrayList<Theme> list_themes_archived_from_path(string archive_dir, string _type) {
		var list = new Gee.ArrayList<Theme>();
		
		//check directory
		var f = File.new_for_path(archive_dir);
		if (!f.query_exists()) {
			//log_error(_("Themes not found in backup directory"));
			return list;
		}

		try {
			var directory = File.new_for_path(archive_dir);
			var enumerator = directory.enumerate_children("%s".printf(FileAttribute.STANDARD_NAME), 0);
			FileInfo info;

			while ((info = enumerator.next_file()) != null) {
				if (info.get_file_type() != FileType.REGULAR) {
					continue;
				}
				if (!info.get_name().has_suffix(".tar.gz")){
					continue;
				}
				
				string file_path = "%s/%s".printf(archive_dir, info.get_name());
				string theme_name = info.get_name().replace(".tar.gz", "");
				string theme_type = archive_dir.has_suffix("/icons") ? "icons" : "themes";

				App.status_line = info.get_name();
				App.progress_count++;

				var theme = new Theme.from_archive(theme_name, file_path, theme_type);
				list.add(theme);
			}
		}
		catch (Error e) {
			log_error (e.message);
			log_error ("In: list_themes_archived_from_path()");
		}

		return list;
	}

	private void get_theme_type_from_archive(){
		clear_type_list();

		// check and get type from index ----------------------
		
		string type_name = "%s/%s".printf(dir_type,name);
		if (type_index.has_key(type_name)){
			load_type_from_index();
			return;
		}
		
		// get type by parsing archive -----------------------
		
		var file = File.new_for_path(archive_path);
		if (!file.query_exists()){
			return;
		}

		var archive = new Archive.from_file(archive_path);
		archive.open(true);
		progress_total = archive.base_archive.file_count_total;
		
		if ((archive.base_archive.children == null) || (archive.base_archive.children.size == 0)){
			return;
		}
		
		FileItem themedir = null;
		foreach (FileItem item in archive.base_archive.children.values){
			themedir = item;
			break;
		}
		
		foreach (FileItem item in themedir.children.values){
			if (item.file_type == FileType.DIRECTORY){
				string dir_name = item.file_name;
				add_type(dir_name);
			}
		}
		
		type_desc = type_desc.strip();
		if (type_desc.length > 0){
			type_desc = type_desc[0:type_desc.length - 1];
		}
	}

	public int64 get_file_count_archived(){
		//get file count from archive
		string cmd = "tar tvf '%s'".printf(archive_path);
		string txt = execute_command_sync_get_output(cmd);
		progress_total += txt.split("\n").length;

		progress_count = 0;
		
		return progress_total;
	}
	
	private string set_theme_dir_path(string username){
		if (username.length == 0){
			theme_dir_path = "/usr/share/%s/%s".printf(dir_type, name);
		}
		else if (username == "root"){
			theme_dir_path = "/%s/.%s/%s".printf(username, dir_type, name);
		}
		else{
			theme_dir_path = "/home/%s/.%s/%s".printf(username, dir_type, name);
		}
		return theme_dir_path;
	}
	
	public bool check_installed(string username){
		set_theme_dir_path(username);

		//check directory
		var f = File.new_for_path(theme_dir_path);
		if (f.query_exists()) {
			is_installed = true;
			
			base_path = File.new_for_path(theme_dir_path).get_parent().get_path();
		}
		else{
			is_installed = false;
		}
		
		return is_installed;
	}
	
	//zip and unzip --------------------------

	Pid child_pid;
	int input_fd;
	int output_fd;
	int error_fd;
		
	public bool zip(string backup_dir, bool gui_mode) {
		string backup_path = backup_dir + "%s".printf(dir_type);
		string file_name = name + ".tar.gz";
		string zip_file = backup_path + "/" + file_name;

		try {
			//create directory
			var f = File.new_for_path(backup_path);
			if (!f.query_exists()) {
				f.make_directory_with_parents();
			}

			string cmd = "tar czvf '%s' -C '%s' '%s'".printf(zip_file, base_path, name);
			status_line = theme_dir_path;

			if (gui_mode) {
				run_gzip(cmd);
			}
			else {
				stdout.printf("%-80s".printf(_("Archiving") + " '%s'".printf(theme_dir_path)));
				stdout.flush();

				int status = Posix.system(cmd + " 1> /dev/null");
				if (status == 0) {
					stdout.printf("[ OK ]\n");
				}
				else {
					stdout.printf("[ status=%d ]\n".printf(status));
				}
				return (status == 0);
			}

			return true;
		}
		catch (Error e) {
			log_error (e.message);
			return false;
		}
	}
	
	public bool unzip(string username, bool gui_mode) {
		set_theme_dir_path(username);
		
		//check file
		if (!file_exists(archive_path)) {
			log_error(_("File not found") + ": '%s'".printf(archive_path));
			return false;
		}

		//create dest dir
		dir_create(theme_dir_path);

		string cmd = "tar xzvf '%s' --directory='%s'".printf(archive_path, file_parent(theme_dir_path));
		status_line = archive_path;
		
		if (gui_mode) {
			log_msg("Extract: %s, Dest: %s".printf(archive_path, file_parent(theme_dir_path)));
			return run_gzip(cmd);
		}
		else {
			stdout.printf("%-80s".printf(_("Extracting") + " '%s'".printf(theme_dir_path)));
			stdout.flush();

			int status = Posix.system(cmd + " 1> /dev/null");
			if (status == 0) {
				stdout.printf("[ OK ]\n");
			}
			else {
				stdout.printf("[ status=%d ]\n".printf(status));
			}
			
			return (status == 0);
		}
	}
	
	private bool run_gzip (string cmd) {
		string[] argv = new string[1];
		argv[0] = save_bash_script_temp(cmd);

		try {
			//execute script file
			Process.spawn_async_with_pipes(
			    App.temp_dir, //working dir
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

	private void gzip_read_error_line() {
		try {
			err_line = dis_err.read_line (null);
			while (err_line != null) {
				stderr.printf(err_line + "\n"); //print
				err_line = dis_err.read_line (null); //read next
			}

			dis_err.close();
			dis_err = null;
			GLib.FileUtils.close(error_fd);
		}
		catch (Error e) {
			log_error (e.message);
		}
	}

	private void gzip_read_output_line() {
		try {
			out_line = dis_out.read_line (null);
			while (out_line != null) {
				progress_count += 1; //count
				status_line = out_line;
				out_line = dis_out.read_line (null);  //read next
			}

			dis_out.close();
			dis_out = null;
			GLib.FileUtils.close(output_fd);

			GLib.FileUtils.close(input_fd);
			
			Process.close_pid(child_pid); //required on Windows, doesn't do anything on Unix
					
			is_running = false;
		}
		catch (Error e) {
			log_error (e.message);
		}
	}
	
	//permissions -------------
	
	public bool update_permissions() {
		try {
			int exit_code;
			string cmd;

			log_debug("set permission '755' for dirs in path '%s'".printf(theme_dir_path));
			cmd = "find '%s' -type d -exec chmod 755 '{}' ';'".printf(theme_dir_path);
			Process.spawn_command_line_sync(cmd, null, null, out exit_code);
			if (exit_code != 0) {
				return false;
			}

			log_debug("set permission '644' for files in path '%s'".printf(theme_dir_path));
			cmd = "find '%s' -type f -exec chmod 644 '{}' ';'".printf(theme_dir_path);
			Process.spawn_command_line_sync(cmd, null, null, out exit_code);
			if (exit_code != 0) {
				return false;
			}

			return true;
		}
		catch (Error e) {
			log_error (e.message);
			return false;
		}
	}
	
	public void update_ownership(string username) {
		if (username.length > 0){
			set_directory_ownership(theme_dir_path, username);
			set_directory_ownership(file_parent(theme_dir_path), username);
		}
	}
	
	//enums and helpers ------------------
	
	public enum ThemeType {
		ALL,
		NONE,
		CINNAMON,
		CURSOR,
		GNOMESHELL,
		GTK20,
		GTK30,
		ICON,
		METACITY1,
		UNITY,
		XFCENOTIFY40,
		XFWM4
	}
	
	public static Gee.HashMap<Theme.ThemeType, string> theme_type_map;
	
	static construct {
		var map = new Gee.HashMap<Theme.ThemeType, string>(); 
		map[ThemeType.ALL] = "all";
		map[ThemeType.NONE] = "none";
		map[ThemeType.CINNAMON] = "cinnamon";
		map[ThemeType.CURSOR] = "cursors";
		map[ThemeType.GNOMESHELL] = "gnome-shell";
		map[ThemeType.GTK20] = "gtk-2.0";
		map[ThemeType.GTK30] = "gtk-3.0";
		map[ThemeType.ICON] = "icons";
		map[ThemeType.METACITY1] = "metacity-1";
		map[ThemeType.UNITY] = "unity";
		map[ThemeType.XFCENOTIFY40] = "xfce-notify-4.0";
		map[ThemeType.XFWM4] = "xfwm4";
		theme_type_map = map;
	}

	public static void fix_nested_folders(){
		fix_nested_folders_in_path("/usr/share/themes");
		fix_nested_folders_in_path("/usr/share/icons");
		fix_nested_folders_in_path("/root/.themes");
		fix_nested_folders_in_path("/root/.icons");
			
		var list = list_dir_names("/home");
		
		foreach(string user_name in list){
			if (user_name == "PinguyBuilder"){
				continue;
			}

			fix_nested_folders_in_path("/home/%s/.themes".printf(user_name));
			fix_nested_folders_in_path("/home/%s/.icons".printf(user_name));
		}
	}
	
	public static void fix_nested_folders_in_path(string share_path){
		try {
			
			log_msg("\n" + _("Checking for nested folders in path") + ": %s".printf(share_path));
			
			var dir = File.new_for_path(share_path);
			if (!dir.query_exists()){
				return;
			}
			
			var enumerator = dir.enumerate_children("%s".printf(FileAttribute.STANDARD_NAME), 0);
			FileInfo info;

			while ((info = enumerator.next_file()) != null) {
				if (info.get_file_type() == FileType.DIRECTORY) {
					string theme_name = info.get_name();

					var theme_dir = "%s/%s".printf(share_path, theme_name);
					var dir2 = File.new_for_path(theme_dir);					
					var enum2 = dir2.enumerate_children("%s".printf(FileAttribute.STANDARD_NAME), 0);
					FileInfo info2;

					bool nested_dir_found = false;
					int subdir_count = 0;
					while ((info2 = enum2.next_file()) != null) {
						subdir_count++;
						if (info2.get_file_type() == FileType.DIRECTORY) {
							if (info2.get_name() == theme_name){
								nested_dir_found = true;
							}
						}
					}

					if (nested_dir_found && (subdir_count == 1)){
						// move the nested folder one level up
						var src = "%s/%s/%s".printf(share_path, theme_name, theme_name);
						var dst = "%s/%s".printf(share_path, theme_name);
						var dst_tmp = "%s/%s_temp".printf(share_path, theme_name);

						if (dir_exists(src)){
							file_move(src, dst_tmp);
						}

						file_delete(dst);
						file_move(dst_tmp, dst);

						log_msg("Fixed: %s".printf(src));
					}
				}
			}
		}
		catch (Error e) {
			log_error (e.message);
			log_error ("Theme: fix_nested_folders_in_path()");
		}
	}
	
}
