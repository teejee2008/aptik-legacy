/*
 * DonationWindow.vala
 *
 * Copyright 2012 Tony George <teejeetech@gmail.com>
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
		string msg = _("I made this application for my own use. I'm distributing it in the hope that it will be useful to someone. This is not a commercial product, there's no company behind it and there are no support teams to answer your questions. I work on this application during my free time based on my own requirements and interest.\n\nIf you need help with an issue, or if you have a feature request, please open a ticket on the GitHub issue tracker. If the requested feature is useful to me and I have the time, I will implement it. If it is not useful to me or if it requires a lot of time and effort, then it will remain in the tracker till someone takes interest in the feature and implements it. That's the whole idea behind open-source software. Open-source does not mean \"free\" stuff that you don't need to pay for. It's software that belongs to everyone. If someone needs a feature that is missing, they can take the source code, add the feature and contribute the change back to the project so that everyone can benefit from their work.\n\nHaving said that, please feel free to leave feature requests, suggestions and bug reports in the issue tracker. Good ideas are always useful and many of them require little time to implement. Check if an issue was already reported before opening a new item in the tracker, and help out other users if you know the solution to an issue.\n\nYou can leave a donation via PayPal if you wish to say thanks. My PayPal ID is linked below.\n\nThanks,\nTony George");
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

		//btn_donate_paypal
		var button = new Button.with_label(_("Donate - PayPal"));
		button.set_tooltip_text("Donate to: teejeetech@gmail.com");
		vbox_actions.add(button);
		button.clicked.connect(() => {
			xdg_open("https://www.paypal.com/cgi-bin/webscr?business=teejeetech@gmail.com&cmd=_xclick&currency_code=USD&amount=10&item_name=Aptik%20Donation");
		});

		//btn_donate_wallet
		button = new Button.with_label(_("Donate - Google Wallet"));
		button.set_tooltip_text("Donate to: teejeetech@gmail.com");
		vbox_actions.add(button);
		button.clicked.connect(() => {
			xdg_open("https://support.google.com/mail/answer/3141103?hl=en");
		});

		//tracker
		button = new Button.with_label(_("Issue Tracker"));
		button.set_tooltip_text("https://github.com/teejee2008/aptik/issues");
		vbox_actions.add(button);
		button.clicked.connect(() => {
			xdg_open("https://github.com/teejee2008/aptik/issues");
		});

		//btn_visit
		button = new Button.with_label(_("Website"));
		button.set_tooltip_text("http://www.teejeetech.in");
		vbox_actions.add(button);
		button.clicked.connect(() => {
			xdg_open("http://www.teejeetech.in");
		});
	}
}

