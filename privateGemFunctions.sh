#
# ProfileGem Private Functions
# Used internally to prepare the profile, not meant to be called by the user
#

# Given a relative path, prints an absolute path
_realpath() {
  if command -v realpath >& /dev/null
  then
    realpath "$1"
  else
    # readlink -f doesn't exist on OSX, so can't use readlink
    if [[ -d "$1" ]]; then
      (cd "$1" && pwd -P)
    else
      echo "$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")"
    fi
  fi
}

# Expects a path argument and outputs the full path, with the path to ProfileGem stripped off
# e.g. dispPath /home/username/ProfileGem/my.gem => my.gem
_dispPath() {
  _realpath "$@" | sed 's|^'"$_PGEM_LOC/"'||'
}

# Checks that the config file exists, and returns its name
_configFile() {
  local conf_file='local.conf.sh'
  echo "$conf_file"
  if ! [[ -f "$conf_file" ]]; then
    pgem_err "No ${conf_file} file found."
    return 1
  fi
}

# Run "$@" in each gem - should generally be a function
_eachGem() {
  pushd "$_PGEM_LOC" > /dev/null
  local i
  for i in "${!_GEMS[@]}"; do
    local gem="${_GEMS[$i]}"
    if [[ -d "$gem" ]]; then
      pushd "$gem" > /dev/null
      "$@"
      local exit=$?
      if [[ $exit != 0 ]]; then
        _PGEM_LOAD_EXIT_CODE=$exit
        pgem_err "'$*' failed in $gem"
      fi
      popd > /dev/null
    else
      pgem_log "$gem is not a directory."
      # http://wiki.bash-hackers.org/syntax/arrays
      unset -v '_GEMS['"$i"']'
    fi
  done
  popd > /dev/null
}

# Prints a line describing the status of a local repo vs. its remote source.
# No output means no (known) changes to pull.
# Currently only supports hg
_incomingRepo() {
  local dir
  dir=$(basename "$PWD")
  if [[ -d ".hg" ]]; then
    local incoming
    incoming=$(hg incoming -q | wc -l)
    if (( incoming > 0 )); then
      echo "$dir is $incoming change(s) behind."
    fi
  fi
}

# Pulls in updates for the current directory, currently aware of Mercurial and Git
# Alternatively create an update.sh script in the current directory to specify
# custom update behavior
_updateRepo() {
  local dir
  dir=$(basename "$PWD")
  if [[ -f "noupdate" ]]; then
    echo "Not updating $dir"
    return
  fi
  echo "Updating $dir"
  if [[ -f "update.sh" ]]; then
    ./update.sh
  elif [[ -d ".hg" ]]; then
    # separate steps, so that we update even if pull doesn't
    # find anything (i.e. someone pushed to this repo)
    # TODO this should alert more clearly if the user needs to merge heads
    hg pull > /dev/null
    hg up -c > /dev/null
  elif [[ -d ".git" ]]; then
    # TODO are their failure modes for this?
    git pull --rebase > /dev/null
  else
    pgem_err "Could not update $dir"
    return 1
  fi
}

# Sources a file if it exists, skips if not
_srcIfExist() {
  if [[ -f "$1" ]];  then
    pgem_log "Including $(_dispPath "$1")"
    # shellcheck disable=SC1090
    . "$1"
  fi
}

# Initialize environment
_loadBase() {  _srcIfExist "base.conf.sh"; }

# Evaluates the config file - not called by _eachGem
_evalConfig() {  _srcIfExist "$(_configFile)"; }

# Set environment variables
_loadEnv() {  _srcIfExist "environment.sh"; }

# Load aliases
_loadAlias() { _srcIfExist "aliases.sh"; }

# Define functions
_loadFuncs() { _srcIfExist "functions.sh"; }

# Add scripts directory to PATH
_loadScripts() {
  if [[ -d "scripts" ]]; then
    pgem_add_path "scripts"
  fi
}

# Run commands
_loadCmds() { _srcIfExist "commands.sh"; }

# Output first paragraph of info.txt, indented
_printDocLead() {
  echo "$(basename $PWD)"
  if [[ -f "info.txt" ]]; then
    # http://stackoverflow.com/a/1603425/113632
    sed -e 's/^/  /' -e '/^\s*$/Q' "info.txt"
    echo
  fi
}

# Output info.txt and check for incoming changes
_printDoc() {
  _incomingRepo
  if [[ -f "info.txt" ]]; then
    cat "info.txt"
  fi
}
