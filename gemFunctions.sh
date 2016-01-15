#
# ProfileGem Functions
# Used internally to prepare the profile, not meant to be called by the user
#

#
# User Functions
#

pgem_reload()
{
  $_PGEM_DEBUG && set | sort > /tmp/pgem_pre.env
  PATH="$_PRE_PGEM_PATH"
  PS1="$_PRE_PGEM_PS1"
  PROMPT_COMMAND="$_PRE_PGEM_PROMPT_COMMAND"
  
  pushd "$_PGEM_LOC" > /dev/null
  . ./load.sh
  local ret=$?
  popd > /dev/null
  
  if $_PGEM_DEBUG
  then
    set | sort > /tmp/pgem_post.env
    echo Environment Changes:
    comm -3 /tmp/pgem_pre.env /tmp/pgem_post.env |
      sed -e 's`^[^\t]`- \0`' -e 's`^\t`+ `'
  fi
  unset _PGEM_LOAD_EXIT_CODE
  return $ret
}

pgem_update()
{
  _PGEM_LOAD_EXIT_CODE=0
  pushd "$_PGEM_LOC" > /dev/null
  _eachGem _updateRepo
  _updateRepo # update ProfileGem
  popd > /dev/null
  pgem_reload
}

# TODO improve this
pgem_info()
{
  echo Useful Commands:
  _eachGem _printDoc info.txt
  #echo 'Run `pgem_help` for more'
}

# TODO
#pgem_help()
#{
#  _eachGem _printDoc info.txt
#  echo
#  _eachGem _printDoc help.txt
#}

# Cron Functions

pgem_cron_out()
{
  local load="$_PGEM_LOC/load.sh"
  cronFile()
  {
    local file="jobs.txt"
    if [ -f $file ]
    then
      echo -f $(_realpath $file)
    fi
  }
  local files=$(_eachGem cronFile)
  $_PGEM_LOC/cronBuild.py -p "$load" $files $@ $PGEM_JOBS
}

pgem_cron_info()
{
  pgem_cron_out -i
}

pgem_cron_user()
{
  pgem_cron_out | crontab && echo "Successfully installed user crontab"
}

pgem_cron_etc()
{
  if [ -z $1 ]
  then
    local path=/etc/cron.d/profileGem
  else
    local path=$1
  fi
  pgem_cron_out -u - > $path && echo "Successfully installed system crontab to $path"
}

# Copies a function f to _orig_f, letting callers redefine (or decorate) f
# http://stackoverflow.com/q/1203583
#
# Suggested usage:
#
#   pgem_decorate func &&
#   func() {
#     ...
#   }
#
# The && prevents func from being (re)defined if it didn't previously exist.
pgem_decorate()
{
  local func="${1:?Must provide a function name to decorate}"
  local prefix="${2:-_orig_}"
if declare -F ${prefix}${func} >& /dev/null
  then
    # This function has previously been decorated; restore the original version
    _copy_function ${prefix}${func} ${func}
  fi
  _copy_function ${func} ${prefix}${func}
}

#
# Private Functions
#

# Given a name and an existing function, create a new function called name that
# executes the same commands as the initial function
_copy_function()
{
  declare -F ${1:?Missing function} >& /dev/null || { echo No such function $1; return 1; }
  eval "$(echo "${2:?Missing function name}()"; declare -f ${1} | tail -n +2)"
}

# Given a relative path, prints an absolute path
_realpath()
{
  if which realpath > /dev/null 2>&1
  then
    realpath "$@"
  else
    # readlink -f doesn't exist on OSX, so can't use readlink
    cd "$@"
    pwd
    cd -
  fi
}
  

# Expects a path argument and outputs the full path, with the path to ProfileGem stripped off
# e.g. dispPath /home/username/ProfileGem/my.gem => my.gem
_dispPath()
{
  _realpath "$@" | sed 's`^'"$_PGEM_LOC/"'``'
}

# Identifies the config file to read
# Only one file is loaded, the first file that exists out of the below locations
_CONFIG_FILE_LOCS=(local.conf.sh "config.d/users/${USER}.sh" "config.d/hosts/${HOSTNAME}.sh")
_findConfigFile()
{
  local file
  for file in ${_CONFIG_FILE_LOCS[@]}
  do
    [ -f $file ] && echo $file && return 0
  done
  echo "Failed to find config file, looked in ${_CONFIG_FILE_LOCS[@]}" >&2
  return 1
}
  

# Output the list of gems to load, in order
_gemList()
{
  grep '^#GEM' "$_PGEM_LOC/$(_findConfigFile)" | awk '{ print $2 ".gem" }'
}

# Run "$@" in each gem
_eachGem()
{
  pushd "$_PGEM_LOC" > /dev/null
  local gem
  for gem in $_GEM_LIST
  do
    if [ -d $gem ]
    then
      pushd $gem > /dev/null
      "$@"
      local exit=$? && [[ $exit != 0 ]] && _PGEM_LOAD_EXIT_CODE=$exit
      popd > /dev/null
    elif $_PGEM_DEBUG
    then
      echo $gem is not a directory.
      _GEM_LIST=$(echo $_GEM_LIST | sed 's`'$gem'``')
    fi
  done
  popd > /dev/null
}

# Pulls in updates for the current directory, currently aware of Mercurial and Git
# Alternatively create an update.sh script in the current directory to specify
# custom update behavior
_updateRepo()
{
  local dir=$(basename $(pwd))
  if [ -f noupdate ]
  then
    echo Not updating $dir
    return
  fi
  echo Updating $dir
  if [ -f update.sh ]
  then
    ./update.sh
  elif [ -d .hg ]
  then
    # separate steps, so that we update even if pull doesn't
    # find anything (i.e. someone pushed to this repo)
    # FIXME this doesn't correctly prompt/exit if conflicts
    hg pull > /dev/null
    hg up > /dev/null
  elif [ -d .git ]
  then
    git pull --rebase > /dev/null
  else
    echo "Could not update $dir" >&2
    return 1
  fi
}

# Sources a file if it exists, skips if not
_srcIfExist()
{
  if [ -f "$@" ]
  then
    $_PGEM_DEBUG && echo "Including $(_dispPath $@)"
    . "$@"
  fi
}

# Initialize environment
_loadBase()
{
  _srcIfExist base.conf.sh
}

# Evaluates the config file - not called by _eachGem
_evalConfig()
{
  _srcIfExist $(_findConfigFile)
}

# Set environment variables
_loadEnv()
{
  _srcIfExist environment.sh
}

# Load aliases
_loadAlias()
{
  _srcIfExist aliases.sh
}

# Define functions
_loadFuncs()
{
  _srcIfExist functions.sh
}

# Add scripts directory to PATH
_loadScripts()
{
  if [ -d scripts ]
  then
    $_PGEM_DEBUG && echo "Adding $(pwd)/scripts to \$PATH"
    export PATH="$(pwd)/scripts:$PATH"
  fi
}

# Run commands
_loadCmds()
{
  _srcIfExist commands.sh
}

# Output doc file
_printDoc()
{
  if [ -f $1 ]
  then
    $_PGEM_DEBUG && basename $(pwd)
    cat $1
  fi
}
