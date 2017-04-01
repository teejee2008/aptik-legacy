/*
 * Classes.vala
 *
 * Copyright 2012-2017 Tony George <teejeetech@gmail.com>
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
using TeeJee.System;
using TeeJee.Misc;
using TeeJee.GtkHelper;


public class Package : GLib.Object {
	public string id = "";
	public string name = "";
	public string description = "";
	public string server = "";
	public string repo = "";
	public string repo_section = "";
	public string arch = "";
	public string status = "";
	public string section = "";
	public string version = "";
	public string version_installed = "";
	public string version_available = "";
	public string depends = "";
	public string gid = "";

	public string deb_file_name = "";
	public string deb_uri = "";
	public int64 deb_size = 0;
	public string deb_md5hash = "";

	public bool is_selected = false;
	public bool is_available = false;
	public bool is_installed = false;
	public bool is_default = false;
	public bool is_automatic = false;
	public bool is_manual = false;
	public bool is_deb = false;

	//convenience members
	public bool is_visible = false;
	public bool in_backup_list = false;

	public Package(string _name){
		name = _name;
	}

	public bool is_foreign(){
		if (check_if_foreign(arch)){
			return true;
		}
		else{
			return false;
		}
	}

	public static string get_id(string _name, string _arch){
		string str = "";
		str = "%s".printf(_name);
		if (check_if_foreign(_arch)){
			str = str + ":%s".printf(_arch); //make it unique
		}
		return str;
	}

	public static bool check_if_foreign(string architecture){
		if ((architecture.length > 0) && (architecture != App.NATIVE_ARCH) && (architecture != "all") && (architecture != "any")){
			return true;
		}
		else{
			return false;
		}
	}
}

//unused
public class Repository : GLib.Object{
	public string name = "";
	public string description = "";

	public bool is_selected = false;
	public bool is_installed = false;

	public Type type = Type.BINARY;
	public string URI = "";
	public string dist = "";
	public string sections = "";
	public string comments = "";

	public enum Type{
		BINARY,
		SOURCE
	}
}

public class Ppa : GLib.Object{
	public string name = "";
	public string description = "";
	public string all_packages = "";
	public bool is_selected = false;
	public bool is_installed = false;

	public string message = "";

	public Ppa(string _name){
		name = _name;
	}
}

public class BatteryStat : GLib.Object{
	public DateTime date;
	public long charge_now = 0;
	//public long charge_full = 0;
	//public long charge_full_design = 0;
	//public long charge_percent = 0;
	public long voltage_now = 0;
	public long cpu_usage = 0;

	public long graph_x = 0;

	public static string BATT_STATS_CHARGE_NOW         = "/sys/class/power_supply/BAT0/charge_now";
	public static string BATT_STATS_CHARGE_FULL        = "/sys/class/power_supply/BAT0/charge_full";
	public static string BATT_STATS_CHARGE_FULL_DESIGN = "/sys/class/power_supply/BAT0/charge_full_design";
	public static string BATT_STATS_VOLTAGE_NOW        = "/sys/class/power_supply/BAT0/voltage_now";

	public BatteryStat.read_from_sys(){
		this.date = new DateTime.now_local();
		this.charge_now = batt_charge_now();
		//this.charge_full = batt_charge_full();
		//this.charge_full_design = batt_charge_full_design();
		//this.charge_percent = (long) ((charge_now / batt_charge_full() * 1.00) * 1000);
		this.voltage_now = batt_voltage_now();
		this.cpu_usage = (long) (ProcStats.get_cpu_usage() * 1000);
	}

	public BatteryStat.from_delimited_string(string line){
		var arr = line.split("|");
		if (arr.length == 4){
			DateTime date_utc = new DateTime.from_unix_utc(int64.parse(arr[0]));
			this.date = date_utc.to_local();
			this.charge_now = long.parse(arr[1]);
			this.voltage_now = long.parse(arr[2]);
			this.cpu_usage = long.parse(arr[3]);


			//log_msg("%ld".printf(this.charge_percent));
		}
	}

	public string to_delimited_string(){
		var txt = date.to_utc().to_unix().to_string() + "|";
		txt += charge_now.to_string() + "|";
		txt += voltage_now.to_string() + "|";
		txt += cpu_usage.to_string();
		txt += "\n";
		return txt;
	}

	public double voltage(){
		return (voltage_now / 1000000.00);
	}

	public double charge_percent(){
		return (((charge_now * 1.00) / batt_charge_full()) * 100);
	}

	public double charge_in_mah(){
		return (charge_now / 1000.0);
	}

	public double charge_in_wh(){
		return ((charge_in_mah() * voltage()) / 1000.00);
	}

	public double cpu_percent(){
		return (cpu_usage / 1000.00);
	}

	public static long batt_charge_now(){
		string val = read_sys_stat_file(BATT_STATS_CHARGE_NOW);
		if (val.length == 0) { return 0; }
		return long.parse(val);
	}

	public static long batt_charge_full(){
		string val = read_sys_stat_file(BATT_STATS_CHARGE_FULL);
		if (val.length == 0) { return 0; }
		return long.parse(val);
	}

	public static long batt_charge_full_design(){
		string val = read_sys_stat_file(BATT_STATS_CHARGE_FULL_DESIGN);
		if (val.length == 0) { return 0; }
		return long.parse(val);
	}

	public static long batt_voltage_now(){
		string val = read_sys_stat_file(BATT_STATS_VOLTAGE_NOW);
		if (val.length == 0) { return 0; }
		return long.parse(val);
	}

	public static string read_sys_stat_file(string statFile){
		try{
			var file = File.new_for_path(statFile);
			if (file.query_exists()){
				var dis = new DataInputStream (file.read());
				string line = dis.read_line (null);
				if (line != null) {
					return line;
				}
			} //stream closed
		}
		catch (Error e){
				log_error (e.message);
		}

		return "";
	}
}

public class AppConfig : GLib.Object{
	public string name = "";
	public string description = "";
	public bool is_selected = false;
	public string size = "";
	public uint64 bytes = 0;

	public AppConfig(string dir_name){
		name = dir_name;
	}

	public string path{
		owned get{
			string str = name.replace("~",App.current_user.home_path);
			return str.strip();
		}
	}

	public string pattern{
		owned get{
			string str = path + "/**";
			return str.strip();
		}
	}
}

public class FsTabEntry : GLib.Object{
	public string device = "";
	public string mount_point = "";
	public string fs_type = "";
	public string options = "";
	public string dump = "";
	public string pass = "";

	public string mapped_name = "";
	public string password = "";

	public bool is_selected = false;

	public Action action = Action.NONE;
	public DeviceType dev_type = DeviceType.REGULAR;

	public enum Action{
		ADD,
		MODIFY,
		NONE
	}

	public enum DeviceType{
		REGULAR,
		ENCRYPTED
	}

	public string action_display {
		owned get{
			switch(action){
			case Action.NONE:
				return _("No Change");
			case Action.ADD:
				return _("Add");
			case Action.MODIFY:
				return _("Update");
			default:
				return _("No Change");
			}
		}
	}

	public string get_line(){
		if (dev_type == DeviceType.REGULAR){
			return fstab_line;
		}
		else{
			return crypttab_line;
		}
	}

	public string keyfile_archive_name{
		owned get{
			return "key-file-" + device.down().replace("/","-") + ".tar.gpg";
		}
	}

	public string mount_dir_archive_name{
		owned get{
			return "mount-point" + mount_point.down().replace("/","-") + ".tar";
		}
	}

	private string fstab_line{
		owned get{
			return "%s\t%s\t%s\t%s\t%s\t%s".printf(device,mount_point,fs_type,options,dump,pass);
		}
	}

	private string crypttab_line{
		owned get{
			return "%s\t%s\t%s\t%s".printf(mapped_name,device,password,options);
		}
	}

	public bool uses_keyfile(){
		return (password.length > 0) && (password != "none") && !password.has_prefix("/dev/");
	}

	// factory methods

	public static FsTabEntry create_from_fstab_line(string tab_line){
		var s = tab_line.strip();

		while (s.contains("  ")){
			s = s.replace("  "," ");
		}

		while (s.contains(" \t")){
			s = s.replace(" \t"," ");
		}

		while (s.contains("\t ")){
			s = s.replace("\t "," ");
		}

		s = s.replace(" ","\t");

		FsTabEntry fs = null;

		string[] arr = s.split("\t");
		if (arr.length == 6){
			fs = new FsTabEntry();
			fs.device = arr[0];
			fs.mount_point = arr[1];
			fs.fs_type = arr[2];
			fs.options = arr[3];
			fs.dump = arr[4];
			fs.pass = arr[5];
			fs.dev_type = DeviceType.REGULAR;
		}

		return fs;
	}

	public static FsTabEntry create_from_crypttab_line(string tab_line){
		var s = tab_line.strip();

		while (s.contains("  ")){
			s = s.replace("  "," ");
		}

		while (s.contains(" \t")){
			s = s.replace(" \t"," ");
		}

		while (s.contains("\t ")){
			s = s.replace("\t "," ");
		}

		s = s.replace(" ","\t");

		FsTabEntry fs = null;

		string[] arr = s.split("\t");
		if (arr.length == 4){
			fs = new FsTabEntry();
			fs.mapped_name = arr[0];
			fs.device = arr[1];
			fs.password = arr[2];
			fs.options = arr[3];
			fs.dev_type = DeviceType.ENCRYPTED;
		}

		return fs;
	}

	// read file

	public static Gee.ArrayList<FsTabEntry> read_fstab_file(string tab_file, string password){
		var list = new Gee.ArrayList<FsTabEntry>();

		if (!file_exists(tab_file)){
			return list;
		}

		string txt = "";
		if (tab_file.has_suffix(".tar.gpg")){
			txt = file_decrypt_untar_read(tab_file, password);
		}
		else{
			txt = file_read(tab_file);
		}

		foreach(string line in txt.split("\n")){
			if (line.strip().has_prefix("#")){
				continue;
			}
			var fs = create_from_fstab_line(line);
			if (fs != null){
				list.add(fs);
			}
		}

		return list;
	}

	public static Gee.ArrayList<FsTabEntry> read_crypttab_file(string tab_file, string password){
		var list = new Gee.ArrayList<FsTabEntry>();

		if (!file_exists(tab_file)){
			return list;
		}

		string txt = "";
		if (tab_file.has_suffix(".tar.gpg")){
			txt = file_decrypt_untar_read(tab_file, password);
		}
		else{
			txt = file_read(tab_file);
		}

		foreach(string line in txt.split("\n")){
			if (line.strip().has_prefix("#")){
				continue;
			}
			var fs = create_from_crypttab_line(line);
			if (fs != null){
				list.add(fs);
			}
		}

		return list;
	}

	// save file

	public static bool save_fstab_file(Gee.ArrayList<FsTabEntry> list){
		string txt = "";

		if (file_exists("/etc/fstab")){
			txt += file_read("/etc/fstab").strip() + "\n";
		}
		else{
			txt += "# <file system> <mount point> <type> <options> <dump> <pass>\n";
		}

		bool found_root = false;
		foreach(var fs in list){
			if (fs.is_selected && (fs.action == Action.ADD)){
				txt += "%s\n".printf(fs.get_line());
			}
			if (fs.mount_point == "/"){
				found_root = true;
			}
		}

		if (found_root){
			bool ok = file_write("/etc/fstab",txt);
			return ok;
		}

		return false;
	}

	public static bool save_crypttab_file(Gee.ArrayList<FsTabEntry> list){
		string txt = "";

		if (file_exists("/etc/crypttab")){
			txt += file_read("/etc/crypttab").strip() + "\n";
		}
		else{
			txt += "# <target name> <source device> <key file> <options>\n";
		}

		foreach(var fs in list){
			if (fs.is_selected && (fs.action == Action.ADD)){
				txt += "%s\n".printf(fs.get_line());
			}
		}

		bool ok = file_write("/etc/crypttab",txt);
		return ok;
	}

}
