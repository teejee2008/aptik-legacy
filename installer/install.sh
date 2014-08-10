#!/bin/bash

app_name='aptik'
app_fullname='Aptik'

generic_depends=(rsync libgee json-glib aptitude gksu)
debian_depends=(rsync libgee2 libjson-glib-1.0-0 aptitude gksu)
redhat_depends=()
arch_depends=()

generic_recommends=()
debian_recommends=()
redhat_recommends=()
arch_recommends=()

Reset='\e[0m'
Red='\e[1;31m'
Green='\e[1;32m'
Yellow='\e[1;33m'

CHECK_COLOR_SUPPORT() {
	colors=`tput colors`
	if [ $colors -gt 1 ]; then
		COLORS_SUPPORTED=0
	else
		COLORS_SUPPORTED=1
	fi
}

MSG_INFO() {
	add_newline=''
	if [ "$2" == 0 ]; then
		add_newline='-n'
	fi
	
	if [ $COLORS_SUPPORTED -eq 0 ]; then
        echo -e ${add_newline} "[${Yellow}*${Reset}] ${Green}$1${Reset}"
    else
        echo -e ${add_newline} "[*] $1"
    fi
}

MSG_WARNING() {
	add_newline=''
	if [ "$2" == 0 ]; then
		add_newline='-n'
	fi
	
	if [ $COLORS_SUPPORTED -eq 0 ]; then
        echo -e ${add_newline} "[${Red}!${Reset}] ${Yellow}$1${Reset}"
    else
        echo -e ${add_newline} "[!] $1"
    fi
}

MSG_ERROR() {
	add_newline=''
	if [ "$2" == 0 ]; then
		add_newline='-n'
	fi
	
    if [ $COLORS_SUPPORTED -eq 0 ]; then
        echo -e ${add_newline} "[${Red}X${Reset}] ${Yellow}$1${Reset}"
    else
        echo -e ${add_newline} "[X] $1"
    fi
}

CD_PUSH() {
	cd_backup=`pwd`
}

CD_POP() {
	if [ ! -z "${cd_backup}" ]; then
		cd "${cd_backup}"
	fi
}

BACKUP_IFS(){
	IFS_backup="${IFS}"
}

SET_IFS_NEWLINE(){
	IFS=$'\n'
}

RESET_IFS() {
	if [ ! -z "${IFS_backup}" ]; then
		IFS="${IFS_backup}"
	fi
}

EXIT(){
	RESET_IFS
	CD_POP
	exit $1
}

WAIT_FOR_INPUT() {
	echo ""
	echo "Press any key to exit..."
	read dummy
}

GET_SCRIPT_PATH(){
	SCRIPTPATH="$(cd "$(dirname "$0")" && pwd)"
	SCRIPTNAME=`basename $0`
}

RUN_AS_ADMIN() {
	if [ ! `id -u` -eq 0 ]; then
		GET_SCRIPT_PATH
		if command -v sudo >/dev/null 2>&1; then
			sudo "${SCRIPTPATH}/${SCRIPTNAME}"
			EXIT $?
		elif command -v su >/dev/null 2>&1; then
			su -c "${SCRIPTPATH}/${SCRIPTNAME}"
			EXIT $?
		else
			echo ""
			MSG_ERROR "** Installer must be run as Admin (using 'sudo' or 'su') **"
			echo ""
			EXIT 1
		fi
	fi
}

CD_PUSH
CHECK_COLOR_SUPPORT
RUN_AS_ADMIN
BACKUP_IFS

if ! command -v apt-get >/dev/null 2>&1; then
	MSG_ERROR "'apt-get' not found"
	MSG_ERROR "This application can be used only on Debian-based systems"
	WAIT_FOR_INPUT
	EXIT 1
fi

SET_IFS_NEWLINE

MSG_INFO "Expanding directories..."
for f in `find ./ -type d -exec echo "{}" \;`; do
    directory=`echo "$f" | sed -r 's/^.{2}//'`
    mkdir -p -m 755 "/$directory"
    echo "/$directory"
done
echo ""

MSG_INFO "Installing files..."
for f in `find ./ -type f \( ! -iname "install.sh" \) -exec echo "{}" \;`; do
    file=`echo "$f" | sed -r 's/^.{2}//'`
    install -m 0755 "./$file" "/$file"
    echo "/$file"
done
echo ""

RESET_IFS

install_dependencies=y

if command -v apt-get >/dev/null 2>&1; then

	if [ -f /etc/debian_version ]; then
		install_dependencies=y
	else
		MSG_INFO "Found 'apt-get' package manager" 
		MSG_INFO "Install dependencies with 'apt-get'? (y/n):" "0"
		read install_dependencies
		if [ "$install_dependencies" == "" ]; then
			install_dependencies=y
		fi
	fi
	
	if [ "$install_dependencies" == "y" ]; then
		MSG_INFO "Installing Debian packages..."
		echo ""
		for i in "${debian_depends[@]}"; do
		  MSG_INFO "Installing: $i"
		  apt-get -y install $i
		  echo ""
		done
	fi
fi
echo ""

MSG_INFO "Install completed."
echo ""
echo "******************************************************************"
echo "Start ${app_fullname} using the shortcut in the Applications Menu"
echo "or by running the command: sudo ${app_name}"	
echo "If it fails to start, check and install the following packages:"
echo "Required: ${generic_depends[@]}"
echo "Optional: (none)"
echo "******************************************************************"
WAIT_FOR_INPUT
EXIT 0
