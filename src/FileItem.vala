/*
 * FileItem.vala
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

public class FileItem : GLib.Object {
	public string file_name = "";
	public string file_location = "";
	public string file_path = "";
	public FileType file_type = FileType.REGULAR;
	public DateTime modified;

	public bool is_symlink = false;
	public string symlink_target = "";

	public FileItem parent;
	public Gee.HashMap<string, FileItem> children;
	public Archive task_ref;
	
	public long file_count = 0;
	public long dir_count = 0;
	private int64 _size = 0;
	private int64 _size_compressed = 0;

	public long file_count_total = 0;
	public long dir_count_total = 0;

	public string permissions = "";
	public string owner = "";
	public string group = "";

	//public string icon_name = "gtk-file";
	public GLib.Icon icon;

	public bool is_dummy = false;

	public void init() {
		children = new Gee.HashMap<string, FileItem>();
	}

	public FileItem.base_archive(Archive _task_ref, string name = "New Archive") {
		init();
		file_name = name;
		task_ref = _task_ref;
	}

	public FileItem.dummy(Archive _task_ref, FileType _file_type) {
		init();
		is_dummy = true;
		file_type = _file_type;
		task_ref = _task_ref;
	}

	//private
	private FileItem.from_path_and_type(Archive _task_ref, string _file_path, FileType _file_type) {
		init();

		file_path = _file_path;
		file_name = file_basename(_file_path);
		file_location = file_parent(_file_path);
		file_type = _file_type;
		task_ref = _task_ref;
	}

	public int64 size {
		get{
			return _size;
		}
	}

	public int64 size_compressed {
		get{
			return _size_compressed;
		}
	}

	public FileItem add_child(string item_file_path, FileType item_file_type, int64 item_size, int64 item_size_compressed) {
		//create item
		var item = new FileItem.from_path_and_type(this.task_ref, item_file_path, item_file_type);

		//set parent and child
		item.parent = this;
		this.children[item.file_name] = item;

		if (item_file_type == FileType.REGULAR) {

			//set file sizes
			if (item_size > 0) {
				item._size = item_size;
			}
			if (item_size_compressed > 0) {
				item._size_compressed = item_size_compressed;
			}

			//update file counts
			this.file_count++;
			this.file_count_total++;
			this._size += item_size;
			this._size_compressed += item_size_compressed;

			//update file count and size of parent dirs
			var temp = this;
			while (temp.parent != null) {
				temp.parent.file_count_total++;
				temp.parent._size += item_size;
				temp.parent._size_compressed += item_size_compressed;
				temp = temp.parent;
			}

			try {
				item.icon = GLib.Icon.new_for_string("gtk-file");
			}
			catch (Error e) {
				log_error (e.message);
			}
		}
		else {
			//update dir counts
			this.dir_count++;
			this.dir_count_total++;
			//this.size += _size; //size will be updated when children are added

			//update dir count of parent dirs
			var temp = this;
			while (temp.parent != null) {
				temp.parent.dir_count_total++;
				temp = temp.parent;
			}

			try {
				item.icon = GLib.Icon.new_for_string("gtk-directory");
			}
			catch (Error e) {
				log_error (e.message);
			}
		}

		//log_debug("%3ld %3ld %s".printf(file_count, dir_count, file_path));

		return item;
	}

	public FileItem remove_child(string child_name) {
		FileItem child = null;

		if (this.children.has_key(child_name)) {
			child = this.children[child_name];
			this.children.unset(child_name);

			if (child.file_type == FileType.REGULAR) {
				//update file counts
				this.file_count--;
				this.file_count_total--;

				//subtract child size
				this._size -= child.size;
				this._size_compressed -= child.size_compressed;

				//update file count and size of parent dirs
				var temp = this;
				while (temp.parent != null) {
					temp.parent.file_count_total--;

					temp.parent._size -= child.size;
					temp.parent._size_compressed -= child.size_compressed;

					temp = temp.parent;
				}
			}
			else {
				//update dir counts
				this.dir_count--;
				this.dir_count_total--;

				//subtract child counts
				this.file_count_total -= child.file_count_total;
				this.dir_count_total -= child.dir_count_total;
				this._size -= child.size;
				this._size_compressed -= child.size_compressed;

				//update dir count of parent dirs
				var temp = this;
				while (temp.parent != null) {
					temp.parent.dir_count_total--;

					temp.parent.file_count_total -= child.file_count_total;
					temp.parent.dir_count_total -= child.dir_count_total;
					temp.parent._size -= child.size;
					temp.parent._size_compressed -= child.size_compressed;

					temp = temp.parent;
				}
			}
		}

		//log_debug("%3ld %3ld %s".printf(file_count, dir_count, file_path));

		return child;
	}

	public FileItem add_child_from_disk(string item_file_path) {
		FileItem item = null;

		try {
			FileEnumerator enumerator;
			FileInfo info;
			File file = File.parse_name (item_file_path);

			GLib.Icon item_icon = null;
			FileType item_file_type_actual = FileType.REGULAR;
			FileType item_file_type_resolved = FileType.REGULAR;
			bool item_is_symlink = false;
			int64 item_size = 0;
			DateTime item_modified = null;
			string item_target = "";
			
			if (file.query_exists()) {

				//get type without following symlinks
				info = file.query_info("%s,%s,%s".printf(
				                           FileAttribute.STANDARD_TYPE,
				                           FileAttribute.STANDARD_ICON,
				                           FileAttribute.STANDARD_SYMLINK_TARGET),
				                       FileQueryInfoFlags.NOFOLLOW_SYMLINKS);

				item_file_type_actual = info.get_file_type();
				if (item_file_type_actual == FileType.SYMBOLIC_LINK) {
					item_icon = GLib.Icon.new_for_string("emblem-symbolic-link");
					item_is_symlink = true;
					item_target = info.get_symlink_target();
				}
				else {
					item_icon = info.get_icon();
					item_is_symlink = false;
				}

				//get file info - follow symlinks
				info = file.query_info("%s,%s,%s".printf(
				                           FileAttribute.STANDARD_TYPE,
				                           FileAttribute.STANDARD_SIZE,
				                           FileAttribute.TIME_MODIFIED), 0);

				//get type
				item_file_type_resolved = info.get_file_type();

				//get size
				if (!item_is_symlink && (item_file_type_resolved == FileType.REGULAR)) {
					item_size = info.get_size();
				}

				//get modified date
				item_modified = (new DateTime.from_timeval_utc(info.get_modification_time())).to_local();

				//add item
				item = this.add_child(item_file_path, item_file_type_resolved, item_size, 0);
				item.icon = item_icon;
				item.is_symlink = item_is_symlink;
				item.symlink_target = item_target;
				item.modified = item_modified;

				if ((item.file_type == FileType.DIRECTORY) && !item.is_symlink) {
					//recurse children
					enumerator = file.enumerate_children ("%s".printf(FileAttribute.STANDARD_NAME), 0);
					while ((info = enumerator.next_file()) != null) {
						string child_path = "%s/%s".printf(item_file_path, info.get_name());
						item.add_child_from_disk(child_path);
					}
				}
			}
		}
		catch (Error e) {
			log_error (e.message);
		}

		return item;
	}

	public FileItem add_descendant(string file_path, FileType ? _file_type, int64 item_size, int64 item_size_compressed) {
		string item_path = file_path.strip();
		FileType item_type = (_file_type == null) ? FileType.REGULAR : _file_type;

		if (item_path.has_suffix("/")) {
			item_path = item_path[0:item_path.length - 1];
			item_type = FileType.DIRECTORY;
		}

		string dir_name = "";
		string dir_path = "";

		//create dirs and find parent dir
		FileItem current_dir = this;
		string[] arr = item_path.split("/");
		for (int i = 0; i < arr.length - 1; i++) {
			//get dir name
			dir_name = arr[i];

			//add dir
			if (!current_dir.children.keys.contains(dir_name)) {
				dir_path = (current_dir.parent == null) ? "" : current_dir.file_path + "/";
				dir_path = "%s%s".printf(dir_path, dir_name);
				current_dir.add_child(dir_path, FileType.DIRECTORY, 0, 0);
			}

			current_dir = current_dir.children[dir_name];
		}

		//get item name
		string item_name = arr[arr.length - 1];

		//add item
		if (!current_dir.children.keys.contains(item_name)) {
			current_dir.add_child(item_path, item_type, item_size, item_size_compressed);
		}

		return current_dir.children[item_name];
	}

	public void print(int level) {

		if (level == 0) {
			stdout.printf("\n");
			stdout.flush();
		}

		stdout.printf("%s%s\n".printf(string.nfill(level * 2, ' '), file_name));
		stdout.flush();

		foreach (var key in this.children.keys) {
			this.children[key].print(level + 1);
		}
	}
}



