#!/bin/bash

set -eu
#set -x

help() {
  printf "usage:\n"
  printf "\tmm init\t: create a ~/.mm dir\n"
  printf "\tmm new {filename}\t: create a {filename} and trace the file\n"
  printf "\tmm ls [local,all]\t: listup the memos \n"
  printf "\tmm snapshot create [message]\t: create a snapshot of all memos\n"
  printf "\tmm snapshot list\t: list all snapshots\n"
  printf "\tmm snapshot help\t: show snapshot help message\n"
  printf "\tmm help\t: show this message\n"
}

# global variables
mm_root=$HOME/.mm
mm_root_index=${mm_root}/index
mm_snapshots=${mm_root}/snapshots
cur_mm=$(pwd)/.mm
cur_mm_index=${cur_mm}/index

if [ $# -lt 1 ]; then
  help
  exit 1
fi

cmd=$1
shift

init() {
  mkdir -p "${mm_root}"
  touch "${mm_root_index}"
  echo Success
}

has_entry() {
  local index="$1"
  local file="$2"

  grep -q "$file" "$index" 2> /dev/null
}

cur_has_entry() {
  local file="$1"

  has_entry "${cur_mm_index}" "${file}"
}

update_index() {
  local index="$1"
  local file_path="$2"
  local date=$(date +%Y-%m-%d-%H:%M)

  if has_entry "${index}" "${file_path}" ; then
    sed -i "s|.* ${file_path}|${date} ${file_path}|" ${index}
    echo Updated.
  else
    echo "${date} ${file_path}" >> "${index}"
    echo Created.
  fi
}

new() {
  local fname="$1"
  local file="${cur_mm}/${fname}"

  mkdir -p "${cur_mm}"
  touch "${cur_mm_index}"

  touch "${file}"

  # update the root index.
  update_index "${mm_root_index}" "${cur_mm_index}"
  # update the local index.
  update_index "${cur_mm_index}" "${file}"

  echo "Create a ${fname} and start to track by mm."
}

open() {
  local file="${cur_mm}/$1"

  if ! cur_has_entry "${file}"; then
    echo "Not found the ${file}"
    exit 1
  fi

  # update the root index.
  update_index "${mm_root_index}" "${cur_mm_index}"

  # update the root index.
  update_index "${cur_mm_index}" "${file}"

  editor "${file}"
}

search_recursive() {
  local dir="$1"

  while [[ "${dir}" != "/" ]];
  do
    if [[ -d "${dir}/.mm" ]]; then
      echo "${dir}/.mm"
      return 0
    fi

    dir="$(dirname "${dir}")"
  done

  return 1
}

ls() {
  local region="local"
  if [ $# -eq 1 ]; then
    region="$1"
  fi

  case "$region" in
    local)
      local dir="$(search_recursive "$(pwd)")"
      if [[ -n "$dir" ]]; then
        cat "${dir}/index"
      else
        echo ".mm/ is not found in any parent directory."
      fi
      ;;
    all)
      cat "${mm_root_index}"
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
  local file="$(pwd)/.mm/$1"
  if ! cur_has_entry "${file}"; then
    echo not found
  fi

  # TODO
}

generate_snapshot_name() {
  local message="$1"
  local timestamp=$(date +%Y-%m-%d-%H:%M)
  
  if [ -n "$message" ]; then
    echo "${timestamp}-${message}"
  else
    echo "${timestamp}"
  fi
}

copy_root_index() {
  local snapshot_dir="$1"
  
  if [ -f "${mm_root_index}" ]; then
    cp "${mm_root_index}" "${snapshot_dir}/root_index"
    return 0
  else
    echo "Warning: ${mm_root_index} not found"
    return 1
  fi
}

copy_project_mm_dirs() {
  local snapshot_dir="$1"
  
  while IFS= read -r line; do
    if [ -n "$line" ] && [[ ! "$line" =~ ^# ]]; then
      local project_mm_path=$(echo "$line" | awk '{print $2}')
      copy_single_project_mm "$snapshot_dir" "$project_mm_path"
    fi
  done < "${mm_root_index}"
}

copy_single_project_mm() {
  local snapshot_dir="$1"
  local project_mm_index_path="$2"
  local project_mm_dir=$(dirname "$project_mm_index_path")
  
  if [ -d "$project_mm_dir" ]; then
    local project_dir=$(dirname "$project_mm_dir")
    local safe_path=$(echo "$project_dir" | sed 's|^/||' | tr '/' '_')
    cp -r "$project_mm_dir" "${snapshot_dir}/projects/${safe_path}"
    echo "Copied: $project_mm_dir"
  else
    echo "Warning: $project_mm_dir not found, skipping"
  fi
}

compress_snapshot() {
  local snapshot_dir="$1"
  local snapshot_name=$(basename "$snapshot_dir")
  
  cd "${mm_snapshots}"
  tar -cjf "${snapshot_name}.tar.bz2" "${snapshot_name}"
  
  if [ $? -eq 0 ]; then
    rm -rf "${snapshot_name}"
    echo "Compressed to: ${snapshot_name}.tar.bz2"
    return 0
  else
    echo "Warning: Failed to compress snapshot"
    return 1
  fi
}

snapshot_create() {
  local message=""
  if [ $# -ge 1 ]; then
    message="$1"
  fi
  
  local snapshot_name=$(generate_snapshot_name "$message")
  local snapshot_dir="${mm_snapshots}/${snapshot_name}"
  
  mkdir -p "${snapshot_dir}/projects"
  
  if ! copy_root_index "$snapshot_dir"; then
    return 1
  fi
  
  copy_project_mm_dirs "$snapshot_dir"
  
  echo "Snapshot created: ${snapshot_name}"
  
  if compress_snapshot "$snapshot_dir"; then
    echo "Snapshot successfully compressed and saved"
  fi
}

snapshot_list() {
  if [ ! -d "${mm_snapshots}" ]; then
    echo "No snapshots found"
    return 0
  fi
  
  echo "Available snapshots:"
  /bin/ls -1 "${mm_snapshots}" | grep -E '\.(tar\.bz2|tar\.gz)$|^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}:[0-9]{2}' | sort -r
}

snapshot_help() {
  printf "snapshot usage:\n"
  printf "\tmm snapshot create [message]\t: create a compressed snapshot of all memos\n"
  printf "\tmm snapshot list\t\t: list all snapshots\n"
  printf "\tmm snapshot help\t\t: show this snapshot help message\n"
}

snapshot() {
  if [ $# -lt 1 ]; then
    echo "snapshot subcommand required"
    snapshot_help
    exit 1
  fi
  
  local subcmd=$1
  shift
  
  case "$subcmd" in
    create)
      snapshot_create $@
      ;;
    list)
      snapshot_list
      ;;
    help)
      snapshot_help
      ;;
    *)
      echo "Unknown snapshot subcommand: $subcmd"
      snapshot_help
      exit 1
      ;;
  esac
}

arg_check(){
  local num="$1"
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
  snapshot)
    snapshot $@
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
