prefix=/usr
bindir=$(prefix)/bin
sharedir=$(prefix)/share
localedir=$(sharedir)/locale
launcherdir=$(sharedir)/applications
polkitdir=$(sharedir)/polkit-1/actions
mandir=$(sharedir)/man
man1dir=$(mandir)/man1
CFLAGS=--std=c99
app_name=aptik
app_fullname=Aptik

vte_version=$(shell { ((ldconfig -p | grep libvte-2.91*.so) >/dev/null && echo 'vte-2.91') || echo 'vte-2.90'; } )
vte_symbols=$(shell { ((ldconfig -p | grep libvte-2.91*.so) >/dev/null && echo '-D VTE_291') || echo ''; } )
gtk3_version=$(shell { (pkg-config --modversion gtk+-3.0 | cut -d. -f2); } )

ifeq ($(shell { test ${gtk3_version} -gt 17 ; echo $$? ; } ), 0)
gtk3_symbols=$(shell { echo '-D GTK3_18'; } )
else
gtk3_symbols=$(shell { echo ''; } )
endif

define_symbols=$(shell { echo "${vte_symbols} ${gtk3_symbols}"; } )

all:
	#build binaries

	#aptik-gtk
	valac -X -D'GETTEXT_PACKAGE="${app_name}"' --Xcc="-lm" -X -Wl,-rpath,/usr/share/${app_name}/libs ${define_symbols} --thread "Main.vala" "Classes.vala" "Utility.vala" "AptikGtk.vala" "MainWindow.vala" "PackageWindow.vala" "ProgressWindow.vala" "PpaWindow.vala" "ThemeWindow.vala" "MountWindow.vala" "ConfigWindow.vala" "CustomMessageDialog.vala" "DonationWindow.vala" "DownloadWindow.vala" "AboutWindow.vala" "Theme.vala" "Archive.vala" "Archiver.vala" "FileItem.vala" "TerminalWindow.vala" "UserAccountWindow.vala" "OneClickSettingsDialog.vala" "UserDataSettingsDialog.vala" "CronTab.vala" -o ${app_name}-gtk --pkg glib-2.0 --pkg gio-unix-2.0 --pkg posix --pkg gtk+-3.0 --pkg $(vte_version) --pkg gee-0.8 --pkg json-glib-1.0 

	#aptik
	valac -X -D'GETTEXT_PACKAGE="${app_name}"' --Xcc="-lm" -X -Wl,-rpath,/usr/share/${app_name}/libs --thread "Main.vala" "Classes.vala" "Utility.vala" "CustomMessageDialog.vala" "AptikConsole.vala" "Theme.vala" "Archive.vala" "Archiver.vala" "FileItem.vala" "CronTab.vala" -o ${app_name} --pkg glib-2.0 --pkg gio-unix-2.0 --pkg posix --pkg gtk+-3.0 --pkg gee-0.8 --pkg libsoup-2.4 --pkg json-glib-1.0

	#update translation template
	xgettext --language=C --keyword=_ --copyright-holder='Tony George (teejee2008@gmail.com)' --package-name='${app_name}' --package-version='1.6' --msgid-bugs-address='teejee2008@gmail.com' --escape --sort-output -o ../${app_name}.pot *.vala

clean:
	rm -rf *.o ${app_name} ${app_name}-gtk

install:
	mkdir -p "$(DESTDIR)$(bindir)"
	mkdir -p "$(DESTDIR)$(sharedir)"
	mkdir -p "$(DESTDIR)$(mandir)"
	mkdir -p "$(DESTDIR)$(man1dir)"
	mkdir -p "$(DESTDIR)$(launcherdir)"
	mkdir -p "$(DESTDIR)$(polkitdir)"
	mkdir -p "$(DESTDIR)$(sharedir)/${app_name}"
	mkdir -p "$(DESTDIR)$(sharedir)/pixmaps"
	mkdir -p "$(DESTDIR)$(localedir)/it/LC_MESSAGES"
	mkdir -p "$(DESTDIR)$(localedir)/ru/LC_MESSAGES"
	mkdir -p "$(DESTDIR)$(localedir)/ko/LC_MESSAGES"
	mkdir -p "$(DESTDIR)$(localedir)/pt/LC_MESSAGES"
	mkdir -p "$(DESTDIR)$(localedir)/cs/LC_MESSAGES"

	#binary
	install -m 0755 ${app_name} "$(DESTDIR)$(bindir)"
	install -m 0755 ${app_name}-gtk "$(DESTDIR)$(bindir)"
	install -m 0755 ${app_name}-uninstall "$(DESTDIR)$(bindir)"
	install -m 0755 ${app_name}-launcher "$(DESTDIR)$(bindir)"

	#shared files
	cp -dpr --no-preserve=ownership -t "$(DESTDIR)$(sharedir)/${app_name}" ./share/${app_name}/*
	chmod --recursive 0755 $(DESTDIR)$(sharedir)/${app_name}/*

	#polkit policy file
	install -m 0644 ./share/polkit-1/actions/in.teejeetech.pkexec.aptik-gtk.policy "$(DESTDIR)$(polkitdir)"
	
	#launcher
	install -m 0755 ${app_name}.desktop "$(DESTDIR)$(launcherdir)"

	#app icon
	install -m 0755 ./share/pixmaps/${app_name}.svg "$(DESTDIR)$(sharedir)/pixmaps/"

	#translations
	msgfmt --check --verbose -o "$(DESTDIR)$(localedir)/it/LC_MESSAGES/${app_name}.mo" ../po/${app_name}-it.po
	msgfmt --check --verbose -o "$(DESTDIR)$(localedir)/pt/LC_MESSAGES/${app_name}.mo" ../po/${app_name}-pt.po
	msgfmt --check --verbose -o "$(DESTDIR)$(localedir)/ko/LC_MESSAGES/${app_name}.mo" ../po/${app_name}-ko.po
	msgfmt --check --verbose -o "$(DESTDIR)$(localedir)/ru/LC_MESSAGES/${app_name}.mo" ../po/${app_name}-ru.po
	msgfmt --check --verbose -o "$(DESTDIR)$(localedir)/cs/LC_MESSAGES/${app_name}.mo" ../po/${app_name}-cs.po

uninstall:

	#binary
	rm -f "$(DESTDIR)$(bindir)/${app_name}"
	rm -f "$(DESTDIR)$(bindir)/${app_name}-gtk"
	rm -f "$(DESTDIR)$(bindir)/${app_name}-uninstall"
	rm -f "$(DESTDIR)$(bindir)/${app_name}-launcher"

	#shared files
	rm -rf "$(DESTDIR)$(sharedir)/${app_name}"

	#polkit policy file
	rm -f "$(DESTDIR)$(polkitdir)/in.teejeetech.pkexec.aptik-gtk.policy"

	#launcher
	rm -f "$(DESTDIR)$(launcherdir)/${app_name}.desktop"

	#app icon
	rm -f "$(DESTDIR)$(sharedir)/pixmaps/${app_name}.svg"

	#translations
	rm -f $(DESTDIR)$(localedir)/*/LC_MESSAGES/${app_name}.mo
