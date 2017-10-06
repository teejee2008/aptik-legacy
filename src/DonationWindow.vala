/*
 * DonationWindow.vala
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

using Gtk;

using TeeJee.Logging;
using TeeJee.FileSystem;
using TeeJee.JSON;
using TeeJee.ProcessManagement;
using TeeJee.System;
using TeeJee.Misc;
using TeeJee.GtkHelper;

public class DonationWindow : Dialog {
	
	public DonationWindow() {
		
		set_title("");
		window_position = WindowPosition.CENTER_ON_PARENT;
		set_destroy_with_parent (true);
		set_modal (true);
		set_deletable(true);
		set_skip_taskbar_hint(false);
		set_default_size (500, 20);
		icon = get_app_icon(16);

		//vbox_main
		Box vbox_main = get_content_area();
		vbox_main.margin = 6;
		vbox_main.spacing = 6;
		vbox_main.homogeneous = false;

		get_action_area().visible = false;

		// label
		var label = new Gtk.Label("");
		string msg = _("This application was created for my own use. I work on it during my free time based on my own requirements and interest. I'm distributing it in the hope that it will be useful to someone.\n\nIf you need help with an issue, or if you have a feature request, please create an item in the GitHub issue tracker. Check if a similar item exists before creating a new one, and help out other users if you know the solution to an issue.\n\nYou can leave a donation via PayPal if you wish to say thanks. My PayPal ID is linked below.\n\nThanks,\nTony George");
		label.label = msg;
		label.wrap = true;
		label.xalign = 0.0f;
		label.yalign = 0.0f;
		label.margin_bottom = 6;
		vbox_main.pack_start(label, true, true, 0);

		//vbox_actions
		var vbox_actions = new Box (Orientation.HORIZONTAL, 6);
		//vbox_actions.margin_left = 50;
		//vbox_actions.margin_right = 50;
		//vbox_actions.margin_top = 20;
		vbox_main.pack_start(vbox_actions, false, false, 0);

		string username = get_username();
		
		//btn_donate_paypal
		var button = new Button.with_label(_("Donate - PayPal"));
		button.set_tooltip_text("Donate to: teejeetech@gmail.com");
		vbox_actions.add(button);
		button.clicked.connect(() => {
			xdg_open("https://www.paypal.com/cgi-bin/webscr?business=teejeetech@gmail.com&cmd=_xclick&currency_code=USD&amount=10&item_name=Aptik%20Donation", username);
		});

		//btn_donate_wallet
		button = new Button.with_label(_("Donate - Google Wallet"));
		button.set_tooltip_text("Donate to: teejeetech@gmail.com");
		vbox_actions.add(button);
		button.clicked.connect(() => {
			xdg_open("https://support.google.com/mail/answer/3141103?hl=en", username);
		});

		//tracker
		button = new Button.with_label(_("Issue Tracker"));
		button.set_tooltip_text("https://github.com/teejee2008/aptik/issues");
		vbox_actions.add(button);
		button.clicked.connect(() => {
			xdg_open("https://github.com/teejee2008/aptik/issues", username);
		});

		//btn_visit
		button = new Button.with_label(_("Website"));
		button.set_tooltip_text("http://www.teejeetech.in");
		vbox_actions.add(button);
		button.clicked.connect(() => {
			xdg_open("http://www.teejeetech.in", username);
		});
	}
}

