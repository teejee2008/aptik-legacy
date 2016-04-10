/*
 * Main.vala
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

extern void exit(int exit_code);

public class Main : GLib.Object {
	public static string DEF_PKG_LIST = "/var/log/installer/initial-status.gz";
	public static string DEF_PKG_LIST_UNPACKED = "/var/log/installer/initial-status";

	public static string APT_LISTS_PATH = "/var/lib/apt/lists";
	public static string PKG_CACHE_APT = "/var/cache/apt/pkgcache.bin";
	public static string PKG_CACHE_TEMP = "/tmp/aptikcache";
	public static string DEB_LIST_TEMP = "/tmp/aptik-debs";

	public static string PKG_LIST_BAK = "packages.list";
	public static string PKG_LIST_INSTALLED_BAK = "packages-installed.list";

	public string NATIVE_ARCH = "amd64";
	
	public string temp_dir = "";
	public string _backup_dir = "";
	public string share_dir = "/usr/share";
	public string app_conf_path = "";

	public bool default_list_missing = false;

	public bool gui_mode = false;
	public string user_login = "";
	public string user_home = "";
	public int user_uid = -1;
	public bool all_users = false;

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
	public bool cancelled;
	
	public Gee.HashMap<string, Package> pkg_list_master;
	public Gee.HashMap<string, Ppa> ppa_list_master;
	public Gee.ArrayList<string> sections;

	public Gee.HashMap<string,SystemUser> user_list_bak;
	public Gee.HashMap<string,SystemGroup> group_list_bak;

	public Gee.ArrayList<SystemUser> user_list_home;
	
	public Gee.ArrayList<BackupTask> task_list;
	public string selected_tasks = "";
	public bool backup_mode = false;
	public bool dup_mode_full = false;
	public FileItem home_tree;
	
	public string pkg_list_install = "";
	public string pkg_list_deb = "";
	public string pkg_list_missing = "";
	public string gdebi_list = "";

	public string arg_password = "";
	public uint64 arg_size_limit = 0;
	
	public DateTime pkginfo_modified_date;

	public Gdk.WindowTypeHint temp_type = Gdk.WindowTypeHint.MENU;
	
	Pid child_pid;
	int input_fd;
	int output_fd;
	int error_fd;
		
	public Main(string[] args, bool _gui_mode) {

		gui_mode = _gui_mode;

		LOG_TIMESTAMP = false;
		
		pkginfo_modified_date = new DateTime.from_unix_utc(0); //1970

		//initialize
		pkg_list_master = new Gee.HashMap<string, Package>();
		ppa_list_master = new Gee.HashMap<string, Ppa>();
		sections = new Gee.ArrayList<string>();
		home_tree = null;

		//config file
		string home = Environment.get_home_dir();
		app_conf_path = home + "/.config/aptik.json";

		//load settings if GUI mode
		if (gui_mode) {
			load_app_config();
		}

		//check dependencies
		string message;
		if (!check_dependencies(out message)) {
			if (gui_mode) {
				string title = _("Missing Dependencies");
				gtk_messagebox(title, message, null, true);
			}
			exit(0);
		}

		//initialize backup_dir as current directory for CLI mode
		if (!gui_mode) {
			backup_dir = Environment.get_current_dir() + "/";
		}

		try {
			//create temp dir
			temp_dir = get_temp_file_path();

			var f = File.new_for_path(temp_dir);
			if (f.query_exists()) {
				Posix.system("rm -rf %s".printf(temp_dir));
			}
			f.make_directory_with_parents();

			//initialize regex variables
			//rex_aptget_download = new Regex("""([0-9]*)%[ \t]*\[([^\]]*)\]""");
		}
		catch (Error e) {
			log_error (e.message);
		}

		//get user info
		if (gui_mode){
			select_user(get_user_login());
		}
		
		NATIVE_ARCH = execute_command_sync_get_output("dpkg --print-architecture").strip();

		Theme.init();

		init_user_list_home();
	}

	public void select_user(string username){
		if ((username ==  null)||(username == "(all)")||(username == "")){
			all_users = true;
			user_login = "";
			user_home = "/root";
			user_uid = 0;
			return;
		}
		else{
			all_users = false;
		}
		
		if (username == "root"){
			user_login = "root";
			user_home = "/root";
			user_uid = 0;
		}
		else{
			user_login = username;
			user_home = "/home/" + username;
			user_uid = get_user_id(username);
		}

		log_msg(string.nfill(70,'-'));
		log_msg(_("Selected user: %s, %s").printf(user_login,user_home));
		log_msg(string.nfill(70,'-'));
		log_msg("");
	}
	
	public bool check_dependencies(out string msg) {
		msg = "";

		string[] dependencies = { "rsync", "aptitude", "apt-get", "apt-cache", "gzip", "grep", "find", "chown", "rm", "add-apt-repository", "gdebi", "aria2c", "tar", "gpg", "duplicity"};

		string path;
		foreach(string cmd_tool in dependencies) {
			path = get_cmd_path (cmd_tool);
			if ((path == null) || (path.length == 0)) {
				msg += " * " + cmd_tool + "\n";
			}
		}

		if (msg.length > 0) {
			msg = _("Commands listed below are not available on this system") + ":\n\n" + msg + "\n";
			msg += _("Please install required packages and try running Aptik again");
			log_msg(msg);
			return false;
		}
		else {
			return true;
		}
	}

	public DateTime get_apt_list_modified_date(){
		try{
			FileInfo info;
			File file = File.parse_name (APT_LISTS_PATH);
			if (file.query_exists()) {
				info = file.query_info("%s".printf(FileAttribute.TIME_MODIFIED), 0);
				return (new DateTime.from_timeval_utc(info.get_modification_time())).to_local();
			}
		}
		catch (Error e) {
			log_error (e.message);
		}
		
		return (new DateTime.from_unix_utc(0)); //1970
	}

	/* Common */

	public bool check_backup_file(string file_name) {
		string backup_file = backup_dir + file_name;
		var f = File.new_for_path(backup_file);
		if (!f.query_exists()) {
			log_error(_("File not found in backup directory") + ": '%s'".printf(file_name));
			return false;
		}
		else {
			return true;
		}
	}

	public string create_log_dir() {
		string log_dir = backup_dir + "logs/" + timestamp3();
		create_dir(log_dir);
		return log_dir;
	}

	public void save_app_config() {
		var config = new Json.Object();

		config.set_string_member("backup_dir", backup_dir);
		config.set_string_member("selected_tasks", selected_tasks);

		var json = new Json.Generator();
		json.pretty = true;
		json.indent = 2;
		var node = new Json.Node(NodeType.OBJECT);
		node.set_object(config);
		json.set_root(node);

		try {
			json.to_file(this.app_conf_path);
		} catch (Error e) {
			log_error (e.message);
		}

		if (gui_mode) {
			log_msg(_("App config saved") + ": '%s'".printf(app_conf_path));
		}
	}

	public void load_app_config() {
		var f = File.new_for_path(app_conf_path);
		if (!f.query_exists()) {
			return;
		}

		var parser = new Json.Parser();
		try {
			parser.load_from_file(this.app_conf_path);
		} catch (Error e) {
			log_error (e.message);
		}
		var node = parser.get_root();
		var config = node.get_object();

		string val = json_get_string(config, "backup_dir", "");
		if ((val.length > 0) && (dir_exists(val))) {
			backup_dir = val;
		}

		selected_tasks = json_get_string(config, "selected_tasks", "");

		if (gui_mode) {
			log_msg(_("App config loaded") + ": '%s'".printf(this.app_conf_path));
		}
	}

	public string backup_dir {
		owned get{
			if (_backup_dir == null){
				_backup_dir = "";
			}
			return _backup_dir.has_suffix("/") ? _backup_dir : _backup_dir + "/";
		}
		set{
			_backup_dir = value.has_suffix("/") ? value : value + "/";
		}
	}
	
	/* Package selections */

	public void read_package_info(){
		string msg = "";
		if (get_apt_list_modified_date().compare(pkginfo_modified_date) > 0){
			msg = _("Reading package lists...");
			log_debug(msg);
			status_line = msg;
			read_package_lists();
		}

		msg = _("Reading state information...");
		log_debug(msg);
		status_line = msg;
		read_package_info_for_installed_packages();

		if (get_apt_list_modified_date().compare(pkginfo_modified_date) > 0){
			msg = _("Reading default package lists...");
			log_debug(msg);
			status_line = msg;
			read_package_info_for_default_packages();
			read_package_info_for_manual_packages();

			pkginfo_modified_date = new DateTime.now_local();
		}

		msg = _("Reading deb files from backup...");
		log_debug(msg);
		status_line = msg;
				
		update_deb_file_name_from_backup();
	}

	private void read_package_lists(){
		//clear lists
		pkg_list_master = new Gee.HashMap<string, Package>();
		sections = new Gee.ArrayList<string>();

		//iterate files in /var/lib/apt/lists
		
		try{
			FileInfo info;
			File file = File.new_for_path(APT_LISTS_PATH);
			FileEnumerator enumerator = file.enumerate_children ("%s".printf(FileAttribute.STANDARD_NAME), 0);
			while ((info = enumerator.next_file()) != null) {
				string file_name = info.get_name();
				string file_path = "%s/%s".printf(APT_LISTS_PATH, file_name);
			
				if (!file_name.has_suffix("_Packages")){ continue; }

				var map = read_status_file(file_path);

				var pkg_repo_name = file_name[0:file_name.index_of("_dists") - 1];
				var pkg_server = pkg_repo_name.replace("_","/");
				
				foreach(Package pkg in map.values){
					pkg_list_master[pkg.id] = pkg;
					pkg.is_available = true;
					pkg.version_available = pkg.version;
					pkg.server = pkg_server;

					if (!sections.contains(pkg.section)) {
						sections.add(pkg.section);
					}
				}
			}

			//sort sections by name
			CompareDataFunc<string> func = (a, b) => {
				return strcmp(a, b);
			};
			sections.sort((owned)func);
		}
		catch(Error e){
			log_error(e.message);
		}
	}

	private void read_package_info_for_installed_packages() {
		//set version_installed, is_installed, is_automatic
		
		log_debug("call: update_info_for_available_packages");

		string txt = execute_command_sync_get_output("aptitude search --disable-columns -F '%p|%v|%M|%d' '?installed'");
		write_file(PKG_CACHE_TEMP, txt);

		// TODO: Create an optimized method for writing output to file

		//read command output from temp file line by line

		foreach(Package pkg in pkg_list_master.values){
			pkg.is_installed = false;
			//pkg.is_deb = false; //do not reset
			pkg.is_automatic = false;
		}
		
		try {
			string line;
			var file = File.new_for_path (PKG_CACHE_TEMP);
			if (file.query_exists ()) {
				var dis = new DataInputStream (file.read());
				while ((line = dis.read_line (null)) != null) {
					string[] arr = line.split("|");
					if (arr.length != 4) {
						continue;
					}

					string name = arr[0].strip();
					string arch = (name.contains(":")) ? name.split(":")[1].strip() : "";
					if (name.contains(":")) { name = name.split(":")[0]; }
					string version = arr[1].strip();
					string auto = arr[2].strip();
					string desc = arr[3].strip();
					
					string id = Package.get_id(name,arch);

					Package pkg = null;
					if (pkg_list_master.has_key(id)) {
						pkg = pkg_list_master[id];
					}
					else{
						//installed from DEB file, add to master
						pkg = new Package(name);
						pkg.is_deb = true;
						pkg.arch = arch;
						pkg.description = desc;
						pkg.id = Package.get_id(pkg.name,pkg.arch);
						pkg_list_master[pkg.id] = pkg;
					}

					if (pkg != null){
						pkg.is_installed = true;
						pkg.is_automatic = (auto == "A");
						pkg.version_installed = version;
					}
				}
			}
			else {
				log_error (_("File not found: %s").printf(PKG_CACHE_TEMP));
			}
		}
		catch (Error e) {
			log_error (e.message);
		}
	}

	private Gee.HashMap<string,Package> read_status_file(string status_file){
		var map = new Gee.HashMap<string,Package>();

		try {
			string line;
			var file = File.new_for_path(status_file);
			if (!file.query_exists ()) {
				return map;
			}

			Package pkg = null;
			var dis = new DataInputStream (file.read());
			while ((line = dis.read_line (null)) != null) {
				if (line.strip().length == 0) { continue; }
				if (line.index_of(": ") == -1) { continue; }

				//Note: split on ': ' since version string can have colons
				
				string p_name = line[0:line.index_of(": ")].strip();
				string p_value = line[line.index_of(": ") + 2:line.length].strip();

				switch (p_name.down()){
				case "package":
					//add previous pkg to list
					if (pkg != null){
						pkg.id = Package.get_id(pkg.name,pkg.arch);
						map[pkg.id] = pkg;
						pkg = null;
					}
					//create new pkg
					pkg = new Package(p_value);
					break;
				case "section":
					pkg.section = p_value;
					if (pkg.section.contains("/")){
						pkg.section = pkg.section.split("/")[1];
					}
					if (!sections.contains(pkg.section)) {
						sections.add(pkg.section);
					}
					break;
				case "architecture":
					pkg.arch = p_value;
					break;
				case "version":
					pkg.version = p_value;
					break;
				case "description":
					pkg.description = p_value;
					break;
				}
			}

			//add last pkg to list
			if (pkg != null){
				pkg.id = Package.get_id(pkg.name,pkg.arch);
				map[pkg.id] = pkg;
				pkg = null;
			}
		}
		catch (Error e) {
			log_error (e.message);
		}
		
		return map;
	}
	
	private void read_package_info_for_default_packages() {
		//sets: is_default
		
		log_debug("call: update_info_for_default_packages");

		if (!file_exists(DEF_PKG_LIST)) {
			default_list_missing = true;
			return;
		}

		if (!file_exists(DEF_PKG_LIST_UNPACKED)){
			string txt = "";
			execute_command_script_sync("gzip -dc '%s'".printf(DEF_PKG_LIST),out txt,null);
			write_file(DEF_PKG_LIST_UNPACKED,txt);
		}
		
		try {
			string line;
			var file = File.new_for_path(DEF_PKG_LIST_UNPACKED);
			if (!file.query_exists ()) {
				log_error(_("Failed to unzip: '%s'").printf(DEF_PKG_LIST_UNPACKED));
			}

			Package pkg = null;
			var dis = new DataInputStream (file.read());
			while ((line = dis.read_line (null)) != null) {

				if (line.strip().length == 0) { continue; }
				if (line.index_of(": ") == -1) { continue; }

				//Note: split on ': ' since version string can have colons
				
				string p_name = line[0:line.index_of(": ")].strip();
				string p_value = line[line.index_of(": ") + 2:line.length].strip();
				
				switch(p_name.down()){
					case "package":
						//add previous pkg to list
						if (pkg != null){
							pkg.id = Package.get_id(pkg.name,pkg.arch);
							if (pkg_list_master.has_key(pkg.id)){
								pkg_list_master[pkg.id].is_default = true;
							}
							pkg = null;
						}

						//create new pkg
						pkg = new Package(p_value);
						pkg.is_available = true;
						break;
					case "architecture":
						pkg.arch = p_value;
						break;
					case "version":
						pkg.version_available = p_value;
						break;
				}
			}
		}
		catch (Error e) {
			log_error (e.message);
		}
	}

	private void read_package_info_for_manual_packages() {
		//sets: is_manual
		
		log_debug("call: update_info_for_manual_packages");

		foreach(Package pkg in pkg_list_master.values) {
			if (pkg.is_installed && !pkg.is_default && !pkg.is_automatic) {
				pkg.is_manual = true;
			}
		}
	}

	public void update_deb_file_name_from_backup(){
		string deb_dir = backup_dir + "debs";

		//reset 'deb_file_name'
		foreach(Package pkg in pkg_list_master.values) {
			pkg.deb_file_name = "";
		}
		
		try{
			FileInfo info;
			File file = File.new_for_path(deb_dir);
			if (!file.query_exists()){
				return;
			}	
			
			FileEnumerator enumerator = file.enumerate_children ("%s".printf(FileAttribute.STANDARD_NAME), 0);
			while ((info = enumerator.next_file()) != null) {
				string file_name = info.get_name();
				string file_path = "%s/%s".printf(deb_dir, file_name);
			
				if (!file_name.has_suffix(".deb")){ continue; }

				update_deb_file_name_from_backup_single(file_path);
			}
		}
		catch(Error e){
			log_error(e.message);
		}
	}

	public void update_deb_file_name_from_backup_single(string deb_file_path){
		//get package info from DEB file
		string txt = execute_command_sync_get_output("dpkg --info '%s'".printf(deb_file_path));
		Package pkg = null;
		foreach(string line in txt.split("\n")){
			if (line.strip().length == 0) { continue; }
			if (line.index_of(": ") == -1) { continue; }
			
			string p_name = line[0:line.index_of(": ")].strip();
			string p_value = line[line.index_of(": ") + 2:line.length].strip();

			switch(p_name.down()){
				case "package":
					//create new pkg
					pkg = new Package(p_value);
					pkg.is_available = true;
					break;
				case "section":
					pkg.section = p_value;
					if (pkg.section.contains("/")){
						pkg.section = pkg.section.split("/")[1];
					}
					if (!sections.contains(pkg.section)) {
						sections.add(pkg.section);
					}
					break;
				case "architecture":
					pkg.arch = p_value;
					break;
				case "version":
					pkg.version_available = p_value;
					break;
				case "description":
					pkg.description = p_value;
					break;
				case "depends":
					pkg.depends = p_value;
					break;
			}
		}

		if (pkg != null){
			pkg.id = Package.get_id(pkg.name,pkg.arch);
			if (pkg_list_master.has_key(pkg.id)) {
				Package pkg_2 = pkg_list_master[pkg.id];
				string file_name = deb_file_path[deb_file_path.last_index_of("/")+1:deb_file_path.length];
				pkg_2.is_deb = true;
				pkg_2.deb_file_name = file_name;
				pkg_2.description = pkg.description;
			}
		}
	}

	private void print_pkg_info(){
		log_msg("\"%s\",\"%s\",\"%s\",\"%s\",\"%s\",\"%s\"".printf(
		"id","name","arch","section","version_available","description"));
		
		foreach(var pkg in pkg_list_master.values){
			log_msg("\"%s\",\"%s\",\"%s\",\"%s\",\"%s\",\"%s\"".printf(
			pkg.id,pkg.name,pkg.arch,pkg.section,pkg.version_available,pkg.description));
		}
	}

	public bool save_package_list_selected() {

		/* Saves the package names to file.
		 * Unselected package names are commented with #
		 * */

		string list_file = backup_dir + (backup_dir.has_suffix("/") ? "" : "/") + PKG_LIST_BAK;

		var pkg_list = new ArrayList<Package>();
		foreach(Package pkg in pkg_list_master.values) {
			if (pkg.is_selected) {
				pkg_list.add(pkg);
			}
		}
		CompareDataFunc<Package> func = (a, b) => {
			return strcmp(a.name, b.name);
		};
		pkg_list.sort((owned)func);

		string text = "";
		foreach(Package pkg in pkg_list) {
			if (pkg.is_selected) {
				text += "%s #%s\n".printf(pkg.id,pkg.description);
			}
		}

		bool is_success = write_file(list_file, text);

		return is_success;
	}

	public bool save_package_list_installed() {

		/* Saves the installed package names to file.
		 * */

		string list_file = backup_dir + (backup_dir.has_suffix("/") ? "" : "/") + PKG_LIST_INSTALLED_BAK;

		var pkg_list = new ArrayList<Package>();
		foreach(Package pkg in pkg_list_master.values) {
			pkg_list.add(pkg);
		}
		CompareDataFunc<Package> func = (a, b) => {
			return strcmp(a.name, b.name);
		};
		pkg_list.sort((owned)func);

		string text = "";
		foreach(Package pkg in pkg_list) {
			if (pkg.is_installed) {
				text += "%s\n".printf(pkg.id);
			}
		}

		bool is_success = write_file(list_file, text);

		if (is_success) {
			log_msg(_("File saved") + " '%s'".printf(PKG_LIST_INSTALLED_BAK));
		}
		else {
			log_error(_("Failed to write")  + " '%s'".printf(PKG_LIST_INSTALLED_BAK));
		}

		return is_success;
	}

	private Gee.ArrayList<Package> read_package_list_from_backup() {
		string pkg_list_file = backup_dir + (backup_dir.has_suffix("/") ? "" : "/") + PKG_LIST_BAK;
		var pkg_list = new Gee.ArrayList<Package>();

		//check file
		if (!check_backup_file(PKG_LIST_BAK)) {
			return pkg_list;
		}

		//read package names
		foreach(string line in read_file(pkg_list_file).split("\n")) {
			if (line.strip().length == 0) {
				continue;
			}

			if (!line.strip().has_prefix("#")) {
				string pkg_id = line.strip();
				string pkg_desc = "";
				
				if (line.strip().contains("#")){
					pkg_id = pkg_id[0:pkg_id.index_of("#") - 1];
					pkg_desc = pkg_id[pkg_id.index_of("#") + 1 : pkg_id.length];
				}

				string pkg_name = pkg_id.contains(":") ? pkg_id[0:pkg_id.last_index_of(":") - 1] : pkg_id;
				string pkg_arch = pkg_id.contains(":") ? pkg_id[pkg_id.last_index_of(":") + 1: pkg_id.length] : "";
				
				Package pkg = new Package(pkg_name);
				pkg.id = pkg_id;
				pkg.arch = pkg_arch;
				pkg.description = pkg_desc;
				pkg.in_backup_list = true;
				pkg_list.add(pkg);
			}
		}

		return pkg_list;
	}

	public void update_pkg_list_master_for_restore(bool update_selections){
		string deb_dir = backup_dir + "debs";

		foreach(Package pkg in pkg_list_master.values) {
			if (update_selections){
				//unselect all
				pkg.is_selected = false;
			}
			pkg.in_backup_list = false;
		}

		//read backup file
		var list_bak = read_package_list_from_backup();
		
		foreach(Package pkg_bak in list_bak) {
			if (!pkg_list_master.has_key(pkg_bak.id)){
				pkg_list_master[pkg_bak.id] = pkg_bak;
			}

			pkg_list_master[pkg_bak.id].in_backup_list = true;
		}

		update_deb_file_name_from_backup();

		if (update_selections){
			foreach(Package pkg in pkg_list_master.values) {
				//select if not installed and available for installation
				pkg.is_selected = pkg.in_backup_list && !pkg.is_installed &&
					(pkg.is_available || (pkg.is_deb && pkg.deb_file_name.length > 0));
			}
		}
		
		// create a list of packages to be installed -------------------
		
		pkg_list_install = "";
		pkg_list_missing = "";
		pkg_list_deb = "";
		gdebi_list = "";
		
		foreach(Package pkg in pkg_list_master.values) {
			if (!pkg.is_selected || pkg.is_installed){
				continue;
			}

			//available in repo
			if (pkg.is_available) {
				pkg_list_install += " %s".printf(pkg.id);
			}
			else{ //not available
				
				//DEB file available
				if (pkg.is_deb && (pkg.deb_file_name.length > 0)) {
					pkg_list_deb += " %s".printf(pkg.id);
					gdebi_list += "'%s/%s'\n".printf(deb_dir,pkg.deb_file_name);
				}
				else{
					pkg_list_missing += " %s".printf(pkg.id);
				}
			}
		}

		pkg_list_install = pkg_list_install.strip();
		pkg_list_deb = pkg_list_deb.strip();
		pkg_list_missing = pkg_list_missing.strip();
		gdebi_list = gdebi_list.strip();
	}

	public void copy_deb_file(string src_file){
		string deb_dir = backup_dir + "debs";
		create_dir(deb_dir);
		string file_name = src_file[src_file.last_index_of("/")+1:src_file.length];
		string dest_file = deb_dir + "/" + file_name;
		file_copy(src_file,dest_file);
		update_deb_file_name_from_backup_single(dest_file);
	}

	public Gee.ArrayList<Package> get_download_uris(string pkg_names){
		var pkg_list = new Gee.ArrayList<Package>();
		
		string cmd = "apt-get install -y --print-uris %s".printf(pkg_names);

		log_debug("execute: " + cmd);
		
		string txt = execute_command_sync_get_output(cmd);

		Regex regex = null;
		MatchInfo match;
		
		try {
			//Sample:
			//'http://us.archive.ubuntu.com/ubuntu/pool/main/f/firefox/firefox_43.0.4+build3-0ubuntu0.15.04.1_amd64.deb' firefox_43.0.4+build3-0ubuntu0.15.04.1_amd64.deb 45095814 MD5Sum:bc2e305042e265725ca8548308d8d14a
			regex = new Regex("""^'([^']+)'[ \t]+([^ \t]+)[ \t]+([0-9]+)[ \t]+[^:]+:([^ \t]+)$""");
		}
		catch (Error e) {
			log_error (e.message);
		}
		
		foreach(string line in txt.split("\n")){
			if (regex.match(line, 0, out match)) {
				string deb_uri = match.fetch(1).strip();
				string deb_name = match.fetch(2).strip();
				int64 deb_size = int64.parse(match.fetch(3).strip());
				string deb_md5hash = match.fetch(4).strip();

				string pkg_name = deb_name.split("_")[0];
				var pkg = new Package(pkg_name);
				pkg.deb_uri = deb_uri;
				pkg.deb_file_name = deb_name;
				pkg.deb_size = deb_size;
				pkg.deb_md5hash = deb_md5hash;
				pkg_list.add(pkg);
			}
		}

		CompareDataFunc<Package> func = (a, b) => {
			return strcmp(a.name, b.name);
		};
		pkg_list.sort((owned)func);

		return pkg_list;
	}
	
	/* PPA */

	public void ppa_backup_init(bool query_pkg_info = true){
		if (query_pkg_info){
			App.read_package_info();
		}
		App.ppa_list_master = App.list_ppa();
	}

	public void ppa_restore_init(bool query_pkg_info = true){
		if (query_pkg_info){
			App.read_package_info();
		}
		App.ppa_list_master = App.list_ppa();
		App.read_ppa_list();
	}
	
	public Gee.HashMap<string,Ppa> list_ppa(){
		ppa_list_master = list_ppas_from_etc_apt_dir();

		update_info_for_repository();

		return ppa_list_master;
	}
	
	public Gee.HashMap<string,Ppa> list_ppas_from_etc_apt_dir(){
		var msg = _("Reading source lists...");
		log_debug(msg);
		status_line = msg;

		var ppa_list = new Gee.HashMap<string,Ppa>();

		string std_out = "";
		string std_err = "";
		string cmd = "rsync -aim --dry-run --include=\"*.list\" --include=\"*/\" --exclude=\"*\" \"%s/\" /tmp".printf("/etc/apt");
		int exit_code = execute_command_script_sync(cmd, out std_out, out std_err);

		if (exit_code != 0){
			return ppa_list; //no files found
		}

		Regex rex_ppa;
		MatchInfo match;

		try{
			rex_ppa = new Regex("""^deb http://ppa.launchpad.net/([a-z0-9.-]+/[a-z0-9.-]+)""");
		}
		catch (Error e) {
			log_error (e.message);
			return ppa_list;
		}

		string file_path;
		string ppa_name;
		foreach(string line in std_out.split("\n")){
			if (line == null){ continue; }
			if (line.length == 0){ continue; }

			file_path = line.strip();
			if (file_path.has_suffix("~")){ continue; }
			if (file_path.split(" ").length < 2){ continue; }
			if (!file_path.has_suffix(".list")){ continue; }

			file_path = "/etc/apt/" + file_path[file_path.index_of(" ") + 1:file_path.length].strip();

			string txt = read_file(file_path);
			foreach(string list_line in txt.split("\n")){
				if (rex_ppa.match (list_line, 0, out match)){
					ppa_name = match.fetch(1).strip();

					var ppa = new Ppa(ppa_name);
					ppa.is_selected = true;
					ppa.is_installed = true;
					ppa_list[ppa_name] = ppa;
				}
			}
		}

		return ppa_list;
	}

	//sets: server and repo
	public void update_info_for_repository() {
		var msg = _("Reading package priorities...");
		log_debug(msg);
		status_line = msg;
		
		string cmd = "";
		foreach(Package pkg in pkg_list_master.values){
			if (pkg.is_installed){
				cmd += " %s".printf(pkg.id);
			}
		}
		cmd = "apt-cache policy %s".printf(cmd);
		//Note: we are listing each package by name since 'apt-cache policy .' only gives info for native packages
		
		string txt = execute_command_sync_get_output(cmd);

		write_file(PKG_CACHE_TEMP, txt);

		// TODO: Create an optimized method for writing output to file

		string line = null;
		string pkg_name = "";
		string pkg_server = "";
		string pkg_repo = "";
		string pkg_repo_section = "";
		//string pkg_arch = "";

		Regex regex_pkg = null;
		Regex regex_installed_version = null;
		Regex regex_source = null;
		Regex regex_launchpad = null;
		MatchInfo match;

		try {

			/*
			selene:
			  Installed: 2.5.7~196~ubuntu15.04.1
			  Candidate: 2.5.7~196~ubuntu15.04.1
			  Version table:
			 *** 2.5.7~196~ubuntu15.04.1 0
			        500 http://ppa.launchpad.net/teejee2008/ppa/ubuntu/ vivid/main amd64 Packages
			        100 /var/lib/dpkg/status
			*/

			/*
			notepadqq:
			  Installed: 0.50.6-0~vivid1
			  Candidate: 0.51.0-0~vivid1
			  Version table:
				 0.51.0-0~vivid1 0
					500 http://ppa.launchpad.net/notepadqq-team/notepadqq/ubuntu/ vivid/main amd64 Packages
			 *** 0.50.6-0~vivid1 0
					100 /var/lib/dpkg/status
			*/
			
			/* Note: for linking a package with it's PPA the apt-cache policy output is not reliable
			 * Once an update is available, the ppa line for the installed version ( *** 0.50.6-0~vivid1 0)
			 * will have '/var/lib/dpkg/status' instead of the repository URI
			 * */
			 
			regex_pkg = new Regex("""^([^ \t]*):$""");
			regex_installed_version = new Regex("""^[ \t]*[*]*[ \t]*([^ \t]*)[ \t]*[0-9]*""");
			regex_source = new Regex("""[ \t]*[0-9]+[ \t]*([^ \t]*ubuntu.com[^ \t])[ \t]*([^ \t]*)[ \t]*([^ \t]*)""");
			regex_launchpad = new Regex("""[ \t]*[0-9]+[ \t]*([https:/]+ppa.launchpad.net/([^ \t]*)/ubuntu/)[ \t]*([^ \t]*)[ \t]*([^ \t]*)""");
		}
		catch (Error e) {
			log_error (e.message);
		}

		try {
			int count_pkg = 0;
			var file = File.new_for_path (PKG_CACHE_TEMP);
			if (!file.query_exists()) {
				log_error (_("File not found: %s").printf(PKG_CACHE_TEMP));
				return;
			}

			var dis = new DataInputStream (file.read());
			while ((line = dis.read_line (null)) != null) {
				if (line.strip().length == 0) {
					continue;
				}

				if (regex_pkg.match (line, 0, out match)) {
					pkg_name = match.fetch(1).strip();
					count_pkg++;
				}
				else if (regex_launchpad.match (line, 0, out match)) {

					pkg_server = match.fetch(1).strip();
					pkg_repo = match.fetch(2).strip();
					pkg_repo_section = match.fetch(3).strip();

					if (pkg_server.length == 0) {
						continue;
					}

					//add new ppa to master list
					if (!ppa_list_master.has_key(pkg_repo)) {
						var ppa = new Ppa(pkg_repo);
						ppa.is_installed = true;
						ppa_list_master[pkg_repo] = ppa;
					}

					//update ppa and package information
					if (ppa_list_master.has_key(pkg_repo)) {
						var ppa = ppa_list_master[pkg_repo];

						if (pkg_list_master.has_key(pkg_name)) {
							var pkg = pkg_list_master[pkg_name];

							//log_msg("%s : %s".printf(pkg_name,pkg_server));
							
							//update package info
							pkg.server = pkg_server;
							pkg.repo = pkg_repo;
							pkg.repo_section = pkg_repo_section;

							//update PPA info
							if (pkg.is_installed) {
								ppa.description += "%s ".printf(pkg_name);
							}
							ppa.all_packages += "%s ".printf(pkg_name);
						}
					}
				}
				else if (regex_source.match (line, 0, out match)) {

					pkg_server = match.fetch(1).strip();
					pkg_repo = "official";
					pkg_repo_section = match.fetch(2).strip();
					//pkg_arch = match.fetch(4).strip();

					//update package info
					if (pkg_list_master.has_key(pkg_name)) {
						Package pkg = pkg_list_master[pkg_name];
						pkg.server = pkg_server;
						pkg.repo = pkg_repo;
						pkg.repo_section = pkg_repo_section;
					}
				}
			}
		}
		catch (Error e) {
			log_error (e.message);
		}
	}

	public bool save_ppa_list_selected() {
		string file_name = "ppa.list";
		string ppa_list_file = backup_dir + file_name;

		//create an arraylist and sort items for printing
		var ppa_list = new ArrayList<Ppa>();
		foreach(Ppa ppa in ppa_list_master.values) {
			if (ppa.is_selected & (ppa.name != "official")) {
				ppa_list.add(ppa);
			}
		}
		CompareDataFunc<Ppa> func = (a, b) => {
			return strcmp(a.name, b.name);
		};
		ppa_list.sort((owned)func);

		string text = "";
		foreach(Ppa ppa in ppa_list) {
			if (ppa.is_selected) {
				text += "%s #%s\n".printf(ppa.name, ppa.description);
			}
			else {
				text += "#%s #%s\n".printf(ppa.name, ppa.description);
			}
		}

		bool is_success = write_file(ppa_list_file, text);

		return is_success;
	}

	public void read_ppa_list() {
		string file_name = "ppa.list";
		string ppa_list_file = backup_dir + file_name;

		//check file
		if (!check_backup_file(file_name)) {
			return;
		}

		foreach(Ppa ppa in ppa_list_master.values){
			ppa.is_selected = false;
		}
		
		//read file
		foreach(string line in read_file(ppa_list_file).split("\n")) {
			if (line.strip() == "") {
				continue;
			}

			string ppa_name = "";
			string ppa_desc = "";
			bool ppa_selected;

			if (line.strip().has_prefix("#")) {
				ppa_selected = false;
				ppa_name = line.split("#")[1].strip();
				if (line.split("#").length == 3) {
					ppa_desc = line.split("#")[2].strip();
				}
			}
			else {
				ppa_selected = true;
				if (line.split("#").length == 2) {
					ppa_name = line.split("#")[0].strip();
					ppa_desc = line.split("#")[1].strip();
				}
				else {
					ppa_name = line.strip();
				}
			}

			//add new ppa to master list, set: is_selected, is_installed
			if (ppa_list_master.has_key(ppa_name)) {
				Ppa ppa = ppa_list_master[ppa_name];
				ppa.is_installed = true;
				ppa.is_selected = false;
				if (ppa.description.length == 0){
					ppa.description = ppa_desc;
				}
			}
			else {
				Ppa ppa = new Ppa(ppa_name);
				ppa.is_installed = false;
				ppa.is_selected = ppa_selected;
				ppa.description = ppa_desc;
				ppa_list_master[ppa_name] = ppa;
			}
		}
	}


	public bool add_ppa (string cmd) {
		string[] argv = new string[1];
		argv[0] = save_script(cmd);

		try {
			//execute script file
			Process.spawn_async_with_pipes(
			    temp_dir, //working dir
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

			//progress_count = 0;
			stdout_lines = new Gee.ArrayList<string>();
			stderr_lines = new Gee.ArrayList<string>();

			try {
				//start thread for reading output stream
				Thread.create<void> (add_ppa_read_output_line, true);
			} catch (Error e) {
				log_error (e.message);
			}

			try {
				//start thread for reading error stream
				Thread.create<void> (add_ppa_read_error_line, true);
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

	private void add_ppa_read_error_line() {
		try {
			err_line = dis_err.read_line (null);
			while (err_line != null) {
				if (err_line.length > 0){
					stderr_lines.add(err_line);
					status_line = err_line;
					//log_msg("err: %s".printf(err_line));
				}
				
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

	private void add_ppa_read_output_line() {
		try {
			out_line = dis_out.read_line (null);
			while (out_line != null) {
				if (out_line.length > 0){
					stdout_lines.add(out_line);
					status_line = out_line;
					//log_msg("out: %s".printf(out_line));
				}
				
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


	public bool apt_get_update () {
		string[] argv = new string[1];
		argv[0] = save_script("apt-get -y update");

		try {
			//execute script file
			Process.spawn_async_with_pipes(
			    temp_dir, //working dir
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

			//progress_count = 0;
			stdout_lines = new Gee.ArrayList<string>();
			stderr_lines = new Gee.ArrayList<string>();

			try {
				//start thread for reading output stream
				Thread.create<void> (apt_get_update_read_output_line, true);
			} catch (Error e) {
				log_error (e.message);
			}

			try {
				//start thread for reading error stream
				Thread.create<void> (apt_get_update_read_error_line, true);
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

	private void apt_get_update_read_error_line() {
		try {
			err_line = dis_err.read_line (null);
			while (err_line != null) {
				if (err_line.length > 0){
					stderr_lines.add(err_line);
					status_line = err_line;
					//log_msg("err: %s".printf(err_line));
				}
				
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

	private void apt_get_update_read_output_line() {
		try {
			out_line = dis_out.read_line (null);
			while (out_line != null) {
				if (out_line.length > 0){
					stdout_lines.add(out_line);
					status_line = out_line;
					//log_msg("out: %s".printf(out_line));
					progress_count++;
				}
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


	private string save_script(string cmd){
		var script = new StringBuilder();
		script.append ("#!/bin/bash\n");
		script.append ("\n");
		script.append ("LANG=C\n");
		script.append ("\n");
		script.append ("%s\n".printf(cmd));
		script.append ("\n\nexitCode=$?\n");
		script.append ("echo ${exitCode} > ${exitCode}\n");
		script.append ("echo ${exitCode} > status\n");

		temp_dir = TEMP_DIR + "/" + timestamp2();
		var script_file = temp_dir + "/script.sh";
		create_dir (temp_dir);
		
		try {
			// create new script file
			var file = File.new_for_path(script_file);
			var file_stream = file.create(FileCreateFlags.REPLACE_DESTINATION);
			var data_stream = new DataOutputStream(file_stream);
			data_stream.put_string(script.str);
			data_stream.close();

			//set execute permission
			chmod(script_file, "u+x");
		}
		catch (Error e) {
			log_error (e.message);
		}

		return script_file;
	}

	public int read_status(){
		var path = temp_dir + "/status";
		var f = File.new_for_path(path);
		if (f.query_exists()){
			var txt = read_file(path);
			return int.parse(txt);
		}
		return -1;
	}
	
	/* APT Cache */

	public bool backup_apt_cache() {
		string archives_dir = backup_dir + "archives";

		try {
			//create 'archives' directory
			var f = File.new_for_path(archives_dir);
			if (!f.query_exists()) {
				f.make_directory_with_parents();
			}

			string cmd = "rsync -ai --numeric-ids --list-only";
			cmd += " --exclude=lock --exclude=partial/";
			cmd += " %s %s".printf("/var/cache/apt/archives/", archives_dir + "/");

			if (gui_mode) {
				//run rsync to get total count
				string txt = execute_command_sync_get_output(cmd);
				progress_total = txt.split("\n").length;

				//run rsync
				run_rsync(cmd.replace(" --list-only", ""));
			}
			else {
				int status = Posix.system(cmd.replace(" --list-only", ""));
				return (status == 0);
			}

			return true;
		}
		catch (Error e) {
			log_error (e.message);
			return false;
		}
	}

	public bool restore_apt_cache() {
		string archives_dir = backup_dir + "archives";

		//check 'archives' directory
		var f = File.new_for_path(archives_dir);
		if (!f.query_exists()) {
			log_error(_("Cache backup not found in backup directory"));
			return false;
		}

		string cmd = "rsync -ai --numeric-ids --list-only";
		cmd += " --exclude=lock --exclude=partial/";
		cmd += " %s %s".printf(archives_dir + "/", "/var/cache/apt/archives/");

		if (gui_mode) {
			//run rsync to get total count
			string txt = execute_command_sync_get_output(cmd);
			progress_total = txt.split("\n").length;

			//run rsync
			return run_rsync(cmd.replace(" --list-only", ""));
		}
		else {
			int status = Posix.system(cmd.replace(" --list-only", ""));
			return (status == 0);
		}
	}


	private bool run_rsync (string cmd) {
		string[] argv = new string[1];
		argv[0] = save_bash_script_temp(cmd);

		try {
			//execute script file
			Process.spawn_async_with_pipes(
			    temp_dir, //working dir
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

	private void rysnc_read_error_line() {
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

	private void rysnc_read_output_line() {
		try {
			out_line = dis_out.read_line (null);
			while (out_line != null) {
				if (gui_mode) {
					progress_count += 1; //count
					if (out_line.contains(" ")) {
						status_line = out_line.split(" ")[1].strip(); //package name
					}
				}
				else {
					stdout.printf(out_line + "\n"); //print
				}

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

	public void rsync_quit(){
		log_debug("process_quit(): %d".printf(child_pid));
		process_quit(child_pid);
	}
	
	/* App Settings */

	public bool backup_app_settings_all(Gee.ArrayList<AppConfig> config_list) {
		bool ok = true;
		
		backup_app_settings_init(config_list);

		foreach(AppConfig config in config_list) {
			if (!config.is_selected) {
				continue;
			}

			if ((App.arg_size_limit > 0) && (config.bytes > App.arg_size_limit)){
				continue;
			}

			var status = backup_app_settings_single(config);
			ok = ok && status;
		}

		return ok;
	}

	public void backup_app_settings_init(Gee.ArrayList<AppConfig> config_list){
		//get total file count
		progress_total = 0;
		progress_count = 0;
		foreach(AppConfig config in config_list) {
			if (!config.is_selected) {
				continue;
			}

			if ((App.arg_size_limit > 0) && (config.bytes > App.arg_size_limit)){
				continue;
			}
			
			progress_total += (int) get_file_count(config.path);
		}
	}
	
	public bool backup_app_settings_single(AppConfig config) {
		string cmd;

		string backup_dir_config = "%sconfigs/%s".printf(backup_dir, user_login);
		create_dir(backup_dir_config);
		
		try {
			string name = config.name.replace("~/", "");
			string zip_file ="%s/%s.tgz".printf(backup_dir_config,name);

			if (name.contains("/")){
				string parent_dir = "%s/%s".printf(backup_dir_config, name[0:name.last_index_of("/")]);
				create_dir(parent_dir);
			}
			
			//delete zip file
			var f = File.new_for_path(zip_file);
			if (f.query_exists()) {
				f.delete();
			}

			//zip selected folder
			cmd = "tar czvf '%s' -C '%s' '%s'".printf(zip_file, user_home, name);
			status_line = "";

			if (gui_mode) {
				run_gzip(cmd);
			}
			else {
				stdout.printf("%-60s".printf(_("Archiving") + " '%s'".printf(config.name)));
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
	
	public Gee.ArrayList<AppConfig> list_app_config_directories_from_home() {
		return list_app_config_directories_from_path(user_home);
	}

	public Gee.ArrayList<AppConfig> list_app_config_directories_from_path(string base_path) {
		var app_config_list = new Gee.ArrayList<AppConfig>();
		FileInfo file;
		
		try
		{
			//list all items in home except .config and .local
			File f_home = File.new_for_path (base_path);
			FileEnumerator enumerator = f_home.enumerate_children ("%s".printf(FileAttribute.STANDARD_NAME), 0);
			while ((file = enumerator.next_file ()) != null) {
				string name = file.get_name();
				string item = base_path + "/" + name;
				if (!name.has_prefix(".")) {
					continue;
				}
				if (name.has_suffix(".lock")) {
					continue;
				}
				switch (name.down()){
				case ".config":
				case ".local":
				case ".gvfs":
				case ".trash":
				case ".temp":
				case ".thumbnails":
				case ".sudo_as_admin_successful":
					continue;
				}

				AppConfig entry = new AppConfig("~/%s".printf(name));
				entry.bytes = dir_size(item);
				entry.size = format_file_size(entry.bytes);
				entry.description = get_config_dir_description(entry.name);
				app_config_list.add(entry);

				switch (name) {
				case ".cache":
					entry.is_selected = false;
					break;
				}
			}
		}
		catch (Error e) {
			log_error (e.message);
		}

		try{
			//list all items in .config
			File f_home_config = File.new_for_path (base_path + "/.config");
			if (f_home_config.query_exists()){
				var enumerator = f_home_config.enumerate_children ("%s".printf(FileAttribute.STANDARD_NAME), 0);
				while ((file = enumerator.next_file ()) != null) {
					string name = file.get_name();
					string item = base_path + "/.config/" + name;
					if (name.has_suffix(".lock")) {
						continue;
					}

					AppConfig entry = new AppConfig("~/.config/%s".printf(name));
					entry.bytes = dir_size(item);
					entry.size = format_file_size(entry.bytes);
					entry.description = get_config_dir_description(entry.name);
					app_config_list.add(entry);
				}
			}
		}
		catch (Error e) {
			log_error (e.message);
		}

		try{
			//list all items in .local/share
			var f_home_local = File.new_for_path (base_path + "/.local/share");
			if (f_home_local.query_exists()){
				var enumerator = f_home_local.enumerate_children ("%s".printf(FileAttribute.STANDARD_NAME), 0);
				while ((file = enumerator.next_file ()) != null) {
					string name = file.get_name();
					string item = base_path + "/.local/share/" + name;
					if (name.has_suffix(".lock")) {
						continue;
					}
					switch (name.down()){
					case "trash":
						continue;
					}

					AppConfig entry = new AppConfig("~/.local/share/%s".printf(name));
					entry.bytes = dir_size(item);
					entry.size = format_file_size(entry.bytes);
					entry.description = get_config_dir_description(entry.name);
					app_config_list.add(entry);
				}
			}
		}
		catch (Error e) {
			log_error (e.message);
		}

		//sort the list
		CompareDataFunc<AppConfig> entry_compare = (a, b) => {
			return strcmp(a.path, b.path);
		};
		app_config_list.sort((owned) entry_compare);

		return app_config_list;
	}

	public Gee.ArrayList<AppConfig> list_app_config_directories_from_backup() {
		var app_config_list = new Gee.ArrayList<AppConfig>();
		string backup_dir_config = "%sconfigs/%s".printf(backup_dir, user_login);
		
		list_app_config_directories_from_backup_path(backup_dir_config, ref app_config_list);
		
		//sort the list
		CompareDataFunc<AppConfig> entry_compare = (a, b) => {
			return strcmp(a.path, b.path);
		};
		app_config_list.sort((owned)entry_compare);

		return app_config_list;
	}

	public void list_app_config_directories_from_backup_path(string backup_path, ref Gee.ArrayList<AppConfig> app_config_list) {
		string backup_dir_config = "%sconfigs/%s".printf(backup_dir, user_login);

		try{
			File f_bak = File.new_for_path (backup_path);
			FileEnumerator enumerator = f_bak.enumerate_children ("%s".printf(FileAttribute.STANDARD_NAME), 0);
			
			FileInfo file;
			while ((file = enumerator.next_file ()) != null) {
				string name = file.get_name();
				string path = backup_path + "/" + name;
				if (dir_exists(path)){
					list_app_config_directories_from_backup_path(path, ref app_config_list);
				}
				else{
					string item_name = path.replace(backup_dir_config,"~");
					item_name = item_name[0:item_name.length - 4];
					var conf = new AppConfig(item_name);
					conf.description = get_config_dir_description(conf.name);
					app_config_list.add(conf);
				}
			}
		}
		catch (Error e) {
			log_error (e.message);
		}
	}

	public string get_config_dir_description(string name) {
		switch (name) {
		case "~/.mozilla":
			return _("Firefox Web Browser");
		case "~/.cache":
			return "";
		case "~/.opera":
			return _("Opera Web Browser");
		case "~/.fonts":
			return _("Local Fonts");
		case "~/.themes":
			return _("Local Themes");
		case "~/.bash_history":
			return _("Bash Command History");
		case "~/.bashrc":
			return _("Bash Init Script");
		case "~/.bash_logout":
			return _("Bash Logout Script");
		case "~/.config/fonts":
			return _("Local Fonts");
		case "~/.config/themes":
			return _("Local Themes");
		case "~/.config/chromium":
			return _("Chromium Web Browser");
		case "~/.config/autostart":
			return _("Startup Applications");
		default:
			return "";
		}
	}

	public bool restore_app_settings_all(Gee.ArrayList<AppConfig> config_list) {
		bool ok = true;
		
		restore_app_settings_init(config_list);
		
		foreach(AppConfig config in config_list) {
			if (config.is_selected) {
				var status = restore_app_settings_single(config);
				ok = ok && status;
			}
		}

		update_ownership(config_list);

		return ok;
	}

	public void restore_app_settings_init(Gee.ArrayList<AppConfig> config_list) {
		//get file count before unzipping
		progress_total = 0;
		progress_count = 0;
		foreach(AppConfig config in config_list) {
			if (config.is_selected) {
				string name = config.name.replace("~/", "");
				string backup_dir_config = "%sconfigs/%s".printf(backup_dir, user_login);
				string zip_file = "%s/%s.tgz".printf(backup_dir_config, name);
				string cmd = "tar tzvf '%s' | wc -l".printf(zip_file);
				string stderr, stdout;
				execute_command_script_sync(cmd, out stdout, out stderr, true);
				progress_total += long.parse(stdout);
			}
		}
		//log_msg("Total=%ld".printf(progress_total));
	}
	
	public bool restore_app_settings_single(AppConfig config) {
		string cmd;
		string base_dir_target = user_home;

		string backup_dir_config = "%sconfigs/%s".printf(backup_dir, user_login);
		string name = config.name.replace("~/", "");
		string zip_file = "%s/%s.tgz".printf(backup_dir_config, name);
		
		//check zip file
		if (!file_exists(zip_file)) {
			log_error(_("File not found") + ": '%s'".printf(zip_file));
			return false;
		}

		//delete existing target folder
		string dir = config.name.replace("~", base_dir_target);
		if (dir_exists(dir)) {
			cmd = "rm -rf \"%s\"".printf(dir);
			execute_command_sync(cmd);
		}

		//create base_dir_target
		create_dir(base_dir_target);

		if (name.contains("/")){
			string parent_dir = "%s/%s".printf(base_dir_target, name[0:name.last_index_of("/")]);
			create_dir(parent_dir);
			log_debug("create_dir: %s".printf(parent_dir));
		}

		//unzip selected items to home directory
		cmd = "tar xzvf '%s' -C '%s' '%s'".printf(zip_file, base_dir_target, name);
		status_line = "";

		if (gui_mode) {
			run_gzip(cmd);
		}
		else {
			stdout.printf("%-60s".printf(_("Extracting") + " '%s'".printf(config.name)));
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

	public bool reset_app_settings(Gee.ArrayList<AppConfig> config_list) {
		string cmd;
		string base_dir_target = user_home;

		//delete existing target folders
		foreach(AppConfig config in config_list) {
			if (config.is_selected) {
				string dir = config.name.replace("~", base_dir_target);
				if (dir_exists(dir)) {
					cmd = "rm -rf \"%s\"".printf(dir);
					execute_command_sync(cmd);
				}
			}
		}

		return true;
	}

	public void update_ownership(Gee.ArrayList<AppConfig> config_list) {
		//update ownership
		foreach(AppConfig config in config_list) {
			if (config.is_selected) {
				set_directory_ownership(config.name.replace("~", user_home), user_login);
			}
		}
	}

	private bool run_gzip (string cmd) {
		string[] argv = new string[1];
		argv[0] = save_bash_script_temp(cmd);

		try {
			//execute script file
			Process.spawn_async_with_pipes(
			    temp_dir, //working dir
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
				if (gui_mode) {
					progress_count += 1; //count
					status_line = out_line;
				}
				else {
					stdout.printf(out_line + "\n"); //print
				}
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

	/* Mounts */

	public bool backup_mounts(){
		bool ok = false;

		string mounts_dir = backup_dir + "mounts";
		ok = dir_create(mounts_dir);
		if (!ok){
			return false;
		}

		// get and check password -------------------
		
		prompt_for_password(true);
		if (arg_password.length == 0){
			log_error(Message.PASSWORD_MISSING);
			return false;
		}
				
		// copy /etc/fstab and /etc/crypttab to backup path ---------
		
		foreach(string file_name in new string[] { "fstab", "crypttab"}){
			string src_file = "/etc/%s".printf(file_name);
			string dst_file = "%s/%s.tar.gpg".printf(mounts_dir, file_name);

			if (file_exists(dst_file)){
				
				ok = file_delete(dst_file);
				
				if (!ok){
					log_error(Message.FILE_DELETE_ERROR + ": %s".printf(dst_file));
					return false;
				}
			}
			
			if (file_exists(src_file)){

				ok = file_tar_encrypt(src_file, dst_file, arg_password);

				if (!ok){
					log_error(Message.BACKUP_ERROR + ": %s".printf(src_file));
					return false;
				}
				else{
					log_msg(Message.BACKUP_SAVED + ": %s".printf(src_file));
				}
			}
		}

		// back-up key files mentioned in /etc/crypttab ---------
		
		var list = FsTabEntry.read_crypttab_file("/etc/crypttab", arg_password);
		foreach(var fs in list){
			if (fs.uses_keyfile() && file_exists(fs.password)){
				string src_file = fs.password;
				string dst_file = "%s/%s.tar.gpg".printf(mounts_dir, fs.keyfile_archive_name);
				
				ok = file_tar_encrypt(src_file, dst_file, arg_password);

				if (!ok){
					log_error(Message.BACKUP_ERROR + ": %s".printf(src_file));
					return false;
				}
				else{
					log_msg(Message.BACKUP_SAVED + ": %s".printf(src_file));
				}
			}
		}

		// back-up mount directories with permissions ---------

		// ** /etc/fstab only **
		
		list = FsTabEntry.read_fstab_file("/etc/fstab","");
		foreach(var fs in list){
			if (fs.mount_point == "/"){
				continue;
			}
			if (dir_exists(fs.mount_point)){
				// TAR the mount directory without including contents
				string tar_file = "%s/%s".printf(mounts_dir, fs.mount_dir_archive_name);
				
				ok = dir_tar(fs.mount_point, tar_file, false);
				
				if (!ok){
					log_error(Message.BACKUP_ERROR + ": %s".printf(fs.mount_point));
					return false;
				}
				else{
					//debug
					log_debug(Message.BACKUP_OK + ": %s".printf(fs.mount_point));
				}
			}
		}

		return true;
	}
	
	public bool restore_mounts(Gee.ArrayList<FsTabEntry> fstab_list, Gee.ArrayList<FsTabEntry> crypttab_list, string password){
		bool ok = false;

		string mounts_dir = backup_dir + "mounts";

		log_debug(_("Restoring /etc/fstab and /etc/crypttab entries"));

		// save /etc/fstab --------------------------
		
		bool none_selected = true;
		
		foreach(var fs in fstab_list) {
			if (fs.is_selected && (fs.action == FsTabEntry.Action.ADD)){
				none_selected = false;
				break;
			}
		}

		if (!none_selected){
			
			ok = FsTabEntry.save_fstab_file(fstab_list);
			
			if (!ok){
				log_error(Message.FILE_SAVE_ERROR + ": %s".printf("/etc/fstab"));
				return ok;
			}
			else{
				log_msg(Message.FILE_SAVE_OK + ": %s".printf("/etc/fstab"));
			}
		}
		else{
			log_msg(Message.NO_CHANGES_REQUIRED + ": %s".printf("/etc/fstab"));
		}

		// restore key files -----------------

		foreach(var fs in crypttab_list){
			if (!fs.is_selected || (fs.action != FsTabEntry.Action.ADD)){
				continue;
			}
			
			if (!fs.uses_keyfile()){
				continue;
			}

			if (file_exists(fs.password)){
				log_debug(Message.FILE_EXISTS + ": %s".printf(fs.password));
				continue;
			}
			
			string src_file = "%s/%s".printf(mounts_dir, fs.keyfile_archive_name);

			if (file_exists(src_file)){
				
				// get and check password -------------------
				
				prompt_for_password(false);
				if (arg_password.length == 0){
					log_error(Message.PASSWORD_MISSING);
					return false;
				}

				string dst_file = fs.password;

				ok = decrypt_and_untar(src_file, dst_file, arg_password);
				
				if (!ok){
					arg_password = ""; // forget password (may be incorrect)
					log_msg(Message.FILE_SAVE_ERROR + ": %s".printf(dst_file));
					return false;
				}
				else{
					log_msg(Message.FILE_SAVE_OK + ": %s".printf(dst_file));
				}
			}
		}

		// restore mount directories with permissions ---------

		// ** /etc/fstab only **
		
		foreach(var fs in fstab_list){
			if (!fs.is_selected || (fs.action != FsTabEntry.Action.ADD)){
				continue;
			}
			
			if (dir_exists(fs.mount_point)){
				log_msg(Message.DIR_EXISTS + ": %s".printf(fs.mount_point));
				continue;
			}
			
			// Un-TAR the mount directory from backup
			var tar_file = "%s/%s".printf(mounts_dir, fs.mount_dir_archive_name);
			var dst_dir = file_parent(fs.mount_point);
			if (file_exists(tar_file)){
				ok = dir_untar(tar_file, dst_dir);
				if (!ok){
					log_error(Message.DIR_CREATE_ERROR + ": %s".printf(fs.mount_point));
					return false;
				}
				else{
					log_msg(Message.DIR_CREATE_OK + ": %s".printf(fs.mount_point));
				}
			}
			else{
				log_error(Message.FILE_MISSING + ": %s".printf(tar_file));
			}
		}
		
		// save /etc/crypttab --------------------------
		
		none_selected = true;
		
		foreach(var fs in crypttab_list) {
			if (fs.is_selected && (fs.action == FsTabEntry.Action.ADD)){
				none_selected = false;
				break;
			}
		}

		if (!none_selected){
			
			ok = FsTabEntry.save_crypttab_file(crypttab_list);
			
			if (!ok){
				log_error(Message.FILE_SAVE_ERROR + ": %s".printf("/etc/crypttab"));
				return ok;
			}
			else{
				log_msg(Message.FILE_SAVE_OK + ": %s".printf("/etc/crypttab"));
			}
		}
		else{
			log_msg(Message.NO_CHANGES_REQUIRED + ": %s".printf("/etc/crypttab"));
		}
		
		return true;
	}

	public Gee.ArrayList<FsTabEntry> create_fstab_list_for_restore(){
		string mounts_dir = backup_dir + "mounts";
		string sys_file = "/etc/fstab";
		string backup_file = "%s/fstab.tar.gpg".printf(mounts_dir);

		var list = new Gee.ArrayList<FsTabEntry>();

		// read system file -----------
		
		var list_sys = FsTabEntry.read_fstab_file(sys_file, "");

		// read backup file -------------

		var list_bkup = FsTabEntry.read_fstab_file(backup_file, arg_password);

		// compare ----------------------
		
		foreach(var fs_sys in list_sys){
			list.add(fs_sys);
			fs_sys.is_selected = true;
		}
		
		foreach(var fs_bak in list_bkup){
			bool found = false;
			foreach(var fs_sys in list_sys){
				if (fs_sys.mount_point == fs_bak.mount_point){
					found = true;
					break;
				}
			}
			if (!found){
				// check if it needs to be added
				switch(fs_bak.mount_point){
				case "/":
				case "/boot":
				case "/boot/efi":
				//case "/home": // home will be added if missing in sys fstab
					// do not add
					break;
				default:
					// add
					list.add(fs_bak);
					fs_bak.action = FsTabEntry.Action.ADD;
					fs_bak.is_selected = true;
					if (!fs_bak.options.contains("nofail")){
						fs_bak.options += (fs_bak.options.length > 0) ? ",nofail" : "nofail";
					}
					break;
				}
			}
		}
		
		return list;
	}

	public Gee.ArrayList<FsTabEntry> create_crypttab_list_for_restore(){
		string mounts_dir = backup_dir + "mounts";
		string sys_file = "/etc/crypttab";
		string backup_file = "%s/crypttab.tar.gpg".printf(mounts_dir);

		var list = new Gee.ArrayList<FsTabEntry>();

		// read system file -----------
		
		var list_sys = FsTabEntry.read_crypttab_file(sys_file, "");

		// read backup file -------------
		
		var list_bkup = FsTabEntry.read_crypttab_file(backup_file, arg_password);

		// compare ----------------------
		
		foreach(var fs_sys in list_sys){
			list.add(fs_sys);
			fs_sys.is_selected = true;
		}
		
		foreach(var fs_bak in list_bkup){
			bool found = false;
			foreach(var fs_sys in list_sys){
				if (fs_sys.mapped_name == fs_bak.mapped_name){
					found = true;
					break;
				}
			}
			if (!found){
				// add
				list.add(fs_bak);
				fs_bak.action = FsTabEntry.Action.ADD;
				fs_bak.is_selected = true;
				if (!fs_bak.options.contains("nofail")){
					fs_bak.options += (fs_bak.options.length > 0) ? ",nofail" : "nofail";
				}
			}
		}

		return list;
	}

	/* Users and Groups */

	public bool backup_users_and_groups(string password){
		bool ok = false;

		string users_dir = backup_dir + "users";
		ok = dir_create(users_dir);
		if (!ok){
			return false;
		}

		// get and check password -------------------
		
		prompt_for_password(true);
		if (arg_password.length == 0){
			log_error(Message.PASSWORD_MISSING);
			return false;
		}

		// copy files to backup path ---------
		
		foreach(string file_name in new string[] { "passwd", "shadow", "group", "gshadow"}){
			string src_file = "/etc/%s".printf(file_name);
			string dst_file = "%s/%s.tar.gpg".printf(users_dir, file_name);

			if (file_exists(dst_file)){
				ok = file_delete(dst_file);
				if (!ok){
					log_error(Message.FILE_DELETE_ERROR + ": %s".printf(dst_file));
					return false;
				}
			}
			
			if (file_exists(src_file)){
			
				ok = file_tar_encrypt(src_file, dst_file, arg_password);

				if (!ok){
					log_error(Message.BACKUP_ERROR + ": %s".printf(src_file));
					return false;
				}
				else{
					log_msg(Message.BACKUP_SAVED + ": %s".printf(src_file));
				}
			}
		}

		return true;
	}

	public bool restore_users_and_groups_init(string password){
		string users_dir = App.backup_dir + "users";

		// get and check password -------------------
		
		prompt_for_password(false);
		if (arg_password.length == 0){
			log_error(Message.PASSWORD_MISSING);
			return false;
		}

		// query users and groups from system -------------------
		
		SystemUser.query_users();
		SystemGroup.query_groups();

		// read passwd and shadow files ---------------------
		
		var file_1 = "%s/%s.tar.gpg".printf(users_dir,"passwd");
		var file_2 = "%s/%s.tar.gpg".printf(users_dir,"shadow");

		user_list_bak = SystemUser.read_users_from_file(file_1, file_2, arg_password);

		if (user_list_bak.size > 0){
			log_debug(Message.FILE_READ_OK + ": %s".printf(file_1));
			log_debug(Message.FILE_READ_OK + ": %s".printf(file_2));
		}
		else{
			arg_password = ""; // forget password (may be incorrect)
			return false;
		}
		
		// read group and gshadow files ---------------------
		
		file_1 = "%s/%s.tar.gpg".printf(users_dir,"group");
		file_2 = "%s/%s.tar.gpg".printf(users_dir,"gshadow");

		group_list_bak = SystemGroup.read_groups_from_file(file_1, file_2, arg_password);

		if (group_list_bak.size > 0){
			log_debug(Message.FILE_READ_OK + ": %s".printf(file_1));
			log_debug(Message.FILE_READ_OK + ": %s".printf(file_2));
		}
		else{
			arg_password = ""; // forget password (may be incorrect)
			return false;
		}

		// select defaults ----------------------------------
		
		foreach(var user in user_list_bak.values){
			user.is_selected = !user.is_installed;
		}

		foreach(var group in group_list_bak.values){
			group.is_selected = !group.is_installed;
		}

		return true;
	}

	public bool restore_users_and_groups(){
		bool ok = true;

		//LOG_TIMESTAMP = false;
		
		// add users and primary groups ---------------------------
		
		foreach(var user in user_list_bak.values){
			if (SystemUser.all_users.has_key(user.name)){
				continue;
			}

			if (!user.is_selected || user.is_system){
				continue;
			}

			ok = (user.add() == 0);
			
			if (!ok){
				log_error(Message.USER_ADD_ERROR + ": %s".printf(user.name));
				return false;
			}
			else{
				log_msg(Message.USER_ADD_OK + ": %s".printf(user.name));
			}
		}

		// re-query users and groups from system
		SystemUser.query_users();
		SystemGroup.query_groups();

		// add groups ---------------------------

		foreach(var group in group_list_bak.values){

			if (SystemGroup.all_groups.has_key(group.name)){
				continue;
			}

			if (!group.is_selected || group.is_system){
				continue;
			}
			
			ok = (group.add() == 0);
			
			if (!ok){
				log_error(Message.GROUP_ADD_ERROR + ": %s".printf(group.name));
				return false;
			}
			else{
				log_msg(Message.GROUP_ADD_OK + ": %s".printf(group.name));
			}
		}

		// re-query groups from system
		SystemGroup.query_groups();

		// add users to groups --------------------------------------

		foreach(var group_bak in group_list_bak.values){
			// skip missing group
			if (!SystemGroup.all_groups.has_key(group_bak.name)){
				continue;
			}

			foreach(var user_name_bak in group_bak.users){
				SystemUser user_bak = null;
				if (user_list_bak.has_key(user_name_bak)){
					user_bak = user_list_bak[user_name_bak];
				}
				else{
					log_error("Backup group user missing in backup users list" + ": %s, %s".printf(group_bak.name, user_name_bak));
					return false;
				}
				
				// skip missing users
				if (!SystemUser.all_users.has_key(user_name_bak)){
					continue;
				}

				// skip if system group already contains user
				var sys_group = SystemGroup.all_groups[group_bak.name];
				if (sys_group.users.contains(user_name_bak)){
					continue;
				}
				
				// check if either user or group is selected
				if (!user_bak.is_selected && !group_bak.is_selected){
					continue;
				}
				
				// add user to group
				group_bak.add_to_group(user_name_bak);
				
				if (!ok){
					log_error(Message.GROUP_ADD_USER_ERROR + ": %s, %s".printf(user_name_bak, group_bak.name));
					return false;
				}
				else{
					log_msg(Message.GROUP_ADD_USER_OK + ": %s, %s".printf(user_name_bak, group_bak.name));
				}
			}
		}

		SystemUser.query_users();
		SystemGroup.query_groups();

		// restore user and group passwords and other settings ------

		foreach(var user in SystemUser.all_users.values){
			SystemUser? user_bak = null;
			if (user_list_bak.has_key(user.name)){
				user_bak = user_list_bak[user.name];
			}
			else{
				continue;
			}
			if (!user_bak.is_selected){
				continue;
			}

			user.password = user_bak.password;
			user.user_info = user_bak.user_info;
			user.home_path = user_bak.home_path;
			user.shell_path = user_bak.shell_path;
			
			user.update_passwd_file();

			user.pwd_hash = user_bak.pwd_hash;
			user.pwd_last_changed = user_bak.pwd_last_changed;
			user.pwd_age_min = user_bak.pwd_age_min;
			user.pwd_age_max = user_bak.pwd_age_max;
			user.pwd_warning_period = user_bak.pwd_warning_period;
			user.pwd_inactivity_period = user_bak.pwd_inactivity_period;
			user.pwd_expiraton_date = user_bak.pwd_expiraton_date;
			user.reserved_field = user_bak.reserved_field;
			
			user.update_shadow_file();
		}

		foreach(var group in SystemGroup.all_groups.values){
			SystemGroup? group_bak = null;
			if (group_list_bak.has_key(group.name)){
				group_bak = group_list_bak[group.name];
			}
			else{
				continue;
			}
			if (!group_bak.is_selected){
				continue;
			}

			group.password = group_bak.password;
			// keep name, gid, usernames
			group.update_group_file();

			group.password = group_bak.password;
			// keep name, admin, members
			group.update_gshadow_file();
		}

		// re-query users and groups from system
		SystemUser.query_users();
		SystemGroup.query_groups();

		return ok;
	}

	/* Home */

	public void init_user_list_home(){
		
		// query users ----------------
		
		SystemUser.query_users();

		// build list -----------------
		
		var list = new Gee.ArrayList<SystemUser>();
		foreach(var user in SystemUser.all_users.values){
			if (user.is_system){
				continue;
			}

			if ((user.home_path.length == 0) || !dir_exists(user.home_path)){
				continue;
			}

			user.is_selected = true;
			
			list.add(user);
		}
		
		//sort ------
		
		CompareDataFunc<SystemUser> func = (a, b) => {
			return strcmp(a.name, b.name);
		};
		list.sort((owned)func);
		
		user_list_home = list;
	}

	public void init_home_tree(){
		home_tree = new FileItem.dummy_root();

		foreach (var user in user_list_home) {
			home_tree.add_child_from_disk(user.home_path,1);
		}
	}
	
	public string backup_home_get_script(){
		string sh = "";
		
		foreach(var user in user_list_home){
			if (user.is_selected){
				var bak_dir = "%s%s/%s".printf(backup_dir, "home", user.name);
				var exclude_list = "%s/exclude.list".printf(bak_dir);
				create_dir(bak_dir);
				if (file_exists(exclude_list)){
					file_delete(exclude_list);
				}
				file_write(exclude_list, exclude_list_create());
				
				var cmd = "";
				
				cmd += "export PASSPHRASE='%s'\n".printf(App.arg_password);
				
				cmd += "duplicity%s --verbosity i --exclude-globbing-filelist '%s' '%s' 'file://%s'\n".printf(
				((dup_mode_full) ? " full" : ""), exclude_list, user.home_path, bak_dir);
				
				cmd += "unset PASSPHRASE\n";

				sh += "echo '%s'\n".printf(string.nfill(70,'-'));
				sh += "echo '%s'\n".printf(user.name);
				sh += "echo '%s'\n".printf(string.nfill(70,'-'));
				sh += "%s\n".printf(cmd);
				sh += "echo ''\n";
			}
		}

		return sh;
	}

	public string restore_home_get_script(){
		string sh = "";
		
		foreach(var user in user_list_home){
			if (user.is_selected){
				var bak_dir = "%s%s/%s".printf(backup_dir, "home", user.name);
				var exclude_list = "%s/exclude.list".printf(bak_dir);
				create_dir(bak_dir);
				if (file_exists(exclude_list)){
					file_delete(exclude_list);
				}
				file_write(exclude_list, exclude_list_create());

				var cmd = "";
				
				cmd += "export PASSPHRASE='%s'\n".printf(App.arg_password);
				
				cmd += "duplicity --verbosity i --force --exclude-globbing-filelist '%s' 'file://%s' '%s'\n".printf(exclude_list, bak_dir, user.home_path);
				
				cmd += "unset PASSPHRASE\n";

				log_debug(cmd);
				
				sh += "";
				sh += "echo '%s'\n".printf(string.nfill(70,'-'));
				sh += "echo '%s'\n".printf(user.name);
				sh += "echo '%s'\n".printf(string.nfill(70,'-'));
				sh += "%s\n".printf(cmd);
				sh += "echo ''\n";
			}
		}

		sh += "echo '%s'\n".printf(Message.BACKUP_OK);

		return sh;
	}

	public string exclude_list_create(){
		string txt = "";
		
		if (App.home_tree != null){
			foreach(var home in App.home_tree.children.values){
				exclude_list_append(home, ref txt, home.file_path);
			}
		}

		txt += "%s\n".printf("**/.*");
		return txt;
	}

	public void exclude_list_append(FileItem item, ref string txt, string base_dir){
		if (item.is_selected){
			//txt += "%s\n".printf(string_replace(item.file_path, base_dir, "**", 1));
			txt += "%s\n".printf(item.file_path);
		}
		foreach(var child in item.children.values){
			exclude_list_append(child, ref txt, base_dir);
		}
	}

	/* Misc */

	public void prompt_for_password (bool encrypt_mode){

		if (arg_password.length != 0){
			return;
		}

		string message = (encrypt_mode) ? Message.ENTER_PASSWORD_BACKUP : Message.ENTER_PASSWORD_RESTORE;
		stdout.printf(message + ":\n");
		
		string? line = stdin.read_line();
		line = (line != null) ? line.strip() : "";
		string password = line;

		if (password.length == 0){
			log_msg("%s\n".printf(Message.PASSWORD_EMPTY));
			prompt_for_password(encrypt_mode);
			return;
		}
		
		if (encrypt_mode){
			stdout.printf(_("Enter password again to confirm") + ":\n");
			
			line = stdin.read_line();
			line = (line != null) ? line.strip() : "";
			string password2 = line;
			if (password != password2){
				log_msg("%s\n".printf(Message.PASSWORD_NOT_MATCHING));
				prompt_for_password(encrypt_mode);
				return;
			}
			else{
				stdout.printf("\n");
			}
		}

		arg_password = line;
	}

	public bool run_cmd (string cmd) {
		string[] argv = new string[1];
		argv[0] = save_script(cmd);

		try {
			//execute script file
			Process.spawn_async_with_pipes(
			    temp_dir, //working dir
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

			//progress_count = 0;
			stdout_lines = new Gee.ArrayList<string>();
			stderr_lines = new Gee.ArrayList<string>();

			try {
				//start thread for reading output stream
				Thread.create<void> (aptik_read_output_line, true);
			} catch (Error e) {
				log_error (e.message);
			}

			try {
				//start thread for reading error stream
				Thread.create<void> (aptik_read_error_line, true);
			} catch (Error e) {
				log_error (e.message);
			}

			while (is_running){
				sleep(500);
			}

			return true;
		}
		catch (Error e) {
			log_error (e.message);
			return false;
		}
	}

	private void aptik_read_error_line() {
		try {
			err_line = dis_err.read_line (null);
			while (err_line != null) {
				stderr.printf(err_line);
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

	private void aptik_read_output_line() {
		try {
			out_line = dis_out.read_line (null);
			while (out_line != null) {
				stdout.printf(out_line);
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

	public bool take_ownership() {
		bool is_success = set_directory_ownership(user_home, user_login);
		if (is_success) {
			log_msg(_("Ownership changed to '%s' for files in directory '%s'").printf(user_login, user_home));
			return true;
		}
		else {
			log_msg(_("Failed to change file ownership"));
			return false;
		}
	}

	public void exit_app() {

		save_app_config();

		try {
			//delete temporary files
			var f = File.new_for_path(temp_dir);
			if (f.query_exists()) {
				f.delete();
			}
		}
		catch (Error e) {
			log_error (e.message);
		}
	}
}

public class BackupTask : GLib.Object {
	public string name = "";
	public string display_name = "";
	public bool is_started = false;
	public bool is_completed = false;
	public bool is_selected = true;
	private string _backup_cmd = "";
	private string _restore_cmd = "";

	private BackupTask(string name, string display_name){
		this.name = name;
		this.display_name = display_name;

		/*string cmd = "";
		cmd += string.nfill(70,'=') + "\n";
		cmd += "echo '%s'\n".printf(display_name);
		cmd += string.nfill(70,'=') + "\n";

		_backup_cmd = cmd;
		_restore_cmd = cmd;*/
	}

	public string backup_cmd {
		owned get{
			return _backup_cmd;
		}
		set{
			var cmd = "";
			//cmd += "echo '%s'\n".printf(string.nfill(70,'='));
			//cmd += "echo '%s'\n".printf(display_name);
			//cmd += "echo '%s'\n".printf(string.nfill(70,'='));
			//cmd += "%s\n".printf(value);
			//cmd += "echo\n";
			cmd = value;
			_backup_cmd = cmd;
		}
	}

	public string restore_cmd {
		owned get{
			return _restore_cmd;
		}
		set{
			var cmd = "";
			//cmd += "echo '%s'\n".printf(string.nfill(70,'='));
			//cmd += "echo '%s'\n".printf(display_name);
			//cmd += "echo '%s'\n".printf(string.nfill(70,'='));
			//cmd += "%s\n".printf(value);
			//cmd += "echo\n";
			cmd = value;
			_restore_cmd = cmd;
		}
	}
	
	public static Gee.ArrayList<BackupTask> create_list(){
		var list = new Gee.ArrayList<BackupTask>();
		
		var task = new BackupTask("ppa",_("Software Sources (PPAs)"));
		task.backup_cmd = "aptik --backup-dir '%s' --backup-ppa".printf(App.backup_dir);
		task.restore_cmd = "aptik --backup-dir '%s' --restore-ppas".printf(App.backup_dir);
		list.add(task);
		
		task = new BackupTask("cache",_("Downloaded Packages (APT Cache)"));
		task.backup_cmd = "aptik --backup-dir '%s' --backup-cache".printf(App.backup_dir);
		task.restore_cmd = "aptik --backup-dir '%s' --restore-cache".printf(App.backup_dir);
		list.add(task);
		
		task = new BackupTask("package",_("Software Selections (Installed Packages)"));
		task.backup_cmd = "aptik --backup-dir '%s' --backup-packages".printf(App.backup_dir);
		task.restore_cmd = "aptik --backup-dir '%s' --restore-packages".printf(App.backup_dir);
		list.add(task);

		// exit script on error
		task.restore_cmd += "\nstatus=$?; if [ $status -ne 0 ]; then echo '\n\n%s\n\n'; exit $status; fi\n".printf(Message.APT_GET_ERROR);

		task = new BackupTask("mount",_("Filesystem Mounts"));
		task.backup_cmd = "aptik --backup-dir '%s' --password '%s' --backup-mounts".printf(App.backup_dir, App.arg_password);
		task.restore_cmd = "aptik --backup-dir '%s' --password '%s' --restore-mounts".printf(App.backup_dir, App.arg_password);
		list.add(task);
		
		task = new BackupTask("theme",_("Themes and Icons"));
		task.backup_cmd = "aptik --backup-dir '%s' --backup-themes".printf(App.backup_dir);
		task.restore_cmd = "aptik --backup-dir '%s' --restore-themes".printf(App.backup_dir);
		list.add(task);
		
		task = new BackupTask("user",_("Users and groups"));
		task.backup_cmd = "aptik --backup-dir '%s' --password '%s' --backup-users".printf(App.backup_dir, App.arg_password);
		task.restore_cmd = "aptik --backup-dir '%s' --password '%s' --restore-users".printf(App.backup_dir, App.arg_password);
		list.add(task);

		task = new BackupTask("config",_("User Application Settings"));
		task.backup_cmd = "aptik --backup-dir '%s' --size-limit %lld --backup-configs".printf(App.backup_dir, App.arg_size_limit);
		task.restore_cmd = "aptik --backup-dir '%s' --restore-configs".printf(App.backup_dir);
		list.add(task);

		task = new BackupTask("home",_("User Data (Home directory)"));
		task.backup_cmd = "aptik --backup-dir '%s' --password '%s' --backup-home".printf(App.backup_dir, App.arg_password);
		task.restore_cmd = "aptik --backup-dir '%s' --password '%s' --restore-home".printf(App.backup_dir, App.arg_password);
		list.add(task);

		string[] arr = App.selected_tasks.strip().split(",");

		if (arr.length == 0){
			foreach(var item in list){
				item.is_selected = true;
			}
		}
		else{
			foreach(var item in list){
				item.is_selected = false;
				foreach(string selected_name in arr){
					if (item.name == selected_name){
						item.is_selected = true;
						break;
					}
				}
			}
		}
		
		return list;
	}
}

public class Message : GLib.Object {
	public static const string APT_GET_ERROR = _("Package installation has failed. Un-select the packages mentioned in the above error message and run the restore again.");
	
	public static const string BACKUP_OK = _("Backup completed");
	public static const string BACKUP_ERROR = _("Backup completed with errors");
	public static const string BACKUP_SAVED = _("Backup saved");
	
	public static const string RESTORE_OK = _("Restore completed");
	public static const string RESTORE_ERROR = _("Restore completed with errors");

	public static const string FILE_EXISTS = _("File exists");
	public static const string FILE_MISSING = _("File not found");
	
	public static const string FILE_SAVE_OK = _("File saved");
	public static const string FILE_SAVE_ERROR = _("Failed to save file");

	public static const string FILE_READ_OK = _("File read");
	public static const string FILE_READ_ERROR = _("Failed to read file");
	
	public static const string FILE_DECRYPT_OK = _("File decrypted");
	public static const string FILE_DECRYPT_ERROR = _("Failed to decrypt file");
	
	public static const string FILE_DELETE_OK = _("File deleted");
	public static const string FILE_DELETE_ERROR = _("Failed to delete file");
	
	public static const string DIR_CREATE_OK = _("Directory created");
	public static const string DIR_CREATE_ERROR = _("Failed to create directory");

	public static const string DIR_EXISTS = _("Directory exists");
	public static const string DIR_MISSING = _("Directory missing");

	public static const string USER_ADD_OK = _("User added");
	public static const string USER_ADD_ERROR = _("Failed to add user");

	public static const string GROUP_ADD_OK = _("Group added");
	public static const string GROUP_ADD_ERROR = _("Failed to add group");

	public static const string GROUP_ADD_USER_OK = _("User added to group");
	public static const string GROUP_ADD_USER_ERROR = _("Failed to add user to group");
	
	public static const string NO_CHANGES_REQUIRED = _("No changes required");
	public static const string PASSWORD_MISSING = _("Password not specified!");
	public static const string ENTER_PASSWORD_BACKUP = _("Enter password for encrypting backup");
	public static const string ENTER_PASSWORD_RESTORE = _("Enter password for decrypting backup");
	public static const string PASSWORD_EMPTY = _("Password cannot be empty!");
	public static const string PASSWORD_NOT_MATCHING = _("Passwords do not match!");
}
