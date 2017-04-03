using TeeJee.Logging;
using TeeJee.FileSystem;
using TeeJee.JSON;
using TeeJee.ProcessManagement;
using TeeJee.GtkHelper;
using TeeJee.System;
using TeeJee.Misc;

public class AppExcludeEntry : GLib.Object{
	public string name = "";
	public bool is_include = false;
	public bool is_file = false;
	public bool enabled = false;
	public int64 size = 0;
	public int64 count = 0;
	public Gee.ArrayList<string> items;
	public Gee.ArrayList<string> patterns;

	//static
	public static Gee.HashMap<string, AppExcludeEntry> app_map;

	public AppExcludeEntry(string _name, bool _is_include = false){
		name = _name;
		is_include = _is_include;

		items = new Gee.ArrayList<string>();
		patterns = new Gee.ArrayList<string>();
	}

	public string tooltip_text(){
		string txt = "";
		foreach(var item in items){
			txt += "%s\n".printf(item);
		}
		if (txt.has_suffix("\n")){
			txt = txt[0:txt.length - 1];
		}
		return txt;
	}	

	public string description {
		owned get {
			switch (name) {
			case "mozilla":
				return _("Firefox Web Browser");
			case "opera":
				return _("Opera Web Browser");
			case "fonts":
				return _("Local Fonts");
			case "themes":
				return _("Local Themes");
			case ".bash_history":
				return _("Bash Command History");
			case ".bashrc":
				return _("Bash Init Script");
			case ".bash_logout":
				return _("Bash Logout Script");
			case "chromium":
				return _("Chromium Web Browser");
			case "autostart":
				return _("Startup Entries");
			default:
				return "";
			}
		}
	}

	// static
	
	public static void clear(){

		log_debug("AppExcludeEntry: clear()");
		
		if (app_map == null){
			app_map = new Gee.HashMap<string, AppExcludeEntry>();
		}
		else{
			app_map.clear();
		}
	}

	public static void add_app_exclude_entries_from_home(string home){

		log_debug("AppExcludeEntry: add_app_exclude_entries_from_home(): %s".printf(home));

		try
		{
			File f_home = File.new_for_path (home);
			if (!f_home.query_exists()){
				return;
			}
			
	        FileEnumerator enumerator = f_home.enumerate_children ("standard::*", 0);
	        FileInfo file;
	        while ((file = enumerator.next_file ()) != null) {
				string name = file.get_name();
				string item = home + "/" + name;
				if (name.has_suffix(".lock")){ continue; }
				if (name.has_suffix(".log")){ continue; }
				if (name.has_suffix(".old")){ continue; }
				if (name.has_suffix("~")){ continue; }
				if (name == ".Xauthority"){ continue; }
				
				add_app_exclude_entries_from_path(item);
	        }
        }
        catch(Error e){
	        log_error (e.message);
	    }
	}
	
	public static void add_app_exclude_entries_from_path(string user_home){

		log_debug("AppExcludeEntry: add_app_exclude_entries_from_path(): %s".printf(user_home));

		try
		{
			File f_home = File.new_for_path (user_home);
			if (!f_home.query_exists()){
				return;
			}
			
	        FileEnumerator enumerator = f_home.enumerate_children ("standard::*", 0);
	        FileInfo file;
	        while ((file = enumerator.next_file ()) != null) {
				string name = file.get_name();
				string item = user_home + "/" + name;
				if (!name.has_prefix(".")){ continue; }
				if (name.has_suffix("~")){ continue; }
				if (name == ".config"){ continue; }
				if (name == ".local"){ continue; }
				if (name == ".gvfs"){ continue; }
				if (name == ".thumbnails"){ continue; }
				if (name == ".cache"){ continue; }
				if (name == ".temp"){ continue; }
				if (name == ".sudo_as_admin_successful"){ continue; }
				if (name.has_suffix(".lock")){ continue; }
				if (name.has_suffix(".log")){ continue; }
				if (name.has_suffix(".old")){ continue; }
				if (name.has_suffix("~")){ continue; }
				if (name == ".Xauthority"){ continue; }
				
				var relpath = "~/%s".printf(name);
				add_item(item, relpath, !dir_exists(item), false);
	        }

	        File f_home_config = File.new_for_path (user_home + "/.config");
	        if (f_home_config.query_exists()){
				enumerator = f_home_config.enumerate_children ("standard::*", 0);
				while ((file = enumerator.next_file ()) != null) {
					string name = file.get_name();
					string item = user_home + "/.config/" + name;
					if (name.has_suffix(".lock")){ continue; }
					if (name.has_suffix(".log")){ continue; }
					if (name.has_suffix(".old")){ continue; }
					if (name.has_suffix("~")){ continue; }
					if (name == ".Xauthority"){ continue; }
					
					var relpath = "~/.config/%s".printf(name);
					add_item(item, relpath, !dir_exists(item), false);
				}
			}

	        File f_home_local = File.new_for_path (user_home + "/.local/share");
	        if (f_home_local.query_exists()){
				enumerator = f_home_local.enumerate_children ("standard::*", 0);
				while ((file = enumerator.next_file ()) != null) {
					string name = file.get_name();
					string item = user_home + "/.local/share/" + name;
					if (name.has_suffix(".lock")){ continue; }
					if (name.has_suffix(".log")){ continue; }
					if (name.has_suffix(".old")){ continue; }
					if (name.has_suffix("~")){ continue; }
					if (name == "applications"){ continue; }
					if (name == "Trash"){ continue; }
					if (name == ".Xauthority"){ continue; }
					
					var relpath = "~/.local/share/%s".printf(name);
					add_item(item, relpath, !dir_exists(item), false);
				}
			}
        }
        catch(Error e){
	        log_error (e.message);
	    }
	}

	public static void add_item(string disk_path, string item_path, bool is_file, bool is_include){

		if (app_map == null){
			app_map = new Gee.HashMap<string, AppExcludeEntry>();
		}

		var name = file_basename(item_path);
		
		if (name.has_suffix(".ini")){
			name = name[0:name.length - ".ini".length];
		}
		else if (name.has_suffix(".sh")){
			name = name[0:name.length - ".sh".length];
		}
		else if (name.has_suffix(".json")){
			name = name[0:name.length - ".json".length];
		}
		else if (name.has_suffix(".conf")){
			name = name[0:name.length - ".conf".length];
		}
		else if (name.has_suffix(".list")){
			name = name[0:name.length - ".list".length];
		}
		else if (name.has_suffix(".xbel")){
			name = name[0:name.length - ".xbel".length];
		}
		else if (name.has_suffix(".xbel.tbcache")){
			name = name[0:name.length - ".xbel.tbcache".length];
		}
		else if (name.has_suffix(".bz2")){
			name = name[0:name.length - ".bz2".length];
		}
		else if (name.has_suffix(".old")){
			name = name[0:name.length - ".old".length];
		}
		else if (name.has_suffix(".dirs")){
			name = name[0:name.length - ".dirs".length];
		}
		else if (name.has_suffix(".locale")){
			name = name[0:name.length - ".locale".length];
		}
		else if (name.has_suffix(".dockitem")){
			name = name[0:name.length - ".dockitem".length];
		}
		else if (name.has_suffix(".xml")){
			name = name[0:name.length - ".xml".length];
		}
		else if (name.has_suffix(".log")){
			name = name[0:name.length - ".log".length];
		}
		else if (name.has_suffix(".txt")){
			name = name[0:name.length - ".txt".length];
		}

		if (name.has_prefix(".")){
			name = name[1:name.length];
		}

		name = name.strip();

		if (name.length == 0){
			return;
		}

		var bytes = dir_size(disk_path);
		var file_count = dir_count(disk_path);

		if (file_count == 0){
			
			return; // skip empty directories
		}
		log_debug("count=%lld, %s".printf(file_count, disk_path));
		
		AppExcludeEntry entry = null;
		if (app_map.has_key(name)){
			entry = app_map[name];
		}
		else if (app_map.has_key(name.down())){
			entry = app_map[name.down()];
		}
		else{
			entry = new AppExcludeEntry(name, is_include);
			app_map[name] = entry;
		}

		if (!entry.items.contains(item_path)){
			entry.items.add(item_path);
		}

		// append size and count if existing
		entry.size += (int64) bytes;
		entry.count += (int64) file_count;

		foreach(bool root_user in new bool[] { true, false } ){
			string str = (is_include) ? "+ " : "";
			str += (root_user) ? "/root" : "/home/*";
			str += item_path[1:item_path.length];
			//str += (is_file) ? "" : "/**";
			entry.patterns.add(str);
		}
	}

	public static void add_item_from_archive(string archive_path){

		string backup_path = file_parent(archive_path);
		string name = file_basename(archive_path);
		
		if (!name.has_suffix(".tgz")){ return; }

		name = name[0:name.length - 4];  // remove .tgz

		//string zip_file = path_combine(backup_path, name + ".tgz");
		string list_file = path_combine(backup_path, name + ".info");
		
		if (!file_exists(list_file)){ return; }

		if (name == "Xauthority"){ return; } // skip this file

		AppExcludeEntry entry = null;
		if (app_map.has_key(name)){
			entry = app_map[name];
		}
		else if (app_map.has_key(name.down())){
			entry = app_map[name.down()];
		}
		else{
			entry = new AppExcludeEntry(name, true);
			app_map[name] = entry;
		}

		foreach(string line in file_read(list_file).split("\n")){

			if (line.length == 0){ continue; }
			
			if (line.has_prefix("size=")){
				entry.size += int64.parse(line.split("size=")[1]);
			}
			else if (line.has_prefix("count=")){
				entry.count += int64.parse(line.split("count=")[1]);
			}
			else{
				if (!entry.items.contains(line)){
					entry.items.add(line);
				}
			}
		}
	}

	public static Gee.ArrayList<AppExcludeEntry> get_apps_list(){

		if (app_map == null){
			app_map = new Gee.HashMap<string, AppExcludeEntry>();
		}

		/*
		 * foreach(var selected_name in selected_app_names){
			if (app_map.has_key(selected_name)){
				app_map[selected_name].enabled = true;
			}
			else{
				app_map[selected_name].enabled = false;
			}
		}
		* */
	
		var list = new Gee.ArrayList<AppExcludeEntry>();
		foreach(var key in app_map.keys){
			list.add(app_map[key]);
		}

		//sort the list
		GLib.CompareDataFunc<AppExcludeEntry> entry_compare = (a, b) => {
			return strcmp(a.name.down(),b.name.down());
		};
		
		list.sort((owned) entry_compare);

		log_debug("apps: %d".printf(list.size));
		
		return list;
	}
}

public class AppSelection : GLib.Object {
	
	public string user = "";
	public string name = "";
	public bool selected = true;

	public static Gee.ArrayList<AppSelection> selections = new Gee.ArrayList<AppSelection>();

	public static AppSelection add_item(string _user, string _name, bool _selected){
		var entry = new AppSelection();
		entry.user = _user;
		entry.selected = _selected;
		entry.name = _name;
		selections.add(entry);
		return entry;
	}
	
	public static void read(string backup_file){

		if (selections == null){
			selections = new Gee.ArrayList<AppSelection>();
		}
		
		selections.clear();

		if (!file_exists(backup_file)){ return; }
		
		foreach(string line in file_read(backup_file).split("\n")){
			var arr = line.split("|");
			if (arr.length < 3){ continue; }
			
			var entry = new AppSelection();
			entry.user = arr[0];
			entry.selected = (arr[1] == "1");
			entry.name = arr[2];
			selections.add(entry);
		}

		log_debug("read app selections: %d".printf(selections.size));
	}

	public static Gee.ArrayList<AppSelection> get_selections_for_user(string username){
		
		var list = new Gee.ArrayList<AppSelection>();
		foreach(var x in selections){
			if (x.user == username){
				list.add(x);
			}
		}
		return list;
	}

	public static void select(string user, string name){
		
		foreach(var item in selections){
			if ((item.user == user) && (item.name == name)){
				item.selected = true;
				return;
			}
		}
		// not found
		add_item(user, name, true);
	}

	public static void unselect(string user, string name){
		
		foreach(var item in selections){
			if ((item.user == user) && (item.name == name)){
				item.selected = false;
				return;
			}
		}
		// not found
		add_item(user, name, false);
	}

	public static void save(string backup_file){

		string txt = "";
		foreach(var item in selections){
			txt += "%s|%s|%s\n".printf(item.user, (item.selected ? "1" : "0"), item.name);
		}
		
		file_write(backup_file, txt);

		log_debug("saved app selections: %d".printf(selections.size));
	}
}

