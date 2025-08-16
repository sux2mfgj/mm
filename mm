#!/bin/bash

set -eu
#set -x

help() {
  printf "usage:\n"
  printf "\tmm init\t: create a ~/.mm dir\n"
  printf "\tmm new {filename}\t: create a {filename} and trace the file\n"
  printf "\tmm ls [local,all]\t: listup the memos \n"
  printf "\tmm help\t: show this message\n"
}

# global variables
mm_root=$HOME/.mm
mm_root_index=${mm_root}/index
cur_mm=$(pwd)/.mm
cur_mm_index=${cur_mm}/index

if [ $# -lt 1 ]; then
  help
  exit 1
fi

cmd=$1
shift

init() {
  mkdir $mm_root
  touch $mm_root_index
  echo Success
}

has_entry() {
  local index=$1
  local file=$2

  grep -q "$file" "$index" 2> /dev/null
}

cur_has_entry() {
  local file=$1

  has_entry ${cur_mm_index} ${file}
}

update_index() {
  local index=$1
  local file_path=$2
  local date=$(date +%Y-%m-%d-%H:%M)

  if has_entry ${index} ${file_path} ; then
    sed -i "s|.* ${file_path}|${date} ${file_path}|" ${index}
    echo Updated.
  else
    echo ${date} ${file_path} >> ${index}
    echo Created.
  fi
}

new() {
  fname=$1
  local file=${cur_mm}/${fname}

  mkdir -p ${cur_mm}
  touch ${cur_mm_index}

  touch ${file}

  # update the root index.
  update_index ${mm_root_index} ${cur_mm_index}
  # update the local index.
  update_index ${cur_mm_index} ${file}

  echo Create a ${fname} and start to track by mm.
}

open() {
  local file=${cur_mm}/$1

  if ! cur_has_entry $file; then
    echo Not found the $file
    exit 1
  fi

  # update the root index.
  update_index ${mm_root_index} ${cur_mm_index}

  # update the root index.
  update_index ${cur_mm_index} ${file}

  editor ${file}
}

search_recursive() {
  local dir=$1

  while [[ "${dir}" != "/" ]];
  do
    if [[ -d "${dir}/.mm" ]]; then
      echo "${dir}/.mm"
      return 0
    fi

    dir=$(dirname ${dir})

  done

  return 1
}

ls() {
  local region="local"
  if [ $# -eq 1 ]; then
    region=$1
  fi

  case "$region" in
    local)
      local dir=$(search_recursive $(pwd))
      if [[ -n "$dir" ]]; then
        cat ${dir}/index
      else
        echo ".mm is not found in any parent directory."
      fi
      ;;
    all)
      cat $HOME/.mm/index
      ;;
    *)
      echo Invalid argument.
      help
      exit 1
      ;;
  esac
}

remove() {
  # if $1 is exists, remove an entry of the file.
  # if not, remove .mm/. You should confirm with the user before deleting.
  file=$(pwd)/.mm/$1
  if ! cur_has_entry $file; then
    echo not found
  fi

  # TODO
}

arg_check(){
  num=$1
  shift
  if [ $# -lt $num ]; then
    echo "Invalid argument."
    help
    exit 1
  fi
}

case "$cmd" in
  init)
    init
    ;;
  new)
    arg_check 1 $@
    new $1
    ;;
  open)
    arg_check 1 $@
    open $1
    ;;
  ls)
    ls $@
    ;;
  remove)
    arg_check 1 $@
    remove $1
    ;;
  help)
    help
    exit 0
    ;;
  *)
    echo Found unexpected subcommand. See the following usage.
    help
    exit 1
    ;;
esac
