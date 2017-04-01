/*
 * Archiver.vala
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

public class Archiver : GLib.Object {

	private MatchInfo match;
	private double dblVal;
	//private uint shutdownTimerID;

	private Pid procID;
	private int archiverPID;
	private string errLine = "";
	private string outLine = "";
	private string tempLine;
	private DataInputStream dis_out;
	private DataInputStream dis_err;
	private DataOutputStream dos_log;
	public int exit_code = 0;

	public string currentLine;
	public string statusLine;
	public double progress;
	//public double progressPercent;
	public GLib.Timer timer;

	public string proc_io_name;

	public int64 proc_read_bytes;
	public int64 proc_write_bytes;
	public int64 archive_file_size;
	public int64 processed_bytes;
	public int64 compressed_bytes;
	public long processed_file_count;
	public double compression_ratio;

	public AppStatus status;
	public bool backgroundMode = false;
	//public string parser_name;
	//public bool execute_for_info = false;

	private Gee.HashMap<string, Regex> regex_list;
	private Archive task;

	Pid child_pid;
	int input_fd;
	int output_fd;
	int error_fd;
		
	public Archiver() {
		regex_list = new Gee.HashMap<string, Regex>();

		// init regular expressions

		try {
			//Example: Compressing  packages/option.d.ts 100%
			regex_list["7z"] = new Regex("""[^ \t]+[ ]+(.*)""");

			//Example: atom/keymap.cson
			regex_list["tar"] = new Regex("""^(.*)$""");
			
			//Example: 10
			regex_list["pv"] = new Regex("""([0-9]+)""");

			//Example: drwxrwxr-x teejee/teejee     0 2015-10-19 10:05 atom/node-uuid/uuid.js
			regex_list["tar_list"] = new Regex("""^([^ \t]{1})([^ \t]*)[ \t]+([^ \t\/]+)\/([^ \t\/]+)[ \t]+([0-9]+)[ \t]+([0-9-]+)[ \t]+([0-9:]+)[ \t]+(.+)$""");

			//Example: 2015-10-19 10:05:22 D....            0            0  atom/.apm/agent-base
			regex_list["7z_list"] = new Regex("""^([0-9-]+)[ \t]+([0-9:]+)[ \t]+([^ \t]+)[ \t]+([0-9]*)[ \t]+([0-9]*)[ \t]+(.+)$""");
		}
		catch (Error e) {
			log_error (e.message);
		}
	}

	public void execute(Archive task, bool wait = false) {
		//log_msg("Executing action on archive: %s".printf(task.archive_path));
		this.task = task;
		task.prepare();
		status = AppStatus.RUNNING;
		
		try {
			Thread.create<void>(execute_thread, true);
		} catch (ThreadError e) {
			log_error(e.message);
		}
		
		if (wait){
			while(status == AppStatus.RUNNING){
				sleep(500);
				gtk_do_events();
			}
		}
	}

	/*public void execute_for_info(Archive _task){
		task = _task;
		
		string stdout = execute_command_sync_get_output(task.get_commands_list_archive_info());

		log_msg(stdout);
		foreach(string line in stdout.split("\n")){
			update_progress_parse_console_output(line);
		}
	}*/
	
	private void execute_thread() {
		string[] argv = new string[1];
		argv[0] = task.script_file;


		//log_msg(read_file(task.script_file));
		

		try {

			//init progress variables ----------------

			proc_read_bytes = 0;
			proc_write_bytes = 0;
			archive_file_size = 0;
			processed_bytes = 0;
			compressed_bytes = 0;
			processed_file_count = 0;
			compression_ratio = 0.0;
			
			statusLine = "";
			currentLine = "";
			tempLine = "";

			//execute script file ---------------------

			archiverPID = -1;

			timer = timer_start();

			Process.spawn_async_with_pipes(
			    task.temp_dir, //working dir
			    argv, //argv
			    null, //environment
			    SpawnFlags.SEARCH_PATH,
			    null,   // child_setup
			    out child_pid,
			    out input_fd,
			    out output_fd,
			    out error_fd);

			procID = child_pid;

			int attempts = 0;
			while ((archiverPID == -1) && (attempts < 10)) {
				sleep(100);
				archiverPID = get_pid_by_command(task.archiver_name);
				attempts++;
			}
			
			//log_msg("pid=%d,attempts=%d,archiver=%s".printf(archiverPID, attempts, task.archiver_name));

			set_priority();

			//create stream readers
			UnixInputStream uis_out = new UnixInputStream(output_fd, false);
			UnixInputStream uis_err = new UnixInputStream(error_fd, false);
			dis_out = new DataInputStream(uis_out);
			dis_err = new DataInputStream(uis_err);
			dis_out.newline_type = DataStreamNewlineType.ANY;
			dis_err.newline_type = DataStreamNewlineType.ANY;

			//create log file
			var file = File.new_for_path(task.log_file);
			var file_stream = file.create(FileCreateFlags.REPLACE_DESTINATION);
			dos_log = new DataOutputStream(file_stream);
			
			//start another thread for reading error stream
			try {
				Thread.create<void> (read_std_err, true);
			}
			catch (Error e) {
				log_error (e.message);
			}

			//start reading output stream in current thread
			outLine = dis_out.read_line (null);
			while (outLine != null) {
				update_progress_parse_console_output (outLine.strip());
				//dos_log.put_string (outLine + "\n");
				outLine = dis_out.read_line (null);
			}

			// cleanup -----------------

			// dispose stdout
			GLib.FileUtils.close(output_fd);
			dis_out.close();
			dis_out = null;

			// dispose stdin
			GLib.FileUtils.close(input_fd);

			// dispose child process
			Process.close_pid(child_pid); //required on Windows, doesn't do anything on Unix

			Thread.usleep ((ulong) 0.1 * 1000000);
			
			dos_log.close();
			dos_log = null;
			
			if (task.action == ArchiveAction.LIST){
				task.archive_size = file_get_size(task.archive_path);
				task.compression_ratio = (task.archive_size * 100.00) / task.base_archive.size;
			}
			
			timer.stop();

			if (status != AppStatus.CANCELLED) {
				status = AppStatus.FINISHED;
			}
		}
		catch (Error e) {
			log_error (e.message);
		}
	}

	private void read_std_err() {
		try {
			errLine = dis_err.read_line (null);
			while (errLine != null) {
				update_progress_parse_console_output(errLine.strip());
				dos_log.put_string (errLine + "\n");
				errLine = dis_err.read_line (null);
			}

			dis_err.close();
			dis_err = null;
			GLib.FileUtils.close(error_fd);
		}
		catch (Error e) {
			log_error (e.message);
		}
	}

	public bool update_progress_parse_console_output (string line = "") {
		tempLine = line;

		if ((tempLine == null) || (tempLine.length == 0)) {
			return true;
		}
		//if (tempLine.index_of ("overread, skip") != -1){ return true; }
		
		
		switch (task.parser_name) {
		case "pv":
			if (regex_list[task.parser_name].match(tempLine, 0, out match)) {
				dblVal = double.parse(match.fetch(1));
				progress = (dblVal / 100.00);
			}
			break;

		case "7z":
			if (regex_list[task.parser_name].match(tempLine, 0, out match)) {
				statusLine = match.fetch(1);
				if (!statusLine.has_suffix("/")){
					processed_file_count += 1;
				}
			}
			break;

		case "tar":
			if (regex_list[task.parser_name].match(tempLine, 0, out match)) {
				statusLine = match.fetch(1);
				if (!statusLine.has_suffix("/")){
					processed_file_count += 1;
				}
			}
			break;
			
		case "tar_list":
			//Example: (d)(rwxrwxr-x) (teejee)/(teejee)     (0) (2015-10-19) (10:05) (atom/node-uuid/uuid.js)
			
			if (regex_list[task.parser_name].match(tempLine, 0, out match)) {
				string type = match.fetch(1).strip();
				string permissions = match.fetch(2).strip();
				string owner = match.fetch(3).strip();
				string group = match.fetch(4).strip();
				string size = match.fetch(5).strip();
				string modified = "%s %s".printf(match.fetch(6).strip(), match.fetch(7).strip());
				string last_field = match.fetch(8).strip();
				string symlink_target = "";
				string file_path = "";

				if (last_field.contains("->")) {
					file_path = last_field.split("->")[0].strip();
					symlink_target = last_field.split("->")[1].strip();
				}
				else {
					file_path = last_field;
				}

				if (file_path.has_prefix("./")) {
					if (file_path.length > 2) {
						file_path = file_path[2:file_path.length].strip();
					}
					else {
						file_path = "";
					}
				}

				if (file_path.length > 0) {
					int64 item_size = int64.parse(size);
					var item = task.base_archive.add_descendant(file_path, FileType.REGULAR, item_size, 0);
					item.modified = datetime_from_string(modified);
					item.permissions = permissions;
					item.owner = owner;
					item.group = group;
					item.symlink_target = symlink_target;
					item.is_symlink = (type == "l");
				}
			}
			else if (tempLine.contains("Wrong password?")){
				task.archive_is_encrypted = true;
			}
			
			break;

		case "7z_list":

			if (regex_list[task.parser_name].match(tempLine, 0, out match)) {
				string modified = "%s %s".printf(match.fetch(1).strip(), match.fetch(2).strip());
				string attr = match.fetch(3).strip();
				string size = match.fetch(4).strip();
				string size_compressed = match.fetch(5).strip();
				string file_path = match.fetch(6).strip();

				var file_type = (attr.contains("D")) ? FileType.DIRECTORY : FileType.REGULAR;
				var item = task.base_archive.add_descendant(file_path, file_type, int64.parse(size), int64.parse(size_compressed));
				item.modified = datetime_from_string(modified);
			}
			else if (tempLine.down().contains("wrong password?")){
				task.archive_is_encrypted = true;
			}
			else if (tempLine.contains("=")){
				if (tempLine.has_prefix("Type = ")){
					string val = tempLine.split("=")[1];
					val = (val == null) ? "" : val.strip();
					task.archive_type = val;
				}
				else if (tempLine.has_prefix("Method = ")){
					string val = tempLine.split("=")[1];
					val = (val == null) ? "" : val.strip();
					task.archive_method = val;
				}
				else if (tempLine.has_prefix("Solid = ")){
					string val = tempLine.split("=")[1];
					val = (val == null) ? "" : val.strip();
					task.archive_is_solid = (val == "+") ? true : false;
				}
				else if (tempLine.has_prefix("Blocks = ")){
					string val = tempLine.split("=")[1];
					val = (val == null) ? "0" : val.strip();
					task.archive_blocks = int.parse(val);
				}
				else if (tempLine.has_prefix("Headers Size = ")){
					string val = tempLine.split("=")[1];
					val = (val == null) ? "0" : val.strip();
					task.archive_header_size = int64.parse(val);
				}
				else if (tempLine.has_prefix("Size = ")){
					string val = tempLine.split("=")[1];
					val = (val == null) ? "0" : val.strip();
					task.archive_unpacked_size = int64.parse(val);

					if ((task.action == ArchiveAction.INFO) || (task.action == ArchiveAction.LIST)){
						App.progress_total = task.archive_unpacked_size;
						log_msg("archive unpacked size: %'ld bytes".printf(task.archive_unpacked_size));
					}

					if (task.action == ArchiveAction.INFO){
						stop(); //TODO: stop after last line in archive info
					}
				}
				else if (tempLine.has_prefix("Packed Size = ")){
					string val = tempLine.split("=")[1];
					val = (val == null) ? "0" : val.strip();
					task.archive_size = int64.parse(val);
				}
			}
			break;

		case "tar_info":
			
			break;
		}

		/*else {
			statusLine = tempLine;
			try{
				dos_log.put_string (tempLine + "\n");
			}
			catch (Error e) {
				log_error (e.message);
			}
		}*/

		/*if (progress < 1) {
			progressPercent = (double)(progress * 100);
		}
		else{
			progressPercent = 100;
		}*/

		return true;
	}

	public bool update_progress_query_io_stats () {
		if (archiverPID > 0) {
			get_proc_io_stats(archiverPID, out proc_read_bytes, out proc_write_bytes);

			//statusLine = "Processed: %s, Written: %s".printf(
			//	format_file_size(proc_read_bytes),
			//	format_file_size(proc_write_bytes));
			progress = (proc_read_bytes * 1.0) / task.base_archive.size;
			//log_msg(statusLine);
		}

		return true;
	}

	public void pause() {
		Pid childPid;
		foreach (long pid in get_process_children (procID)) {
			childPid = (Pid) pid;
			process_pause (childPid);
		}

		status = AppStatus.PAUSED;
	}

	public void resume() {
		Pid childPid;
		foreach (long pid in get_process_children (procID)) {
			childPid = (Pid) pid;
			process_resume (childPid);
		}

		status = AppStatus.RUNNING;
	}

	public void stop() {
		// we need to un-freeze the processes before we kill them
		if (status == AppStatus.PAUSED) {
			resume();
		}

		process_kill(procID);

		status = AppStatus.CANCELLED;
	}

	public void set_priority() {
		int prio = 0;
		if (backgroundMode) {
			prio = 5;
		}

		Pid appPid = Posix.getpid();
		process_set_priority (appPid, prio);

		if (status == AppStatus.RUNNING) {
			process_set_priority (procID, prio);

			Pid childPid;
			foreach (long pid in get_process_children (procID)) {
				childPid = (Pid) pid;

				if (backgroundMode)
					process_set_priority (childPid, prio);
				else
					process_set_priority (childPid, prio);
			}
		}
	}
}

public enum AppMode {
	NEW,
	CREATE,
	OPEN,
	TEST,
	EXTRACT
}


