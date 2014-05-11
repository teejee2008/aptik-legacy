prefix = /usr
bindir = $(prefix)/bin
sharedir = $(prefix)/share
localedir = $(sharedir)/locale
launcherdir = $(sharedir)/applications
mandir = $(sharedir)/man
man1dir = $(mandir)/man1
CFLAGS = --std=c99

all:
	valac -X -D'GETTEXT_PACKAGE="aptik"' --Xcc="-lm" --thread "Main.vala" "Utility.vala" "AptikConsole.vala" -o aptik --pkg glib-2.0 --pkg gio-unix-2.0 --pkg posix --pkg gtk+-3.0 --pkg gee-1.0 --pkg libsoup-2.4 --pkg json-glib-1.0
	valac -X -D'GETTEXT_PACKAGE="aptik"' --Xcc="-lm" --thread "Main.vala" "Utility.vala" "AptikGtk.vala" "MainWindow.vala" "LogWindow.vala" "DonationWindow.vala" "AboutWindow.vala" -o aptik-gtk --pkg glib-2.0 --pkg gio-unix-2.0 --pkg posix --pkg gtk+-3.0 --pkg gee-1.0 --pkg libsoup-2.4 --pkg json-glib-1.0

clean:
	rm -rf *.o aptik

install:
	mkdir -p "$(DESTDIR)"
	mkdir -p "$(DESTDIR)$(bindir)"
	mkdir -p "$(DESTDIR)$(sharedir)"
	mkdir -p "$(DESTDIR)$(mandir)"
	mkdir -p "$(DESTDIR)$(man1dir)"
	mkdir -p "$(DESTDIR)$(launcherdir)"
	mkdir -p "$(DESTDIR)$(sharedir)/aptik"
	mkdir -p "$(DESTDIR)$(sharedir)/pixmaps"
	#mkdir -p "$(DESTDIR)$(localedir)/it_IT/LC_MESSAGES"
	
	#binary
	install -m 0755 aptik "$(DESTDIR)$(bindir)"
	install -m 0755 aptik-gtk "$(DESTDIR)$(bindir)"
	
	#shared files
	cp -dpr --no-preserve=ownership -t "$(DESTDIR)$(sharedir)/aptik" ./share/aptik/*
	chmod --recursive 0755 $(DESTDIR)$(sharedir)/aptik/*
	
	#launcher
	install -m 0755 aptik.desktop "$(DESTDIR)$(launcherdir)"
	
	#app icon
	install -m 0755 ./share/pixmaps/aptik.png "$(DESTDIR)$(sharedir)/pixmaps/"
	
	#translations
	#msgfmt --check --verbose -o "$(DESTDIR)$(localedir)/it_IT/LC_MESSAGES/aptik.mo" ../po/aptik-it.po

uninstall:

	#binary
	rm -f "$(DESTDIR)$(bindir)/aptik"
	rm -f "$(DESTDIR)$(bindir)/aptik-gtk"
	
	#shared files
	rm -rf "$(DESTDIR)$(sharedir)/aptik"
	
	#launcher
	rm -f "$(DESTDIR)$(launcherdir)/aptik.desktop"
	
	#app icon
	rm -f "$(DESTDIR)$(sharedir)/pixmaps/aptik.png"
	
	#translations
	#rm -f $(DESTDIR)$(localedir)/*/LC_MESSAGES/aptik.mo
