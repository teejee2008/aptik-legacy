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
public const string AppName = "Aptik";
public const string AppShortName = "aptik";
public const string AppVersion = "1.6.4";
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
		msg += "  --list-available      " + _("List available packages") + "\n";
		msg += "  --list-installed      " + _("List installed packages") + "\n";
		msg += "  --list-auto[matic]    " + _("List auto-installed packages") + "\n";
		msg += "  --list-{manual|extra} " + _("List extra packages installed by user") + "\n";
		msg += "  --list-default        " + _("List default packages for linux distribution") + "\n";
		msg += "  --list-ppa            " + _("List PPAs") + "\n";
		msg += "  --list-themes         " + _("List themes in /usr/share/themes") + "\n";
		msg += "  --list-icons          " + _("List icon themes in /usr/share/icons") + "\n";
		msg += "  --list-configs        " + _("List config dirs in /home/<user>") + "\n";
		
		msg += "  --backup-ppa          " + _("Backup list of PPAs") + "\n";
		msg += "  --backup-packages     " + _("Backup list of manual and installed packages") + "\n";
		msg += "  --backup-cache        " + _("Backup downloaded packages from APT cache") + "\n";
		msg += "  --backup-themes       " + _("Backup themes from /usr/share/themes") + "\n";
		msg += "  --backup-icons        " + _("Backup icons from /usr/share/icons") + "\n";
		msg += "  --backup-configs      " + _("Backup config files from /home/<user>") + "\n";

		msg += "  --restore-ppa         " + _("Restore PPAs from file 'ppa.list'") + "\n";
		msg += "  --restore-packages    " + _("Restore packages from file 'packages.list'") + "\n";
		msg += "  --restore-cache       " + _("Restore downloaded packages to APT cache") + "\n";
		msg += "  --restore-themes      " + _("Restore themes to /usr/share/themes") + "\n";
		msg += "  --restore-icons       " + _("Restore icons to /usr/share/icons") + "\n";
		msg += "  --restore-configs     " + _("Restore config files to /home/<user>") + "\n";
		
		msg += "  --take-ownership      " + _("Take ownership of files in your home directory") + "\n";
		msg += "  --backup-dir          " + _("Backup directory (defaults to current directory)") + "\n";
		msg += "  --[show-]desc         " + _("Show package description if available") + "\n";
		msg += "  --yes                 " + _("Assume Yes for all prompts") + "\n";
		msg += "  --h[elp]              " + _("Show all options") + "\n";
		msg += "\n";
		return msg;
	}

	public bool parse_arguments(string[] args) {

		bool show_desc = false;
		bool no_prompt = false;

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
				break;
			case "-y":
			case "--yes":
				no_prompt = true;
				break;
			case "--debug":
				LOG_DEBUG = true;
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
			switch (args[k].down()) {
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

			case "--list-ppa":
			case "--list-ppas":
				App.read_package_info();
				App.ppa_list_master = App.list_ppa();
				foreach(Ppa ppa in App.ppa_list_master.values) {
					ppa.is_selected = true;
				}
				print_ppa_list(show_desc);
				//TODO: call the faster method for getting ppas?
				break;

			case "--list-theme":
			case "--list-themes":
				print_theme_list(App.list_themes());
				break;

			case "--list-icon":
			case "--list-icons":
				print_theme_list(App.list_icons());
				break;

			case "--list-config":
			case "--list-configs":
				print_config_list(App.list_app_config_directories_from_home());
				break;
				
			case "--backup-ppa":
			case "--backup-ppas":
				App.read_package_info();
				App.ppa_list_master = App.list_ppa();
				foreach(Ppa ppa in App.ppa_list_master.values) {
					ppa.is_selected = true;
				}
				//TODO: call the faster method for getting ppas?
				return App.save_ppa_list_selected();

			case "--backup-package":
			case "--backup-packages":
				App.read_package_info();
				foreach(Package pkg in App.pkg_list_master.values) {
					pkg.is_selected = pkg.is_manual;
				}

				return App.save_package_list_selected();

			case "--backup-cache":
			case "--backup-apt-cache":
				App.backup_apt_cache();
				while (App.is_running) {
					Thread.usleep ((ulong) 0.3 * 1000000);
				}
				break;

			case "--backup-theme":
			case "--backup-themes":
				foreach(Theme theme in App.list_themes()) {
					if (theme.is_selected) {
						App.zip_theme(theme);
						while (App.is_running) {
							Thread.usleep ((ulong) 0.3 * 1000000);
						}
					}
				}
				break;

			case "--backup-icon":
			case "--backup-icons":
				foreach(Theme theme in App.list_icons()) {
					if (theme.is_selected) {
						App.zip_theme(theme);
						while (App.is_running) {
							Thread.usleep ((ulong) 0.3 * 1000000);
						}
					}
				}
				break;
				
			case "--backup-appsettings":
			case "--backup-configs":
				var list = App.list_app_config_directories_from_home();
				foreach(AppConfig conf in list){
					conf.is_selected = true;
				}
				App.backup_app_settings_all(list);
				break;
				
			case "--restore-ppa":
			case "--restore-ppas":
				if (!check_internet_connectivity()) {
					log_msg(_("Error") + ": " +  _("Internet connection is not active. Please check the connection and try again."));
					return false;
				}

				App.read_package_info();
				restore_ppa();
				break;

			case "--restore-package":
			case "--restore-packages":
				if (!check_internet_connectivity()) {
					log_msg(_("Error") + ": " +  _("Internet connection is not active. Please check the connection and try again."));
					return false;
				}
				restore_packages(no_prompt);
				break;

			case "--restore-cache":
			case "--restore-apt-cache":
				App.restore_apt_cache();
				while (App.is_running) {
					Thread.usleep ((ulong) 0.3 * 1000000);
				}
				break;

			case "--restore-theme":
			case "--restore-themes":
				foreach(Theme theme in App.get_themes_from_backup("theme")) {
					if (theme.is_selected && !theme.is_installed) {
						App.unzip_theme(theme);
						while (App.is_running) {
							Thread.usleep ((ulong) 0.3 * 1000000);
						}
						App.update_permissions(theme.system_path);
					}
				}
				break;

			case "--restore-icon":
			case "--restore-icons":
				foreach(Theme theme in App.get_themes_from_backup("icon")) {
					if (theme.is_selected && !theme.is_installed) {
						App.unzip_theme(theme);
						while (App.is_running) {
							Thread.usleep ((ulong) 0.3 * 1000000);
						}
						App.update_permissions(theme.system_path);
					}
				}
				break;

			case "--restore-appsettings":
			case "--restore-configs":
				var list = App.list_app_config_directories_from_backup();
				foreach(AppConfig conf in list){
					conf.is_selected = true;
				}
				App.restore_app_settings_all(list);
				break;
				
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

	public void check_performance() {
		App.read_package_info();

		var timer = timer_start();

		timer.start();
		//App.list_ppa();
		log_msg("list_ppa: %s".printf(timer_elapsed_string(timer)));

		timer.start();
		App.list_themes();
		log_msg("list_themes: %s".printf(timer_elapsed_string(timer)));

		timer.start();
		App.list_icons();
		log_msg("list_icons: %s".printf(timer_elapsed_string(timer)));

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
			if (theme.name.length > max_length) {
				max_length = theme.name.length;
			}
		}
		string fmt = "%%-%ds".printf(max_length + 2);
		foreach(Theme theme in theme_list) {
			log_msg(fmt.printf(theme.name));
		}
	}

	public void print_config_list(Gee.ArrayList<AppConfig> config_list) {
		foreach(AppConfig config in config_list){
			log_msg("%-60s%10s".printf(config.name,config.size));
			//TODO: show size in bytes with commas
		}
	}

	public bool restore_packages(bool no_prompt) {
		if (!App.check_backup_file("packages.list")) {
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
				Posix.system("apt-get%s install %s".printf((no_prompt) ? " -y" : "", App.pkg_list_install));
			}
			if (App.pkg_list_deb.length > 0){
				log_msg(_("Following packages will be installed") + ":\n%s\n".printf(App.pkg_list_deb));
				Posix.system("gdebi%s %s".printf((no_prompt) ? " -n" : "", App.gdebi_file_list));
			}
		}

		return true;
	}

	public bool restore_ppa() {
		if (!App.check_backup_file("ppa.list")) {
			return false;
		}

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

		return true;
	}
}

