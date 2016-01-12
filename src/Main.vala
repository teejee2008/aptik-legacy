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
	public string backup_dir = "";
	public string share_dir = "/usr/share";
	public string app_conf_path = "";

	public bool default_list_missing = false;

	public bool gui_mode = false;
	public string user_login = "";
	public string user_home = "";
	public int user_uid = -1;

	public string err_line;
	public string out_line;
	public string status_line;
	public string status_summary;
	public Gee.ArrayList<string> stdout_lines;
	public Gee.ArrayList<string> stderr_lines;
	public Pid proc_id;
	public DataInputStream dis_out;
	public DataInputStream dis_err;
	public long progress_count;
	public long progress_total;
	public bool is_running;

	//private Regex rex_aptget_download;

	public Gee.HashMap<string, Package> pkg_list_master;
	//public Gee.HashMap<string, Repository> repo_list_master;
	public Gee.HashMap<string, Ppa> ppa_list_master;
	public Gee.ArrayList<string> sections;
	
	public DateTime pkginfo_modified_date;

	public Main(string[] args, bool _gui_mode) {

		gui_mode = _gui_mode;

		pkginfo_modified_date = new DateTime.from_unix_utc(0); //1970
		
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
		user_login = get_user_login();
		user_home = "/home/" + user_login;
		user_uid = get_user_id(user_login);

		NATIVE_ARCH = execute_command_sync_get_output("dpkg --print-architecture").strip();
	}

	public bool check_dependencies(out string msg) {
		msg = "";

		string[] dependencies = { "rsync", "aptitude", "apt-get", "apt-cache", "gzip", "grep", "find", "chown", "rm" };

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

		if (gui_mode) {
			log_msg(_("App config loaded") + ": '%s'".printf(this.app_conf_path));
		}
	}

	/* Package selections */

	public void read_package_info(){	
		if (get_apt_list_modified_date().compare(pkginfo_modified_date) > 0){
			read_package_info_from_apt_list_files();
			read_package_info_for_installed_packages();
			read_package_info_for_default_packages();
			read_package_info_for_manual_packages();

			DateTime now = new DateTime.now_local();
			pkginfo_modified_date = now;
		}
	}
	
	//set section, arch, version_available, is_available
	private void read_package_info_from_apt_list_files(){
		//clear lists and start reading file
		pkg_list_master = new Gee.HashMap<string, Package>();
		//repo_list_master = new Gee.HashMap<string, Repository>();
		sections = new Gee.ArrayList<string>();
		
		try{
			//iterate files in /var/lib/apt/lists
			FileInfo info;
			File file = File.new_for_path(APT_LISTS_PATH);
			FileEnumerator enumerator = file.enumerate_children ("%s".printf(FileAttribute.STANDARD_NAME), 0);
			while ((info = enumerator.next_file()) != null) {
				string file_name = info.get_name();
				string list_file_path = "%s/%s".printf(APT_LISTS_PATH, file_name);
			
				if (!file_name.has_suffix("_Packages")){ continue; }

				//var repo = new Repository();
				var repo_name = file_name[0:file_name.index_of("_dists")];
				//repo_list_master[repo.name] = repo;

				string pkg_server = repo_name.replace("_","/");
		
				File f_list = File.new_for_path(list_file_path);
				
				string line;
				Package pkg = null;
				var dis = new DataInputStream (f_list.read());
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
								pkg_list_master[pkg.id] = pkg;
								pkg = null;
							}
							//create new pkg
							pkg = new Package(p_value);
							pkg.is_available = true;
							pkg.server = pkg_server;
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
					}
				}

				//add last pkg to list
				if (pkg != null){
					pkg.id = Package.get_id(pkg.name,pkg.arch);
					pkg_list_master[pkg.id] = pkg;
				}
			}

			//sort sections by name
			CompareDataFunc<string> func = (a, b) => {
				return strcmp(a, b);
			};
			sections.sort((owned)func);

			//export csv
			/*
			log_msg("\"%s\",\"%s\",\"%s\",\"%s\",\"%s\",\"%s\"".printf("id","name","arch","section","version_available","description"));
			foreach(var pkg in pkg_list_master.values){
				log_msg("\"%s\",\"%s\",\"%s\",\"%s\",\"%s\",\"%s\"".printf(pkg.id,pkg.name,pkg.arch,pkg.section,pkg.version_available,pkg.description));
			}
			*/
		}
		catch(Error e){
			log_error(e.message);
		}
	}

	//set version_installed, is_installed, is_automatic
	private void read_package_info_for_installed_packages() {
		log_debug("call: update_info_for_available_packages");

		string txt = execute_command_sync_get_output("aptitude search --disable-columns -F '%p|%v|%M' '?installed'");
		write_file(PKG_CACHE_TEMP, txt);

		// TODO: Create an optimized method for writing output to file

		//read command output from temp file line by line

		try {
			string line;
			var file = File.new_for_path (PKG_CACHE_TEMP);
			if (file.query_exists ()) {
				var dis = new DataInputStream (file.read());
				while ((line = dis.read_line (null)) != null) {
					string[] arr = line.split("|");
					if (arr.length != 3) {
						continue;
					}

					string name = arr[0].strip();
					string arch = (name.contains(":")) ? name.split(":")[1].strip() : "";
					if (name.contains(":")) { name = name.split(":")[0]; }
					string version = arr[1].strip();
					string auto = arr[2].strip();

					string id = Package.get_id(name,arch);

					Package pkg = null;
					if (pkg_list_master.has_key(id)) {
						pkg = pkg_list_master[id];
					}
					else{
						//installed from DEB file, add to master
						pkg = new Package(name);
						pkg.is_available = true;
						pkg.is_deb = true;
						pkg.arch = arch;
						pkg_list_master[id] = pkg;
					}

					if (pkg != null){
						pkg.is_installed = true;
						pkg.is_automatic = (auto == "A");
						pkg.version_installed = version;
					}
				}
			}
			else {
				log_error ("File not found: %s".printf(PKG_CACHE_TEMP));
			}
		}
		catch (Error e) {
			log_error (e.message);
		}

		//export csv
		
		/*log_msg("\"%s\",\"%s\",\"%s\",\"%s\",\"%s\",\"%s\",\"%s\",\"%s\"".printf("id","name","arch","section","ver_available","ver_installed","description","installed?"));
		foreach(var pkg in pkg_list_master.values){
			log_msg("\"%s\",\"%s\",\"%s\",\"%s\",\"%s\",\"%s\",\"%s\",\"%s\"".printf(pkg.id,pkg.name,pkg.arch,pkg.section,pkg.version_available,pkg.version_installed,pkg.description.replace("\"","\"\""), (pkg.is_installed)?"Y":"N"));
		}*/
		
	}

	//sets: is_default
	private void read_package_info_for_default_packages() {
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
				log_error("Failed to unzip: '%s'".printf(DEF_PKG_LIST_UNPACKED));
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

	//sets: is_manual
	private void read_package_info_for_manual_packages() {
		log_debug("call: update_info_for_manual_packages");

		foreach(Package pkg in pkg_list_master.values) {
			if (pkg.is_installed && !pkg.is_default && !pkg.is_automatic) {
				pkg.is_manual = true;
			}
		}
	}


	//deprecated
	public void update_info_for_repository_alternate() {
		log_debug("call: update_info_for_repository");

		var cmd =
		    """apt-cache policy $(dpkg -l | awk 'NR >= 6 { print $2 }') |
    awk '/^[^ ]/    { split($1, a, ": "); pkg = a[1] }
		    nextline == 1 { nextline = 0; printf("
		    % -40s % -50s % s\n", pkg, $2, $3) }
		    /\*\*\*/      { nextline = 1 }'
		    """;

		string txtout, txterr;
		int exit_code = execute_command_script_sync(cmd, out txtout, out txterr);

		if (exit_code == 0) {
			string pkg_name;
			string pkg_server;
			string pkg_repo;
			string pkg_repo_section;

			Regex rex_pkg_installed = null;
			MatchInfo match;

			try {
				rex_pkg_installed = new Regex("""([^ \t]*)[ \t]*([^ \t]*)[ \t]*([^ \t]*)[ \t]*""");
			}
			catch (Error e) {
				log_error (e.message);
			}

			foreach(string line in txtout.split("\n")) {
				if (line.strip().length == 0) {
					continue;
				}

				if (rex_pkg_installed.match (line, 0, out match)) {
					pkg_name = match.fetch(1).strip();
					pkg_server = match.fetch(2).strip();
					pkg_repo = "";
					pkg_repo_section = match.fetch(3).strip();

					if (pkg_list_master.has_key(pkg_name)) {
						pkg_list_master[pkg_name].server = pkg_server;
						pkg_list_master[pkg_name].repo = pkg_repo;
						pkg_list_master[pkg_name].repo_section = pkg_repo_section;
					}
				}
			}
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
				text += "%s\n".printf(pkg.name);
			}
		}

		bool is_success = write_file(list_file, text);

		if (is_success) {
			log_msg(_("File saved") + " '%s'".printf(PKG_LIST_BAK));
		}
		else {
			log_error(_("Failed to write")  + " '%s'".printf(PKG_LIST_BAK));
		}

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
				text += "%s\n".printf(pkg.name);
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

	public Gee.ArrayList<string> read_package_list() {
		string pkg_list_file = backup_dir + (backup_dir.has_suffix("/") ? "" : "/") + PKG_LIST_BAK;
		var pkg_list = new Gee.ArrayList<string>();

		//check file
		if (!check_backup_file(PKG_LIST_BAK)) {
			return pkg_list;
		}

		//read package names
		foreach(string line in read_file(pkg_list_file).split("\n")) {
			if (line.strip() == "") {
				continue;
			}
			if (!line.strip().has_prefix("#")) {
				pkg_list.add(line.strip());
			}
			// TODO: Read from script file
		}

		return pkg_list;
	}

	public void download_packages() {
		log_debug("call: update_info_for_available_packages");

		log_debug("create: %s".printf(DEB_LIST_TEMP));

		string txt = execute_command_sync_get_output("apt-get install --reinstall --print-uris -qq chromium-browser firefox | cut -d\' -f2");

		write_file(DEB_LIST_TEMP, txt);

		// TODO: Create an optimized method for writing output to file

		log_debug("read: %s".printf(DEB_LIST_TEMP));

		string line;

		try {
			var file = File.new_for_path (DEB_LIST_TEMP);
			if (file.query_exists ()) {
				var dis = new DataInputStream (file.read());

				//var pkg_list = new Gee.HashMap<string, Package>();
				while ((line = dis.read_line (null)) != null) {

				}
			}
			else {
				log_error ("File not found: %s".printf(DEB_LIST_TEMP));
			}
		}
		catch (Error e) {
			log_error (e.message);
		}
	}

	/* PPA */

	public Gee.HashMap<string,Ppa> list_ppa(){
		ppa_list_master = list_ppas_from_etc_apt_dir();

		//update ppa description (list of installed packages)
		/*foreach(Ppa ppa in ppa_list.values){
			foreach (Package pkg in pkg_list_master.values) {
				if (pkg.is_installed){
					if (pkg.server.contains(ppa.name)){
						ppa.description += " %s".printf(pkg.name);
					}
				}
			}
			ppa.description = ppa.description.strip();
		}*/

		update_info_for_repository();

		return ppa_list_master;
	}
	
	public Gee.HashMap<string,Ppa> list_ppas_from_etc_apt_dir(){
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
	//'apt-cache policy .' only returns info for 
	public void update_info_for_repository() {
		log_debug("call: update_info_for_repository");

		string cmd = "";
		foreach(Package pkg in pkg_list_master.values){
			if (pkg.is_installed){
				cmd += " %s".printf(pkg.id);
			}
		}
		cmd = "apt-cache policy %s".printf(cmd);
		
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

			regex_pkg = new Regex("""^([^ \t]*):$""");
			regex_source = new Regex("""[ \t]*[0-9]+[ \t]*([^ \t]*ubuntu.com[^ \t])[ \t]*([^ \t]*)[ \t]*([^ \t]*)""");
			regex_launchpad = new Regex("""[ \t]*[0-9]+[ \t]*([https:/]+ppa.launchpad.net/([^ \t]*)/ubuntu/)[ \t]*([^ \t]*)[ \t]*([^ \t]*)""");
		}
		catch (Error e) {
			log_error (e.message);
		}

		try {
			int count_pkg = 0;
			int line_number = 0;
			var file = File.new_for_path (PKG_CACHE_TEMP);
			if (!file.query_exists()) {
				log_error ("File not found: %s".printf(PKG_CACHE_TEMP));
				return;
			}

			var dis = new DataInputStream (file.read());

			while ((line = dis.read_line (null)) != null) {
				if (line.strip().length == 0) {
					continue;
				}
				line_number++;

				if (regex_pkg.match (line, 0, out match)) {
					pkg_name = match.fetch(1).strip();
					line_number = 1;
					count_pkg++;
				}
				else {
					switch (line_number) {
					case 2:
					case 3:
					case 4:
					case 5:
						//ignore
						break;
					case 6:
						if (regex_launchpad.match (line, 0, out match)) {
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
						break;
					}
				}
			}
		}
		catch (Error e) {
			log_error (e.message);
		}
	}

	/*
		public Gee.HashMap<string,Ppa> list_ppa(){
			var ppa_list = list_ppas_from_etc_apt_dir();
			var pkg_list_installed = list_installed(true);

			//update ppa description (list of installed packages)
			foreach(Ppa ppa in ppa_list.values){
				foreach (Package pkg in pkg_list_installed.values) {
					if (pkg.server.contains(ppa.name)){
						ppa.description += " %s".printf(pkg.name);
					}
				}
				ppa.description = ppa.description.strip();
			}

			return ppa_list;
		}
	*/

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

		if (is_success) {
			log_msg(_("File saved") + " '%s'".printf(file_name));
		}
		else {
			log_error(_("Failed to write")  + " '%s'".printf(file_name));
		}

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

	public bool run_apt_update () {
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
			progress_total = 0;
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

	private void apt_read_error_line() {
		try {
			err_line = dis_err.read_line (null);
			while (err_line != null) {
				log_msg(err_line);
				err_line = dis_err.read_line (null); //read next
			}
		}
		catch (Error e) {
			log_error (e.message);
		}
	}

	private void apt_read_output_line() {
		try {
			out_line = dis_out.read_line (null);
			while (out_line != null) {
				out_line = dis_out.read_line (null);  //read next
			}

			is_running = false;
		}
		catch (Error e) {
			log_error (e.message);
		}
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

	private void rysnc_read_error_line() {
		try {
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

			is_running = false;
		}
		catch (Error e) {
			log_error (e.message);
		}
	}

	/* Themes */

	public Gee.ArrayList<Theme> list_all_themes() {
		var theme_list = list_themes();
		foreach(Theme theme in list_icons()) {
			theme_list.add(theme);
		}
		return theme_list;
	}

	public Gee.ArrayList<Theme> list_themes() {
		var theme_list = new Gee.ArrayList<Theme>();

		try {
			string theme_type = "theme";
			string share_path = "/usr/share/%ss".printf(theme_type);
			var directory = File.new_for_path(share_path);
			var enumerator = directory.enumerate_children("standard::*", 0);
			FileInfo info;

			while ((info = enumerator.next_file()) != null) {
				if (info.get_file_type() == FileType.DIRECTORY) {
					string theme_name = info.get_name();
					switch (theme_name.down()) {
					case "default":
					case "emacs":
					case "highcontrast":
						continue;
					}

					Theme theme = new Theme(theme_name, theme_type);
					theme.is_selected = true;
					theme.is_installed = true;
					theme_list.add(theme);
				}
			}
		}
		catch (Error e) {
			log_error (e.message);
		}

		return theme_list;
	}

	public Gee.ArrayList<Theme> list_icons() {
		var theme_list = new Gee.ArrayList<Theme>();

		try {
			string theme_type = "icon";
			string share_path = "/usr/share/%ss".printf(theme_type);
			var directory = File.new_for_path(share_path);
			var enumerator = directory.enumerate_children("standard::*", 0);
			FileInfo info;

			while ((info = enumerator.next_file()) != null) {
				if (info.get_file_type() == FileType.DIRECTORY) {
					string theme_name = info.get_name();
					switch (theme_name.down()) {
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

					Theme theme = new Theme(theme_name, theme_type);
					theme.is_selected = true;
					theme.is_installed = true;
					theme_list.add(theme);
				}
			}
		}
		catch (Error e) {
			log_error (e.message);
		}

		return theme_list;
	}

	public Gee.ArrayList<Theme> get_all_themes_from_backup() {
		var themes_list = new Gee.ArrayList<Theme>();

		foreach(Theme theme in get_themes_from_backup("theme")) {
			themes_list.add(theme);
		}

		foreach(Theme theme in get_themes_from_backup("icon")) {
			themes_list.add(theme);
		}

		return themes_list;
	}

	public Gee.ArrayList<Theme> get_themes_from_backup(string theme_type) {
		var themes_list = new Gee.ArrayList<Theme>();
		var themes_installed = list_all_themes();

		string themes_dir = backup_dir + "%ss".printf(theme_type);

		//check directory
		var f = File.new_for_path(themes_dir);
		if (!f.query_exists()) {
			log_error(_("Themes not found in backup directory"));
			return themes_list;
		}//TODO:use func

		try {
			var directory = File.new_for_path(themes_dir);
			var enumerator = directory.enumerate_children("standard::*", 0);
			FileInfo info;

			while ((info = enumerator.next_file()) != null) {
				if (info.get_file_type() == FileType.REGULAR) {
					string zip_file_path = "%s/%s".printf(themes_dir, info.get_name());
					string theme_name = info.get_name().replace(".tar.gz", "");

					Theme theme = new Theme(theme_name, theme_type);
					theme.zip_file_path = zip_file_path;
					theme.is_selected = true;
					foreach (Theme th in themes_installed) {
						if ((th.name == theme_name) && (th.type == theme_type)) {
							theme.is_installed = true;
							break;
						}
					}
					themes_list.add(theme);
				}
			}
		}
		catch (Error e) {
			log_error (e.message);
		}

		return themes_list;
	}


	public bool zip_theme(Theme theme) {
		string theme_dir = backup_dir + "%ss".printf(theme.type);
		string theme_dir_system = "/usr/share/%ss".printf(theme.type);
		string file_name = theme.name + ".tar.gz";
		string zip_file = theme_dir + "/" + file_name;

		try {
			//create theme directory
			var f = File.new_for_path(theme_dir);
			if (!f.query_exists()) {
				f.make_directory_with_parents();
			}

			string cmd = "tar czvf '%s' -C '%s' '%s'".printf(zip_file, theme_dir_system, theme.name);
			status_line = theme.system_path;

			if (gui_mode) {
				run_gzip(cmd);
			}
			else {
				stdout.printf("%-60s".printf(_("Archiving") + " '%s'".printf(theme.system_path)));
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

	public bool unzip_theme(Theme theme) {
		string theme_dir_system = "/usr/share/%ss".printf(theme.type);

		//check file
		if (!file_exists(theme.zip_file_path)) {
			log_error(_("File not found") + ": '%s'".printf(theme.zip_file_path));
			return false;
		}

		string cmd = "tar -xzvf '%s' --directory='%s'".printf(theme.zip_file_path, theme_dir_system);
		status_line = theme.zip_file_path;

		if (gui_mode) {
			return run_gzip(cmd);
		}
		else {
			stdout.printf("%-60s".printf(_("Extracting") + " '%s'".printf(theme.system_path)));
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

	public bool update_permissions(string path) {
		try {
			int exit_code;
			string cmd;

			cmd = "find '%s' -type d -exec chmod 755 '{}' ';'".printf(path);
			Process.spawn_command_line_sync(cmd, null, null, out exit_code);
			if (exit_code != 0) {
				return false;
			}

			cmd = "find '%s' -type f -exec chmod 644 '{}' ';'".printf(path);
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

	private bool run_gzip (string cmd) {
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

			//progress_count = 0;
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

			//while(is_running){
			//	sleep(100);
			//}

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

			is_running = false;
		}
		catch (Error e) {
			log_error (e.message);
		}
	}

	/* App Settings */

	public bool backup_app_settings_all(Gee.ArrayList<AppConfig> config_list) {
		backup_app_settings_init(config_list);

		foreach(AppConfig config in config_list) {
			if (config.is_selected) { 
				backup_app_settings_single(config);
			}
		}

		return true;
	}

	public void backup_app_settings_init(Gee.ArrayList<AppConfig> config_list){
		//get total file count
		progress_total = 0;
		progress_count = 0;
		foreach(AppConfig config in config_list) {
			if (config.is_selected) {
				progress_total += (int) get_file_count(config.path);
			}
		}
	}
	
	public bool backup_app_settings_single(AppConfig config) {
		string cmd;

		string backup_dir_config = "%sconfigs".printf(backup_dir);
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
				//return (status == 0);
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
		
		try
		{
			//list all items in home except .config and .local
			File f_home = File.new_for_path (base_path);
			FileEnumerator enumerator = f_home.enumerate_children ("standard::*", 0);
			FileInfo file;
			while ((file = enumerator.next_file ()) != null) {
				string name = file.get_name();
				string item = base_path + "/" + name;
				if (!name.has_prefix(".")) {
					continue;
				}
				if (name == ".config") {
					continue;
				}
				if (name == ".local") {
					continue;
				}
				if (name == ".gvfs") {
					continue;
				}
				if (name.has_suffix(".lock")) {
					continue;
				}

				AppConfig entry = new AppConfig("~/%s".printf(name));
				entry.size = get_file_size_formatted(item);
				entry.description = get_config_dir_description(entry.name);
				app_config_list.add(entry);

				switch (name) {
				case ".cache":
					entry.is_selected = false;
					break;
				}
			}

			//list all items in .config
			File f_home_config = File.new_for_path (base_path + "/.config");
			enumerator = f_home_config.enumerate_children ("standard::*", 0);
			while ((file = enumerator.next_file ()) != null) {
				string name = file.get_name();
				string item = base_path + "/.config/" + name;
				if (name.has_suffix(".lock")) {
					continue;
				}

				AppConfig entry = new AppConfig("~/.config/%s".printf(name));
				entry.size = get_file_size_formatted(item);
				entry.description = get_config_dir_description(entry.name);
				app_config_list.add(entry);
			}

			//list all items in .local/share
			var f_home_local = File.new_for_path (base_path + "/.local/share");
			enumerator = f_home_local.enumerate_children ("standard::*", 0);
			while ((file = enumerator.next_file ()) != null) {
				string name = file.get_name();
				string item = base_path + "/.local/share/" + name;
				if (name.has_suffix(".lock")) {
					continue;
				}

				AppConfig entry = new AppConfig("~/.local/share/%s".printf(name));
				entry.size = get_file_size_formatted(item);
				entry.description = get_config_dir_description(entry.name);
				app_config_list.add(entry);
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
		string backup_dir_config = "%sconfigs".printf(backup_dir);
		
		list_app_config_directories_from_backup_path(backup_dir_config, ref app_config_list);
		
		//sort the list
		CompareDataFunc<AppConfig> entry_compare = (a, b) => {
			return strcmp(a.path, b.path);
		};
		app_config_list.sort((owned)entry_compare);

		return app_config_list;
	}

	public void list_app_config_directories_from_backup_path(
	string backup_path, ref Gee.ArrayList<AppConfig> app_config_list) {

		string backup_dir_config = "%sconfigs".printf(backup_dir);

		try{
			File f_bak = File.new_for_path (backup_path);
			FileEnumerator enumerator = f_bak.enumerate_children ("standard::*", 0);
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
		restore_app_settings_init(config_list);
		
		foreach(AppConfig config in config_list) {
			if (config.is_selected) {
				restore_app_settings_single(config);
			}
		}

		return true;
	}

	public void restore_app_settings_init(Gee.ArrayList<AppConfig> config_list) {
		//get file count before unzipping
		progress_total = 0;
		progress_count = 0;
		foreach(AppConfig config in config_list) {
			if (config.is_selected) {
				string name = config.name.replace("~/", "");
				string backup_dir_config = "%sconfigs".printf(backup_dir);
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

		string backup_dir_config = "%sconfigs".printf(backup_dir);
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
		cmd = "tar xzvf '%s' -C '%s' %s".printf(zip_file, base_dir_target, name);
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

	/* Misc */

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

