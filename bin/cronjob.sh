#!/bin/bash
### FILE
#       cronjob.sh - calling egw2fbox.pl and fritzuploader.pl
#                  - need config file to find BASEDIR directory
#
### COPYRIGHT
#       Copyright 2011  Christian Anton <mail@christiananton.de>
#                       Kai Ellinger <coding@blicke.de>
#
#       This program is free software; you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation; either version 2 of the License, or
#       (at your option) any later version.
#       
#       This program is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.
#       
#       You should have received a copy of the GNU General Public License
#       along with this program; if not, write to the Free Software
#       Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
#       MA 02110-1301, USA.
#
### FUNCS
function verbose {
	if [ -n "$VERBOSE" ]
	then
		echo "$0: $1"
	fi
}

### INIT
# read command line option: cronjob.sh -c config.file 
while getopts "c:v" flag
do
  case "$flag" in
	c)
		CONFIGFILE=$OPTARG
		;;
	v)
		VERBOSE=1
		;;
  esac
done

# read config file
verbose "reading config file..."
if [ -z $CONFIGFILE ]
then
	echo "you must supply a config file using the -c argument"
	exit 253

elif [ ! -f "$CONFIGFILE" ]
then
	echo "could not open config file"
	exit 254
fi

BASEDIR=$(grep "CRON_BASEDIR" $CONFIGFILE | sed "s/\#.*//g" | cut -d"=" -f2|sed "s/ //g"|sed "s/\/\+$//")

if [ ! -d "$BASEDIR" ]; then
	echo "basedir $BASEDIR not found or is not a directory"
	exit 252
fi

BINDIR=$(grep "CRON_BINDIR" $CONFIGFILE | sed "s/\#.*//g" | cut -d"=" -f2 |sed "s/ //g"|sed "s/\/\+$//")
XMLFILE=$(grep "FBOX_OUTPUT_XML_FILE" $CONFIGFILE | sed "s/\#.*//g" | cut -d"=" -f2|sed "s/ //g"|sed "s/\/\+$//")
HASHFILE=$(grep "CRON_FBOX_XML_HASH" $CONFIGFILE | sed "s/\#.*//g" | cut -d"=" -f2 |sed "s/ //g"|sed "s/\/\+$//")
# TODO - maybe some checks whether BINDIR, XMLFILE and HASHFILE are valid

### DO WORK
# create data files viewable for user only
umask 077

cd $BASEDIR

# call the magic perl script
if [ -n "$VERBOSE" ]
then
	verbose "about to start the worker script in verbose mode"
	EGW2FBOX_ARGS="-c $CONFIGFILE -v"
else
	verbose "about to start the worker script"
	EGW2FBOX_ARGS="-c $CONFIGFILE"
fi

$BINDIR/egw2fbox.pl $EGW2FBOX_ARGS
if [ $? -ne 0 ]; then
	echo "egroupware exporter did not finish correctly"
	exit 251
else
	verbose "worker script ended successfully"
fi

# hash
NEWHASH=$(cat $XMLFILE | grep -v mod_time | md5sum | cut -d" " -f1)
OLDHASH=$(cat $HASHFILE 2>/dev/null)

if [ "_$OLDHASH" = "_$NEWHASH" ]
then
	verbose "hashes of last and new output xml do not differ, not updating fritzbox"
else
	verbose "now uploading new XML file to FritzBox"
	export FRITZUPLOADERCFG=$CONFIGFILE
	$BINDIR/fritzuploader.pl

	if [ $? -eq 0 ]; then
		# only persist new hash if fritzuploader has run correctly
		# in case of i. e. network problems that one should fail and
		# make this wrapper script recognize that another upload is
		# needed
		echo $NEWHASH >$HASHFILE
		verbose "upload succeeded"
	else
		verbose "upload could not be finished correctly"
	fi
fi
