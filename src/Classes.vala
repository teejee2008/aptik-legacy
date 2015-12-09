/*
 * Classes.vala
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


public class Package : GLib.Object {
	public string name = "";
	public string description = "";
	public string server = "";
	public string repo = "";
	public string repo_section = "";
	public string arch = "";
	public string status = "";
	public string section = "";
	public string version_installed = "";
	public string version_available = "";
	public bool is_selected = false;
	public bool is_available = false;
	public bool is_installed = false;
	public bool is_default = false;
	public bool is_automatic = false;
	public bool is_manual = false;

	public Package(string _name){
		name = _name;
	}
}

public struct Package2 {
	public string name;
	public string description;
	public string server;
	public string repo;
	public bool is_selected;
	public bool is_available;
	public bool is_installed;
	public bool is_top;
	public bool is_default;
	public bool is_manual;

	public Package2(string _name){
		name = _name;
	}
}

public class Ppa : GLib.Object{
	public string name = "";
	public string description = "";
	public string all_packages = "";
	public bool is_selected = false;
	public bool is_installed = false;

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

public class Theme : GLib.Object{
	public string name = "";
	public string description = "";
	public string system_path = "";
	public string zip_file_path = "";
	public bool is_selected = false;
	public bool is_installed = false;
	public string type = "";

	public Theme(string _name, string _type){
		name = _name;
		type = _type;
		system_path = "/usr/share/%ss/%s".printf(type, name);
	}
}

public class AppConfig : GLib.Object{
	public string name = "";
	public string description = "";
	public bool is_selected = false;
	public string size = "";

	public AppConfig(string dir_name){
		name = dir_name;
	}

	public string path{
		owned get{
			string str = name.replace("~",App.user_home);
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
