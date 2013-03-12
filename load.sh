#!/bin/bash

#
# ProfileGem
#
# ProfileGem enables highly granular control of your terminal 
# with minimal configuration by loading environment settings,
# aliases, functions, and scripts from a series of "gems"
# you can customize and use independantly.  Easily configure
# similar, yet application specific, profiles with everything
# you need immidiately on hand.
#

_GEMP_DEBUG=true
_GEMP_PATH=$(realpath $(dirname "${BASH_SOURCE[0]}")) #  | sed 's`^'$HOME'`~`' to show ~ instead of $HOME

pushd "$_GEMP_PATH" > /dev/null

. ./gemFunctions.sh

_GEM_LIST=$(_gemList)

_eachGem _loadPre       # load pre-config resources

_eachGem _parseConf     # load config settings

_eachGem _loadEnv       # set environment variables
_eachGem _loadAlias     # create aliases
_eachGem _loadFuncs     # define functions

if [ ! -z "$PS1" ]      # interactive shell
then
	_eachGem _runCmd    # run interactive commands
	if [ -d $START_DIR ]
	then
		cd $START_DIR
	else
		echo "Start Dir $START_DIR Does Not Exist"
	fi
fi

# Enable running a command in ProfileGem's scope
# Note aliases are not accessible if it's not an interactive shell
if [ $# -gt 0 ]
then
	"$@"
fi
