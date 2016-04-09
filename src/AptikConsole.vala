/*
 * AptikConsole.vala
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
using Soup;
using Json;

using TeeJee.Logging;
using TeeJee.FileSystem;
using TeeJee.JSON;
using TeeJee.ProcessManagement;
using TeeJee.GtkHelper;
using TeeJee.Multimedia;
using TeeJee.System;
using TeeJee.Misc;

public Main App;
public const string AppName = "Aptik Migration Utility";
public const string AppShortName = "aptik";
public const string AppVersion = "16.4";
public const string AppAuthor = "Tony George";
public const string AppAuthorEmail = "teejeetech@gmail.com";

const string GETTEXT_PACKAGE = "";
const string LOCALE_DIR = "/usr/share/locale";

public class AptikConsole : GLib.Object {

	public static int main (string[] args) {
		set_locale();

		LOG_TIMESTAMP = false;

		if (!user_is_admin()) {
			log_msg(_("Aptik needs admin access to backup and restore packages."));
			log_msg(_("Please run the application as admin (using 'sudo' or 'su')"));
			exit(0);
		}

		init_tmp();

		App = new Main(args, false);
		
		var console =  new AptikConsole();
		bool is_success = console.parse_arguments(args);
		App.exit_app();

		return (is_success) ? 0 : 1;
	}

	private static void set_locale() {
		Intl.setlocale(GLib.LocaleCategory.MESSAGES, "aptik");
		Intl.textdomain(GETTEXT_PACKAGE);
		Intl.bind_textdomain_codeset(GETTEXT_PACKAGE, "utf-8");
		Intl.bindtextdomain(GETTEXT_PACKAGE, LOCALE_DIR);
	}

	public string help_message() {
		string msg = "\n" + AppName + " v" + AppVersion + " by Tony George (teejee2008@gmail.com)" + "\n";
		msg += "\n";
		msg += _("Syntax") + ": aptik [options]\n";
		msg += "\n";
		msg += _("Options") + ":\n";
		msg += "\n";
		msg += _("Common") + ":\n";
		msg += "\n";
		msg += "  --backup-dir <dir>    " + _("Backup directory (defaults to current directory)") + "\n";
		msg += "  --user <username>     " + _("Select username for listing config files") + "\n";
		msg += "  --password <password> " + _("Specify password for encrypting and decrypting backups") + "\n";
		msg += "  --[show-]desc         " + _("Show package description if available") + "\n";
		msg += "  --yes                 " + _("Assume Yes for all prompts") + "\n";
		msg += "  --h[elp]              " + _("Show all options") + "\n";
		msg += "\n";
		msg += _("Software Sources (PPAs)") + ":\n";
		msg += "\n";
		msg += "  --list-ppa            " + _("List PPAs") + "\n";
		msg += "  --backup-ppa          " + _("Backup list of PPAs") + "\n";
		msg += "  --restore-ppa         " + _("Restore PPAs from file 'ppa.list'") + "\n";
		msg += "\n";
		msg += _("Downloaded Packages (APT Cache)") + ":\n";
		msg += "\n";
		msg += "  --backup-cache        " + _("Backup downloaded packages from APT cache") + "\n";
		msg += "  --restore-cache       " + _("Restore downloaded packages to APT cache") + "\n";
		msg += "\n";
		msg += _("Software Selections (Installed Packages)") + ":\n";
		msg += "\n";
		msg += "  --list-available      " + _("List available packages") + "\n";
		msg += "  --list-installed      " + _("List installed packages") + "\n";
		msg += "  --list-auto[matic]    " + _("List auto-installed packages") + "\n";
		msg += "  --list-{manual|extra} " + _("List extra packages installed by user") + "\n";
		msg += "  --list-default        " + _("List default packages for linux distribution") + "\n";
		msg += "  --backup-packages     " + _("Backup list of manual and installed packages") + "\n";
		msg += "  --restore-packages    " + _("Restore packages from file 'packages.list'") + "\n";
		msg += "\n";
		msg += _("Users and groups") + ":\n";
		msg += "\n";
		msg += "  --backup-users        " + _("Backup users and groups") + "\n";
		msg += "  --restore-users       " + _("Restore users and groups") + "\n";
		msg += "\n";
		msg += _("Application Settings") + ":\n";
		msg += "\n";
		msg += "  --list-configs        " + _("List config dirs in /home/<user>") + "\n";
		msg += "  --backup-configs      " + _("Backup config files from /home/<user>") + "\n";
		msg += "  --restore-configs     " + _("Restore config files to /home/<user>") + "\n";
		msg += "  --size-limit <bytes>  " + _("Skip config dirs larger than specified size") + "\n";
		msg += "\n";
		msg += _("Themes and Icons") + ":\n";
		msg += "\n";
		msg += "  --list-themes         " + _("List themes in /usr/share/themes") + "\n";
		msg += "  --backup-themes       " + _("Backup themes from /usr/share/themes") + "\n";
		msg += "  --restore-themes      " + _("Restore themes to /usr/share/themes") + "\n";
		msg += "\n";
		msg += _("Filesystem Mounts") + ":\n";
		msg += "\n";
		msg += "  --backup-mounts       " + _("Backup /etc/fstab and /etc/crypttab entries") + "\n";
		msg += "  --restore-mounts      " + _("Restore /etc/fstab and /etc/crypttab entries") + "\n";
		msg += "\n";
		msg += _("User Data / Home Directory") + ":\n";
		msg += "\n";
		msg += "  --backup-home         " + _("Backup user-created data in user's home directory") + "\n";
		msg += "  --restore-home        " + _("Restore user-created data in user's home directory") + "\n";
		msg += "\n";
		msg += _("All Items") + ":\n";
		msg += "\n";
		msg += "  --backup-all          " + _("Backup all items") + "\n";
		msg += "  --restore-all         " + _("Restore all items") + "\n";
		msg += "\n";
		return msg;
	}

	public bool parse_arguments(string[] args) {

		bool show_desc = false;
		bool no_prompt = false;
		bool ok = false;
		
		if (args.length == 1) {
			//no args given
			log_msg(help_message());
			return false;
		}

		//parse options
		for (int k = 1; k < args.length; k++) // Oth arg is app path
		{
			switch (args[k].down()) {
			case "--desc":
			case "--show-desc":
				show_desc = true;
				break;
			case "--backup-dir":
				k += 1;
				App.backup_dir = args[k] + (args[k].has_suffix("/") ? "" : "/");
				if (!dir_exists(App.backup_dir)){
					log_error(_("Backup directory not found") + ": '%s'".printf(App.backup_dir));
					exit(1);
				}
				break;
			case "--user":
			case "--username":
				k += 1;
				App.select_user(args[k]);
				break;
			case "--size-limit":
			case "--limit-size":
				k += 1;
				App.arg_size_limit = uint64.parse(args[k]);
				break;
			case "-y":
			case "--yes":
				no_prompt = true;
				break;
			case "--debug":
				LOG_DEBUG = true;
				break;
			case "--password":
				k += 1;
				App.arg_password = args[k];
				break;
			case "--help":
			case "--h":
			case "-h":
				log_msg(help_message());
				return true;
			}
		}

		if (App.user_login.length == 0){
			App.select_user("");
		}

		//parse commands
		for (int k = 1; k < args.length; k++) // Oth arg is app path
		{
			switch (args[k].down()) {

			// ppa --------------------------------------------
			
			case "--list-ppa":
			case "--list-ppas":
				App.ppa_backup_init(show_desc);
				foreach(Ppa ppa in App.ppa_list_master.values) {
					ppa.is_selected = true;
				}
				print_ppa_list(show_desc);
				//TODO: call the faster method for getting ppas?
				break;

			case "--backup-ppa":
			case "--backup-ppas":
				return backup_ppa();
				
			case "--restore-ppa":
			case "--restore-ppas":
				return restore_ppa();

			// package ---------------------------------------

			case "--list-available":
				App.read_package_info();
				foreach(Package pkg in App.pkg_list_master.values) {
					pkg.is_selected = (pkg.is_available && !pkg.is_foreign());
				}
				print_package_list(show_desc);
				break;

			case "--list-installed":
				App.read_package_info();
				foreach(Package pkg in App.pkg_list_master.values) {
					pkg.is_selected = pkg.is_installed;
				}
				print_package_list(show_desc);
				break;

			case "--list-default":
				App.read_package_info();
				foreach(Package pkg in App.pkg_list_master.values) {
					pkg.is_selected = pkg.is_default;
				}
				print_package_list(show_desc);
				break;

			case "--list-auto":
			case "--list-automatic":
				App.read_package_info();
				foreach(Package pkg in App.pkg_list_master.values) {
					pkg.is_selected = pkg.is_automatic;
				}
				print_package_list(show_desc);
				break;

			case "--list-manual":
			case "--list-extra":
				App.read_package_info();
				foreach(Package pkg in App.pkg_list_master.values) {
					pkg.is_selected = pkg.is_manual;
				}
				print_package_list(show_desc);
				break;

			case "--backup-package":
			case "--backup-packages":
				return backup_packages();

			case "--restore-package":
			case "--restore-packages":
				return restore_packages(no_prompt);
				
			// apt cache -------------------------------------

			case "--backup-cache":
			case "--backup-apt-cache":
				return backup_cache();

			case "--restore-cache":
			case "--restore-apt-cache":
				return restore_cache();
				
			// config ---------------------------------------

			case "--list-config":
			case "--list-configs":
				print_config_list(App.list_app_config_directories_from_home());
				break;

			case "--backup-appsettings":
			case "--backup-configs":
			case "--backup-config":
				return backup_config();

			case "--restore-appsettings":
			case "--restore-configs":
				return restore_config();

			// home -------------------------------------

			case "--backup-user-data":
			case "--backup-home":
				return backup_home();

			case "--restore-user-data":
			case "--restore-home":
				return restore_home();
				
			// theme ---------------------------------------------

			case "--list-theme":
			case "--list-themes":
				print_theme_list(Theme.list_themes_installed(App.user_login, true));
				break;

			case "--backup-theme":
			case "--backup-themes":
				return backup_themes();
				
			case "--restore-theme":
			case "--restore-themes":
				return restore_themes();

			// mount -------------------------------------------
			
			case "--backup-mount":
			case "--backup-mounts":
				return backup_mounts();

			case "--restore-mount":
			case "--restore-mounts":
				return restore_mounts();

			// users -------------------------------------------

			case "--list-user":
			case "--list-users":
				return list_users_and_groups();

			case "--backup-user":
			case "--backup-users":
				return backup_users_and_groups();

			case "--restore-user":
			case "--restore-users":
				return restore_users_and_groups();

			// all ---------------------------------------------

			case "--backup-all":
				return backup_all();

			case "--restore-all":
				return restore_all();

			// other -------------------------------------------
			
			case "--take-ownership":
				App.take_ownership();
				break;

			case "--check-perf":
				check_performance();
				break;

			case "--desc":
			case "--show-desc":
			case "-y":
			case "--yes":
			case "--help":
			case "--h":
			case "-h":
			case "--debug":
				//handled already - do nothing
				break;

			case "--user":
			case "--username":
			case "--backup-dir":
			case "--size-limit":
			case "--limit-size":
			case "--password":
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

	public void check_performance() {
		App.read_package_info();

		var timer = timer_start();

		timer.start();
		//App.list_ppa();
		log_msg("list_ppa: %s".printf(timer_elapsed_string(timer)));

		timer.start();
		//App.list_themes();
		//log_msg("list_themes: %s".printf(timer_elapsed_string(timer)));

		timer.start();
		//App.list_icons();
		//log_msg("list_icons: %s".printf(timer_elapsed_string(timer)));

		timer.start();
		App.list_app_config_directories_from_home();
		log_msg("list_apps: %s".printf(timer_elapsed_string(timer)));
	}

	public void print_package_list(bool show_desc) {
		//create an arraylist and sort items for printing
		var pkg_list = new ArrayList<Package>();
		foreach(Package pkg in App.pkg_list_master.values) {
			if (pkg.is_selected) {
				pkg_list.add(pkg);
			}
		}
		CompareDataFunc<Package> func = (a, b) => {
			return strcmp(a.name, b.name);
		};
		pkg_list.sort((owned)func);

		int max_length = 0;
		foreach(Package pkg in pkg_list) {
			if (pkg.name.length > max_length) {
				max_length = pkg.name.length;
			}
			if (pkg.is_foreign()){
				pkg.name = "%s:%s".printf(pkg.name,pkg.arch);
			}
		}
		string fmt = "%%-%ds".printf(max_length + 2);

		if (show_desc) {
			fmt = fmt + "%s";
			foreach(Package pkg in pkg_list) {
				log_msg(fmt.printf(pkg.name, pkg.description));
			}
		}
		else {
			foreach(Package pkg in pkg_list) {
				log_msg(fmt.printf(pkg.name));
			}
		}
	}

	public void print_ppa_list(bool show_desc) {
		//create an arraylist and sort items for printing
		var ppa_list = new ArrayList<Ppa>();
		foreach(Ppa ppa in App.ppa_list_master.values) {
			if (ppa.is_selected) {
				ppa_list.add(ppa);
			}
		}
		CompareDataFunc<Ppa> func = (a, b) => {
			return strcmp(a.name, b.name);
		};
		ppa_list.sort((owned)func);

		int max_length = 0;
		foreach(Ppa ppa in ppa_list) {
			if (ppa.name.length > max_length) {
				max_length = ppa.name.length;
			}
		}
		string fmt = "%%-%ds".printf(max_length + 2);

		if (show_desc) {
			fmt = fmt + "%s";
			foreach(Ppa ppa in ppa_list) {
				log_msg(fmt.printf(ppa.name, ppa.description));
			}
		}
		else {
			foreach(Ppa ppa in ppa_list) {
				log_msg(fmt.printf(ppa.name));
			}
		}
	}

	public void print_theme_list(Gee.ArrayList<Theme> theme_list) {
		int max_length = 0;
		foreach(Theme theme in theme_list) {
			var full_name = "%s/%s".printf(theme.dir_type,theme.name);
			if (full_name.length > max_length) {
				max_length = full_name.length;
			}
		}
		string fmt = "%%-%ds".printf(max_length + 2);
		foreach(Theme theme in theme_list) {
			var full_name = "%s/%s".printf(theme.dir_type,theme.name);
			log_msg(fmt.printf(full_name));
		}
	}

	public void print_config_list(Gee.ArrayList<AppConfig> config_list) {
		foreach(AppConfig config in config_list){
			log_msg("%-60s%10s".printf(config.name,config.size));
			//TODO: show size in bytes with commas
		}
	}

	// ppa -----------------------

	public bool backup_ppa() {
		App.ppa_backup_init(false);
		foreach(Ppa ppa in App.ppa_list_master.values) {
			ppa.is_selected = true;
		}
		
		//TODO: call the faster method for getting ppas?
		bool ok = App.save_ppa_list_selected();
		
		if (ok){
			log_msg(Message.BACKUP_OK);
		}
		else{
			log_msg(Message.BACKUP_ERROR);
		}

		return ok;
	}
	
	public bool restore_ppa() {
		if (!App.check_backup_file("ppa.list")) {
			return false;
		}
		
		if (!check_internet_connectivity()) {
			log_msg(_("Error") + ": " +  _("Internet connection is not active. Please check the connection and try again."));
			return false;
		}

		App.ppa_restore_init(false);
		
		bool run_apt_update = false;
		foreach(Ppa ppa in App.ppa_list_master.values) {
			if (ppa.is_selected && !ppa.is_installed) {
				log_msg(_("Adding PPA") + " '%s'".printf(ppa.name));

				Posix.system("sudo apt-add-repository -y ppa:%s".printf(ppa.name));
				//exit code is not reliable (always 0?)

				run_apt_update = true;
				log_msg("");
			}
		}

		if (run_apt_update) {
			log_msg(_("Updating Package Information..."));
			Posix.system("sudo apt-get -y update");
		}

		log_msg(Message.RESTORE_OK);
		
		return true;
	}

	// cache ----------------------

	public bool backup_cache(){
		App.backup_apt_cache();
		while (App.is_running) {
			sleep(500);
		}
		log_msg(Message.BACKUP_OK);
		return true;
	}

	public bool restore_cache(){
		App.restore_apt_cache();
		while (App.is_running) {
			sleep(500);
		}
		log_msg(Message.RESTORE_OK);
		return true;
	}
	
	// packages --------------------------

	public bool backup_packages(){
		App.read_package_info();
		foreach(Package pkg in App.pkg_list_master.values) {
			pkg.is_selected = pkg.is_manual;
		}
		bool ok = App.save_package_list_selected();

		if (ok){
			log_msg(Message.BACKUP_OK);
		}
		else{
			log_msg(Message.BACKUP_ERROR);
		}

		return ok;
	}

	public bool restore_packages(bool no_prompt){
		bool ok = true;
		
		if (!App.check_backup_file("packages.list")) {
			return false;
		}
		
		if (!check_internet_connectivity()) {
			log_msg(_("Error") + ": " +  _("Internet connection is not active. Please check the connection and try again."));
			return false;
		}

		App.read_package_info();
		App.update_pkg_list_master_for_restore(true);
		
		if (App.pkg_list_missing.length > 0) {
			log_msg(_("Following packages are not available") + ":\n%s\n".printf(App.pkg_list_missing));
		}

		if ((App.pkg_list_install.length == 0) && (App.pkg_list_deb.length == 0)) {
			log_msg(_("Selected packages are already installed"));
		}
		else{
			if (App.pkg_list_install.length > 0){
				log_msg(_("Following packages will be installed") + ":\n%s\n".printf(App.pkg_list_install));

				var command = "apt-get";
				var cmd_path = get_cmd_path ("apt-fast");
				if ((cmd_path != null) && (cmd_path.length > 0)) {
					command = "apt-fast";
				}

				int status = Posix.system("%s%s install %s".printf(command, (no_prompt) ? " -y" : "", App.pkg_list_install));

				ok = ok && (status == 0);
			}
			if (App.pkg_list_deb.length > 0){
				log_msg(_("Following packages will be installed") + ":\n%s\n".printf(App.pkg_list_deb));
				foreach(string line in App.gdebi_list.split("\n")){
					Posix.system("gdebi%s %s".printf((no_prompt) ? " -n" : "", line));
				}
			}
		}

		if (ok){
			log_msg(Message.RESTORE_OK);
		}
		else{
			log_msg(Message.RESTORE_ERROR);
		}
		
		return ok;
	}
	
	// users and groups ----------------------------

	public bool list_users_and_groups(){
		bool ok = true;

		SystemUser.query_users();
		SystemGroup.query_groups();

		// sort users -----------------
		
		var list = new Gee.ArrayList<SystemUser>();
		foreach(var item in SystemUser.all_users.values){
			list.add(item);
		}
		CompareDataFunc<SystemUser> func_group = (a, b) => {
			return strcmp(a.name, b.name);
		};
		list.sort((owned) func_group);

		// print users -----------------
		
		log_msg("%5s %-15s".printf("UID", "User"));
		log_msg(string.nfill(70,'-'));
		foreach(var user in list){
			if (!user.is_system){
				log_msg("%5d %-15s".printf(user.uid, user.name));
			}
		}
		log_msg("");

		// sort groups -----------------
		
		var list_group = new Gee.ArrayList<SystemGroup>();
		foreach(var item in SystemGroup.all_groups.values){
			list_group.add(item);
		}
		CompareDataFunc<SystemGroup> func = (a, b) => {
			return strcmp(a.name, b.name);
		};
		list_group.sort((owned) func);

		// print groups -----------------
		
		log_msg("%5s %-15s %s".printf("GID","Group","Users"));
		log_msg(string.nfill(70,'-'));
		foreach(var group in list_group){
			if (!group.is_system){
				log_msg("%5d %-15s %s".printf(group.gid, group.name, group.user_names));
			}
		}
		log_msg("");
		
		return ok;
	}

	public bool backup_users_and_groups(){
		bool ok = App.backup_users_and_groups("");
		
		if (ok){
			log_msg(Message.BACKUP_OK);
		}
		else{
			log_msg(Message.BACKUP_ERROR);
		}

		return ok;
	}

	public bool restore_users_and_groups(){
		bool ok = true;

		ok = App.restore_users_and_groups_init("");
		
		if (!ok){
			return ok;
		}

		ok = App.restore_users_and_groups();
		
		if (ok){
			log_msg(Message.RESTORE_OK);
		}
		else{
			log_msg(Message.RESTORE_ERROR);
		}

		return ok;
	}

	// configs ------------------------

	public bool backup_config(){
		bool ok = true;
		
		if (App.user_login.length == 0){
			foreach(string username in list_dir_names("/home")){
				if (username == "PinguyBuilder"){
					continue;
				}
			
				App.select_user(username);

				var list = App.list_app_config_directories_from_home();
				foreach(AppConfig conf in list){
					conf.is_selected = true;
				}

				var status = App.backup_app_settings_all(list);
				ok = ok && status;
				
				log_msg("");
			}
		}
		else{
			var list = App.list_app_config_directories_from_home();
			foreach(AppConfig conf in list){
				conf.is_selected = true;
			}

			var status = App.backup_app_settings_all(list);
			ok = ok && status;
		}

		if (ok){
			log_msg(Message.BACKUP_OK);
		}
		else{
			log_msg(Message.BACKUP_ERROR);
		}

		return ok;
	}

	public bool restore_config(){
		bool ok = true;
		
		if (App.user_login.length == 0){
			foreach(string username in list_dir_names("/home")){
				App.select_user(username);
				
				var list = App.list_app_config_directories_from_backup();
				foreach(AppConfig conf in list){
					conf.is_selected = true;
				}

				var status = App.restore_app_settings_all(list);
				ok = ok && status;
			
				log_msg("");
			}
		}
		else{
			var list = App.list_app_config_directories_from_backup();
			foreach(AppConfig conf in list){
				conf.is_selected = true;
			}

			var status = App.restore_app_settings_all(list);
			ok = ok && status;
		}

		if (ok){
			log_msg(Message.RESTORE_OK);
		}
		else{
			log_msg(Message.RESTORE_ERROR);
		}
		
		return ok;
	}

	// themes ----------------------

	public bool backup_themes(){
		bool ok = true;

		foreach(Theme theme in Theme.list_themes_installed()) {
			if (theme.is_selected) {
				theme.zip(App.backup_dir,false);
				while (theme.is_running) {
					sleep(500);
				}
			}
		}
				
		if (ok){
			log_msg(Message.BACKUP_OK);
		}
		else{
			log_msg(Message.BACKUP_ERROR);
		}

		return ok;
	}

	public bool restore_themes(){
		bool ok = true;
		
		var list = Theme.list_themes_archived(App.backup_dir);

		foreach(Theme theme in list){
			theme.check_installed(App.user_login);
			theme.is_selected = !theme.is_installed;
		}
		
		foreach(Theme theme in list) {
			if (theme.is_selected && !theme.is_installed) {
				theme.unzip(App.user_login,false);
				while (theme.is_running) {
					sleep(500);
				}

				theme.update_permissions();
				theme.update_ownership(App.user_login);
			}
		}

		if (ok){
			log_msg(Message.RESTORE_OK);
		}
		else{
			log_msg(Message.RESTORE_ERROR);
		}

		return ok;
	}
	
	// mounts ---------------------
	
	public bool backup_mounts(){
		bool ok = App.backup_mounts();
		
		if (ok){
			log_msg(Message.BACKUP_OK);
		}
		else{
			log_msg(Message.BACKUP_ERROR);
		}

		return ok;
	}
	
	public bool restore_mounts(){
		var fstab_list = App.create_fstab_list_for_restore();
		var crypttab_list = App.create_crypttab_list_for_restore();

		bool ok = App.restore_mounts(fstab_list, crypttab_list, "");

		if (ok){
			log_msg(Message.RESTORE_OK);
		}
		else{
			log_msg(Message.RESTORE_ERROR);
		}
		
		return ok;
	}

	// mounts ---------------------
	
	public bool backup_home(){

		// get password -------------------
		
		App.prompt_for_password(true);
		
		if (App.arg_password.length == 0){
			log_error(Message.PASSWORD_MISSING);
			return false;
		}

		// backup ------------------
		
		int status = Posix.system("%s\n".printf(save_bash_script_temp(App.backup_home_get_script())));
			
		bool ok = (status == 0);
		
		if (ok){
			log_msg(Message.BACKUP_OK);
		}
		else{
			log_msg(Message.BACKUP_ERROR);
		}

		return ok;
	}
	
	public bool restore_home(){
		
		// get password -------------------
		
		App.prompt_for_password(false);
		
		if (App.arg_password.length == 0){
			log_error(Message.PASSWORD_MISSING);
			return false;
		}

		// restore ------------
		
		int status = Posix.system("%s\n".printf(save_bash_script_temp(App.restore_home_get_script())));
			
		bool ok = (status == 0);

		if (ok){
			log_msg(Message.RESTORE_OK);
		}
		else{
			log_msg(Message.RESTORE_ERROR);
		}
		
		return ok;
	}

	// all items ----------------------------------

	public bool backup_all(){
		bool ok = false;

		App.task_list = BackupTask.create_list();
		App.backup_mode = true;

		foreach(var task in App.task_list){
			if (!task.is_selected){
				continue;
			}

			log_msg("");
			log_draw_line();
			string mode = (App.backup_mode) ? _("Backup") : _("Restore");
			log_msg("%s - %s".printf(mode,task.display_name));
			log_draw_line();
			log_msg("");
			
			string cmd = (App.backup_mode) ? task.backup_cmd : task.restore_cmd;

			log_debug(cmd);
			
			Posix.system(cmd);
		}
		
		if (ok){
			log_msg(Message.BACKUP_OK);
		}
		else{
			log_msg(Message.BACKUP_ERROR);
		}

		return ok;
	}

	public bool restore_all(){
		bool ok = false;

		App.task_list = BackupTask.create_list();
		App.backup_mode = false;

		foreach(var task in App.task_list){
			if (!task.is_selected){
				continue;
			}

			log_msg("");
			log_draw_line();
			string mode = (App.backup_mode) ? _("Backup") : _("Restore");
			log_msg("%s - %s".printf(mode,task.display_name));
			log_draw_line();
			log_msg("");
			
			string cmd = (App.backup_mode) ? task.backup_cmd : task.restore_cmd;

			log_debug(cmd);
			
			Posix.system(cmd);
		}
		
		if (ok){
			log_msg(Message.BACKUP_OK);
		}
		else{
			log_msg(Message.BACKUP_ERROR);
		}

		return ok;
	}

}

