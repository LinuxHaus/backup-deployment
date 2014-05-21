#!/bin/bash
CLIENT=""
AUTODIRNAME=""

TEMP=`getopt -o c:d: --long client:,director: -n $0 -- "$@"`
if [ $? != 0 ] ; then echo "Terminating..." >&2 ; exit 1 ; fi
eval set -- "$TEMP"
while true ; do
	case "$1" in
		-c|--client) CLIENT=$2; shift 2;;
		-d|--director) AUTODIRNAME=$2; shift 2 ;;
		--) shift ; break ;;
		*) echo "Internal error!" ; exit 1 ;;
	esac
done

if [ x$CLIENT == x ]; then
	echo "usage: $0 --client CLIENTNAME [ --director DIRECTORNAME ]"
	exit 1
fi
if [ x$AUTODIRNAME == x ]; then
	AUTODIRNAME=$(hostname)
fi


if [ -e /etc/bareos/client.d/$CLIENT.conf ]; then
  echo /etc/bareos/client.d/$CLIENT.conf already exists
  exit 1
fi
if [ -e /etc/bareos/job.d/$CLIENT.conf ]; then
  echo /etc/bareos/job.d/$CLIENT.conf already exists
  exit 1
fi
AUTOFDPASS=$(pwgen 32 1)
sed '
	s/AUTOCLIENTHOSTNAME/'$CLIENT'/g;
	s/AUTOFDPASS/'$AUTOFDPASS'/g;
' >/etc/bareos/client.d/$CLIENT.conf <<'EOF'
Client {
   Name = AUTOCLIENTHOSTNAME
   Address = AUTOCLIENTHOSTNAME
   FDPort = 9102
   Catalog = MyCatalog
   File Retention = 395 days
   Job Retention = 395 days
   Password = "AUTOFDPASS"         # password for FileDaemon
   AutoPrune = yes                     # Prune expired Jobs/Files
   Maximum Concurrent Jobs = 10
}
EOF
sed '
	s/AUTOCLIENTHOSTNAME/'$CLIENT'/g;
	s/AUTOFDPASS/'$AUTOFDPASS'/g;
' >/etc/bareos/job/$CLIENT.conf <<'EOF'
Job {
  Name = "AUTOCLIENTHOSTNAME"
  Client = AUTOCLIENTHOSTNAME
  JobDefs = "job-default"
  FileSet = "fs-GENERIC-LINUX"
  SpoolData = No
  SpoolAttributes = Yes
}
EOF
sed '
	s/AUTOCLIENTHOSTNAME/'$CLIENT'/g;
	s/AUTODIRNAME/'$AUTODIRNAME'/g;
	s/AUTOFDPASS/'$AUTOFDPASS'/g;
' <<'SKRIPT_EOF' | ssh -t $CLIENT
set -x
case $(cat /etc/debian_version) in
	6.*)	echo 'deb     http://download.bareos.org/bareos/release/13.2/Debian_6.0/ /' > /etc/apt/sources.list.d/bareos.list
				OS=Debian
		;;
  7.*)	echo 'deb     http://download.bareos.org/bareos/release/13.2/Debian_7.0/ /' > /etc/apt/sources.list.d/bareos.list
				OS=Debian
    ;;
esac
if [ x$OS == xDebian ]; then
  if [ x$http_proxy == x ]; then
		if [ x$HTTP_PROXY == x ]; then
			export $(apt-config shell http_proxy Acquire::http::Proxy | sed "s/'//g")
    else
			export http_proxy=$HTTP_PROXY
		fi
	fi
  wget http://download.bareos.org/bareos/release/13.2/Debian_7.0/Release.key -O - | apt-key add -
	apt-get update
  apt-get -y install bareos-filedaemon

fi
cat <<EOF1 >/etc/bareos/bareos-fd.conf
#
# List Directors who are permitted to contact this File daemon
#
Director {
  Name = AUTODIRNAME-dir
  Password = "AUTOFDPASS"
}

#
# Restricted Director, used by tray-monitor to get the
#   status of the file daemon
#
Director {
  Name = AUTODIRNAME-mon
  Password = "AUTOFDPASS"
  Monitor = yes
}

#
# "Global" File daemon configuration specifications
#
FileDaemon {                          # this is me
  Name = AUTOCLIENTHOSTNAME
  Maximum Concurrent Jobs = 20

  # remove comment in next line to load plugins from specified directory
  # Plugin Directory = /usr/lib/bareos/plugins

  # if compatible is set to yes, we are compatible with bacula
  # if you want to use new bareos features, please set
  # compatible = no
}

# Send all messages except skipped files back to Director
Messages {
  Name = Standard
  director = AUTODIRNAME-dir = all, !skipped, !restored
}
EOF1
/etc/init.d/bareos-fd restart
SKRIPT_EOF
# vim: ts=2 sw=2 sts=2 sr noet
