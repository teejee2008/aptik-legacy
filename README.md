# Aptik Migration Utility

https://launchpad.net/apt-toolkit    

Aptik is a tool to simplify re-installation of packages after doing a fresh installation of an Ubuntu-based distribution. It can be used while re-installing or upgrading to the next Ubuntu/Linux Mint release.

[![](http://1.bp.blogspot.com/-tivz6R9TJuY/VpszW6xL6TI/AAAAAAAADHc/aX_QFkAas8w/s1600/1_Main_Window.png)](http://1.bp.blogspot.com/-tivz6R9TJuY/VpszW6xL6TI/AAAAAAAADHc/aX_QFkAas8w/s1600/1_Main_Window.png) 

Upgrading to the next release of an Ubuntu-based distribution can be a painful task. While most Ubuntu-based distributions provide an option to upgrade the existing installation, it can cause a number of problems. It sometimes results in broken packages and missing dependencies which can make the system unusable. If proprietary graphic drivers are in use, the system may boot into a black screen after the upgrade.
The look and feel of the new release is lost since the previous desktop settings are used.

In order to avoid problems most people prefer to do a clean installation. While a clean installation avoids the problems that an upgrade can cause, setting up the new system can be a tedious task. Most people put off upgrading their system in order to avoid this trouble of setting up the new system.

Aptik is a tool that will make your life easier. While it won't eliminate all the work that needs to be done after a fresh installation, it will reduce it greatly.

## Features

1) **Backup & Reinstall Packages** - Saves a list of all extra packages installed by the user and re-installs the packages on the new system.  

2) **Backup & Restore Launchpad PPAs** - Saves a list of third-party repositories (Launchpad PPAs) and restores the PPA on the new system.  

3) **Backup & Restore Downloaded Packages** - Saves the downloaded DEB packages in the APT cache to the backup location. These can be copied back to the APT cache on the new system so that the packages don't need to be downloaded again.

4) **Backup & Restore Icons and Themes** - Backup installed GTK/KDE themes and icon themes from /usr/share/icons and /user/share/themes. These can be restored on the new system.

5) **Backup & Restore Application Settings** - Application configuraton folders will be zipped and saved to the backup location. Restoring the directories on the new system will restore the settings for applications like Firefox, Chromium, etc. This is better than taking a backup of your entire Home directory as you can restore the settings for specific applications while keeping the new configuration for other applications.

## Screenshots
  
[![](http://1.bp.blogspot.com/-tivz6R9TJuY/VpszW6xL6TI/AAAAAAAADHc/aX_QFkAas8w/s1600/1_Main_Window.png)](http://1.bp.blogspot.com/-tivz6R9TJuY/VpszW6xL6TI/AAAAAAAADHc/aX_QFkAas8w/s1600/1_Main_Window.png)   
Main Window

[![](http://3.bp.blogspot.com/-4fuVE9CqR-Y/VpszW7vUU-I/AAAAAAAADHg/fzczwSuEyKc/s1600/2_Restore_PPA.png)](http://3.bp.blogspot.com/-4fuVE9CqR-Y/VpszW7vUU-I/AAAAAAAADHg/fzczwSuEyKc/s1600/2_Restore_PPA.png)  
Restore Software Sources (PPAs)

[![](http://1.bp.blogspot.com/-54ayzJrg39A/VpszXQnxMPI/AAAAAAAADHk/ay8F9qDmeAQ/s1600/4_Restore_PPA_Running_apt-get_update.png)](http://1.bp.blogspot.com/-54ayzJrg39A/VpszXQnxMPI/AAAAAAAADHk/ay8F9qDmeAQ/s1600/4_Restore_PPA_Running_apt-get_update.png)  
Restore PPA Progress  

[![](http://1.bp.blogspot.com/-XT60nyoMEK8/VpszXhPWhrI/AAAAAAAADHs/DYEr8RSFQzA/s1600/5_Restore_Downloaded_Packages.png)](http://1.bp.blogspot.com/-XT60nyoMEK8/VpszXhPWhrI/AAAAAAAADHs/DYEr8RSFQzA/s1600/5_Restore_Downloaded_Packages.png)  
Restore Downloaded Packages in APT Cache  

[![](http://3.bp.blogspot.com/-T2L1yM_4_PY/VpszYOWSLTI/AAAAAAAADH0/I6L-Uy18dqc/s1600/6_Restore_Packages.png)](http://3.bp.blogspot.com/-T2L1yM_4_PY/VpszYOWSLTI/AAAAAAAADH0/I6L-Uy18dqc/s1600/6_Restore_Packages.png)  
Restore Packages  

[![](http://2.bp.blogspot.com/-zH8eACoTTtE/VpszYQqXTTI/AAAAAAAADH8/hYHDkbwQdJ0/s1600/7_Restore_Packages_Download.png)](http://2.bp.blogspot.com/-zH8eACoTTtE/VpszYQqXTTI/AAAAAAAADH8/hYHDkbwQdJ0/s1600/7_Restore_Packages_Download.png)   
Restore Packages - Download Manager powered by aria2  

[![](http://2.bp.blogspot.com/-af3Hc8fBrMA/VpszYsOnFOI/AAAAAAAADII/4uhINQ0MNss/s1600/8_Restore_Packages_Installation.png)](http://2.bp.blogspot.com/-af3Hc8fBrMA/VpszYsOnFOI/AAAAAAAADII/4uhINQ0MNss/s1600/8_Restore_Packages_Installation.png)   
Restore Packages - Last step  

[![](http://4.bp.blogspot.com/-JjXhYFzlxQE/Vps9Q5dpD5I/AAAAAAAADIo/OoeScon0vg8/s1600/9_Backup%2BApplication%2BSettings.png)](http://4.bp.blogspot.com/-JjXhYFzlxQE/Vps9Q5dpD5I/AAAAAAAADIo/OoeScon0vg8/s1600/9_Backup%2BApplication%2BSettings.png)   
Backup Application Settings  

[![](http://3.bp.blogspot.com/-47QHV54XxkM/Vps9Qr2CDbI/AAAAAAAADIk/bCWYFKArtb0/s1600/10_Backup%2BThemes.png)](http://3.bp.blogspot.com/-47QHV54XxkM/Vps9Qr2CDbI/AAAAAAAADIk/bCWYFKArtb0/s1600/10_Backup%2BThemes.png)   
Backup Themes  

[![](http://2.bp.blogspot.com/-9Pf25PbiS9k/Vps9QjfEImI/AAAAAAAADIg/HAr9ZgOIoSo/s1600/11_About.png)](http://2.bp.blogspot.com/-9Pf25PbiS9k/Vps9QjfEImI/AAAAAAAADIg/HAr9ZgOIoSo/s1600/11_About.png) 

## Installation

### Ubuntu-based Distributions (Ubuntu, Linux Mint, etc)  
Packages are available in the Launchpad PPA for supported Ubuntu releases.
Run the following commands in a terminal window:  

    sudo apt-add-repository -y ppa:teejee2008/ppa
    sudo apt-get update
    sudo apt-get install aptik

For older Ubuntu releases which have reached end-of-life, you can install Aptik from the DEB files linked below.    
[aptik-latest-i386.deb](http://dl.dropbox.com/u/67740416/linux/aptik-latest-i386.deb?dl=1) (32-bit)  
[aptik-latest-amd64.deb](http://dl.dropbox.com/u/67740416/linux/aptik-latest-amd64.deb?dl=1) (64-bit)  

### Debian
DEB files are available from following links:   
[aptik-latest-i386.deb](http://dl.dropbox.com/u/67740416/linux/aptik-latest-i386.deb?dl=1) (32-bit)  
[aptik-latest-amd64.deb](http://dl.dropbox.com/u/67740416/linux/aptik-latest-amd64.deb?dl=1) (64-bit)  

### Other Linux Distributions  
An installer is available from following links:   
[aptik-latest-i386.run](http://dl.dropbox.com/u/67740416/linux/aptik-latest-i386.run?dl=1) (32-bit)  
[aptik-latest-amd64.run](http://dl.dropbox.com/u/67740416/linux/aptik-latest-amd64.run?dl=1) (64-bit)

## Removal

Run the following commands in a terminal window:  

    sudo apt-get autoremove aptik
    
## Donations


If you want to buy me a coffee or send some donations my way, you can use Google wallet or Paypal to send a donation to **teejeetech at gmail dot com**.  

[Donate with Paypal](https://www.paypal.com/cgi-bin/webscr?business=teejeetech@gmail.com&cmd=_xclick&currency_code=USD&amount=10&item_name=Selene%20Donation)

[Donate with Google Wallet](https://support.google.com/mail/answer/3141103?hl=en)

# Disclaimer

The applications on this website are free for personal and commercial use and are licensed under the GNU General Public License. They are distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. You are using these applications entirely at your own risk. The author will not be liable for any damages arising from the use of this program. See the GNU General Public License for more details. 
