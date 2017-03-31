/*
 * Archive.vala
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

public class Archive : GLib.Object {
	//compression
	public string format = "7z";
	public string method = "lzma";
	public string level = "5";
	public string dict_size = "16m";
	public string word_size = "32";
	public string block_size = "2g";
	public string passes = "0";
	public bool tar_before = true;

	//encryption
	public bool encrypt_archive = false;
	public bool encrypt_header = false;
	public string encrypt_method = "AES256";
	public string password = "";
	public string keyfile = "";
	public bool archive_is_encrypted = false;
	
	//output
	public string archive_path = "";
	public int64 archive_size = 0;
	public int64 archive_unpacked_size = 0;
	public double compression_ratio = 0.0;
	public string extraction_path = "";
	public string archive_type = "";
	public string archive_method = "";
	public bool archive_is_solid = false;
	public int archive_blocks = 0;
	public int64 archive_header_size = 0;
	public DateTime archive_modified;
	
	//input files
	public FileItem base_archive;

	//temp
	public string temp_dir = "";
	public string script_file;
	public string log_file = "";
	
	public ArchiveAction action = ArchiveAction.CREATE;
	public string archiver_name;
	public string parser_name;
	
	// extension groups ------------
	
	public static string[] extensions_tar = {
		".tar"
	};
	
	public static string[] extensions_tar_compressed = {
		".tar.gz", ".tgz",
		".tar.bzip2",".tar.bz2", ".tbz", ".tbz2", ".tb2",
		".tar.lzma", ".tar.lz", ".tlz",
		".tar.xz", ".txz"
	};

	public static string[] extensions_tar_packed = {
		".tar.7z",
		".tar.zip",
		".deb"
	};

	public static string[] extensions_7z_unpack = {
		".7z", ".lzma",
		".bz2", ".bzip2",
		".gz", ".gzip",
		".zip", ".rar", ".cab", ".arj", ".z", ".taz", ".cpio",
		".rpm", ".deb",
		".lzh", ".lha",
		".chm", ".chw", ".hxs",
		".iso", ".dmg", ".dar", ".xar", ".hfs", ".ntfs", ".fat", ".vhd", ".mbr",
		".wim", ".swm", ".squashfs", ".cramfs", ".scap"
	};
				
	// constructors -------------------
	
	public Archive() {
		base_archive = new FileItem.base_archive(this);
	}
	
	public Archive.from_file(string file_path) {
		base_archive = new FileItem.base_archive(this);
		archive_path = file_path;
	}
	
	// prepare -----------------------------------
	
	public void prepare() {
		temp_dir = TEMP_DIR + "/" + timestamp2() + "%ld".printf(Random.next_int()); //TODO: update for other apps
		log_file = temp_dir + "/log.txt";
		script_file = temp_dir + "/convert.sh";
		dir_create (temp_dir);

		string script_text = build_script();
		save_script(script_text);
	}

	public int read_status(){
		var path = temp_dir + "/status";
		var f = File.new_for_path(path);
		if (f.query_exists()){
			var txt = file_read(path);
			return int.parse(txt);
		}
		return -1;
	}
	
	// build command strings -----------------------------
	
	private string build_script() {
		var script = new StringBuilder();
		script.append ("#!/bin/bash\n");
		script.append ("\n");
		script.append ("LANG=C\n");
		script.append ("\n");
		
		switch (action) {
		case ArchiveAction.CREATE:
			script.append("if [ -f '%s' ]; then\n".printf(archive_path));
			script.append("  rm '%s'\n".printf(archive_path));
			script.append("fi\n");
			
			if (file_exists(archive_path + ".tmp")) {
				script.append("rm '%s.tmp'\n".printf(archive_path));
			}
			script.append(get_commands_compress());
			break;

		case ArchiveAction.LIST:
			script.append(get_commands_list());
			break;

		case ArchiveAction.INFO:
			script.append(get_commands_list_archive_info());
			break;
			
		case ArchiveAction.EXTRACT:
			script.append(get_commands_extract());
			break;
		}

		script.append ("\n\nexitCode=$?\n");
		script.append ("echo ${exitCode} > ${exitCode}\n");
		script.append ("echo ${exitCode} > status\n");
		return script.str;
	}

	private void save_script (string script_text) {
		try {
			// create new script file
			var file = File.new_for_path(script_file);
			var file_stream = file.create(FileCreateFlags.REPLACE_DESTINATION);
			var data_stream = new DataOutputStream(file_stream);
			data_stream.put_string(script_text);
			data_stream.close();

			//set execute permission
			chmod(script_file, "u+x");
		}
		catch (Error e) {
			log_error (e.message);
		}
	}
	
	public string get_commands_compress() {
		string cmd = "";

		if (format == "tar") {
			cmd += "tar cvf";
			cmd += " '%s'".printf(archive_path);
			foreach (string key in base_archive.children.keys) {
				var item = base_archive.children[key];
				cmd += " -C '%s'".printf(file_parent(item.file_path));
				cmd += " '%s'".printf(file_basename(item.file_path));
			}

			parser_name = "tar";
			archiver_name = "tar";
			
			return cmd;
		}

		//tar options
		if (tar_before) {
			cmd += "tar cf -";
			foreach (string key in base_archive.children.keys) {
				var item = base_archive.children[key];
				cmd += " -C '%s'".printf(file_parent(item.file_path));
				cmd += " '%s'".printf(file_basename(item.file_path));
			}
			cmd += " | ";
			cmd += "pv --size %lld -n".printf(base_archive.size);
			cmd += " | ";

			parser_name = "pv";
		}

		//main archiver options
		switch (format) {
		case "7z":
		case "bz2":
		case "gz":
		case "xz":
		case "zip":
			cmd += "7z a -bd";
			if (encrypt_archive && (password.length > 0)) {
				cmd += " '-p%s'".printf(password);
				if (encrypt_header) {
					cmd += " -mhe";
				}
			}
			parser_name = "7z";
			archiver_name = "7z";
			break;
		case "tar":
			cmd += "tar cvf";
			parser_name = "tar";
			archiver_name = "tar";
			break;
		}

		//format and method
		switch (format) {
		case "7z":
			cmd += " -t7z";
			cmd += " -m0=" + method; //format supports multiple methods
			break;
		case "bz2":
			cmd += " -tBZip2";
			//default method: bzip2
			break;
		case "gz":
			cmd += " -tGZip";
			//default method: deflate
			break;
		case "xz":
			cmd += " -tXZ";
			//default method: lzma2
			break;
		case "zip":
			cmd += " -tZip";
			cmd += " -mm=" + method; //format supports multiple methods
			break;
		case "tar":
			//no options
			break;
		}

		//multi-threading
		switch (format) {
		case "7z":
		case "bz2":
		case "xz":
			cmd += " -mmt=on";
			break;
		case "gz":
		case "zip":
			//not supported
			break;
		}

		switch (method) {
		case "lzma":
		case "lzma2":
			cmd += " -mx" + level;
			cmd += " -md=" + dict_size;
			cmd += " -mfb=" + word_size;
			break;

		case "ppmd":
			cmd += " -mmem=" + dict_size;
			cmd += " -mo=" + word_size;
			break;

		case "bzip2":
			cmd += " -mx" + level;
			cmd += " -md=" + dict_size;
			cmd += " -mpass=" + passes;
			break;

		case "deflate":
		case "deflate64":
			cmd += " -mx" + level;
			cmd += " -mfb=" + word_size;
			cmd += " -mpass=" + passes;
			break;

		case "copy":
			//no options
			break;
		}

		//solid blocks
		switch (format) {
		case "7z":
			switch (method) {
			case "lzma":
			case "lzma2":
			case "ppmd":
			case "bzip2":
				if (block_size == "non-solid") {
					cmd += " -ms=off";
				}
				else {
					cmd += " -ms=" + block_size;
				}
				break;
			case "copy":
			case "deflate":
			case "deflate64":
				//not supported
				break;
			}
			break;

		default:
			//not supported
			break;
		}

		//output file
		if (archive_path.length > 0) {
			cmd += " '-w%s'".printf(file_parent(archive_path));
			cmd += " '%s'".printf(archive_path);
		}

		//input files
		if (tar_before) {
			cmd += " -si";
		}
		else {
			foreach (string key in base_archive.children.keys) {
				var item = base_archive.children[key];
				cmd += " '%s'".printf(item.file_path);
			}
		}

		return cmd;
	}

	public string get_commands_list_archive_info() {
		string cmd = "";

		/*
		foreach(string extension in Main.extensions_tar_compressed) {
			if (archive_path.has_suffix(extension)) {
				cmd += "7z l -slt '%s'".printf(archive_path);
			}
		}

		
		if (cmd.length == 0) {
			foreach(var extension in Main.extensions_tar_packed) {
				if (archive_path.has_suffix(extension)) {
					string file_title = file_basename(archive_path);

					if (archive_path.has_suffix(".deb")) {
						file_title = "data";
					}
					else {
						foreach(var ext in Main.extensions_tar_packed) {
							if (file_title.has_suffix(ext)){
								file_title = file_title.replace(ext, "");
							}	
						}
					}

					//cmd += "7z x '%s' '-o%s' '-w%s'\n".printf(archive_path, temp_dir, temp_dir);
					//cmd += "7z l -slt '%s/%s.tar'".printf(temp_dir, file_title);
				}
			}
		}

		if (cmd.length == 0) {
			foreach(string extension in Main.extensions_7z_unpack) {
				if (archive_path.has_suffix(extension)) {
					//cmd += "7z l '%s'".printf(archive_path);

					//parser_name = "7z_list";
					//archiver_name = "7z";
				}
			}
		}
		*/

		cmd += "7z l -slt '%s'".printf(archive_path);
		parser_name = "7z_list";
		archiver_name = "7z";
				
		return cmd;
		
		//string cmd = get_commands_list();
		//change parser
		//parser_name = parser_name.replace("list","info");
		//return cmd;
	}
	
	public string get_commands_list() {
		string cmd = "";

		foreach(string extension in array_concat(extensions_tar_compressed,extensions_tar)) {
			if (archive_path.has_suffix(extension)) {
				cmd += "tar tvf '%s'".printf(archive_path);
				parser_name = "tar_list";
				archiver_name = "tar";
			}
		}

		if (cmd.length == 0) {
			foreach(var extension in extensions_tar_packed) {
				if (archive_path.has_suffix(extension)) {
					string file_title = file_basename(archive_path);

					if (archive_path.has_suffix(".deb")) {
						file_title = "data";
					}
					else {
						foreach(var ext in extensions_tar_packed) {
							if (file_title.has_suffix(ext)){
								file_title = file_title.replace(ext, "");
							}	
						}
					}

					cmd += "7z x '%s' '-o%s' '-w%s' -p --\n".printf(archive_path, temp_dir, temp_dir);
					cmd += "tar tvf '%s/%s.tar'".printf(temp_dir, file_title);

					parser_name = "tar_list";
					archiver_name = "tar";
				}
			}
		}

		if (cmd.length == 0) {
			foreach(string extension in extensions_7z_unpack) {
				if (archive_path.has_suffix(extension)) {
					cmd += "7z l '%s'".printf(archive_path);

					if ((password.length > 0)||(keyfile.length > 0)){
						cmd += " '-p%s'".printf(password);
					}
					else{
						cmd += " -p --"; //required for non-encrypted archives
					}
					
					parser_name = "7z_list";
					archiver_name = "7z";
				}
			}
		}
		
		//log_msg(cmd);

		return cmd;
	}

	public string get_commands_extract() {
		string cmd = "";

		foreach(string extension in array_concat(extensions_tar_compressed, extensions_tar)) {
			if (archive_path.has_suffix(extension)) {
				cmd += "tar xvf '%s' -C '%s'".printf(archive_path, extraction_path);
				parser_name = "tar";
				archiver_name = "tar";
			}
		}

		if (cmd.length == 0) {
			foreach(string extension in extensions_tar_packed) {
				if (archive_path.has_suffix(extension)) {
					string file_title = file_basename(archive_path);

					if (archive_path.has_suffix(".deb")) {
						file_title = "data";
					}
					else {
						foreach(var ext in extensions_tar_packed) {
							if (file_title.has_suffix(ext)){
								file_title = file_title.replace(ext, "");
							}	
						}
					}

					cmd += "7z x '%s' '-o%s' '-w%s'\n".printf(archive_path, temp_dir, temp_dir);
					cmd += "tar xvf '%s/%s.tar' -C '%s'".printf(temp_dir, file_title, extraction_path);

					parser_name = "tar";
					archiver_name = "tar";
				}
			}
		}

		if (cmd.length == 0) {
			foreach(string extension in extensions_7z_unpack) {
				if (archive_path.has_suffix(extension)) {
					cmd += "7z x '%s' '-o%s' '-w%s'\n".printf(archive_path, extraction_path, extraction_path);
					parser_name = "7z";
					archiver_name = "7z";
				}
			}
		}

		return cmd;
	}

	public Json.Object to_json() {
		var task = new Json.Object();
		task.set_string_member("format", format);
		task.set_string_member("method", method);
		task.set_string_member("level", level);
		task.set_string_member("dict_size", dict_size);
		task.set_string_member("word_size", word_size);
		task.set_string_member("block_size", block_size);
		task.set_string_member("passes", passes);
		task.set_string_member("tar_before", tar_before.to_string());
		task.set_string_member("encrypt_archive", encrypt_archive.to_string());
		task.set_string_member("encrypt_header", encrypt_header.to_string());
		task.set_string_member("encrypt_method", encrypt_method);
		//task.set_string_member("password", password);
		return task;
	}

	public void load_from_json(Json.Object task) {
		format = json_get_string(task, "format", "7z");
		method = json_get_string(task, "method", "lzma");
		level = json_get_string(task, "level", "5");
		dict_size = json_get_string(task, "dict_size", "16m");
		word_size = json_get_string(task, "word_size", "32");
		block_size = json_get_string(task, "block_size", "2g");
		passes = json_get_string(task, "passes", "");
		tar_before = json_get_bool(task, "tar_before", false);
		encrypt_archive = json_get_bool(task, "encrypt_archive", false);
		encrypt_header = json_get_bool(task, "encrypt_header", false);
		encrypt_method = json_get_string(task, "encrypt_method", "AES256");
	}

	// actions ----------------------
	
	public void open(bool wait = false) {
		log_msg("Opening: %s".printf(archive_path));
		
		//task = new Archive();
		//task.archive_path = archive_file_path;
	
		foreach(string ext in extensions_tar_compressed){
			if (archive_path.has_suffix(ext)){
				//get task.archive_unpacked_size and set App.progress_total
				//get_info();
				break;
			}
		}

		if (archive_path.length > 0) {
			var file = File.parse_name (archive_path);
			if (file.query_exists()) {
				try {
					var finfo = file.query_info("%s,%s".printf(FileAttribute.STANDARD_SIZE,
					FileAttribute.TIME_MODIFIED), 0);

					archive_size = finfo.get_size();
					archive_modified = (new DateTime.from_timeval_utc(finfo.get_modification_time())).to_local();
				}
				catch (Error e) {
					log_msg("error:open()");
					log_error(e.message);
				}
			}
		}
		
		action = ArchiveAction.LIST;
		base_archive = new FileItem.base_archive(this, file_basename(archive_path));
		
		var archiver = new Archiver();
		archiver.execute(this, wait);
	}
	
	public void get_info() {
		if (archive_path.length > 0) {
			var file = File.parse_name (archive_path);
			if (file.query_exists()) {
				try {
					var finfo = file.query_info("%s,%s".printf(FileAttribute.STANDARD_SIZE,
					FileAttribute.TIME_MODIFIED), 0);

					archive_size = finfo.get_size();
					archive_modified = (new DateTime.from_timeval_utc(finfo.get_modification_time())).to_local();
				}
				catch (Error e) {
					log_error(e.message);
				}
			}
		}

		action = ArchiveAction.INFO;
		base_archive = new FileItem.base_archive(this, file_basename(archive_path));
		
		var archiver = new Archiver();
		archiver.execute(this, true);
	}
}

public enum ArchiveAction {
	CREATE,
	UPDATE,
	LIST,
	TEST,
	EXTRACT,
	INFO
}

