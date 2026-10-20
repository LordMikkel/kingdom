#!/usr/bin/env bash

remove_metadata=false
prefix=""
target_files=()

# Function to display help menu
usage() {
  echo "Usage: $(basename "$0") [-m] [-h] <base_prefix> [file1 file2 ...]"
  echo ""
  echo "Options:"
  echo "  -m         Remove metadata using exiftool before renaming."
  echo "  -h, --help Show this help message and exit."
  echo ""
  echo "Description:"
  echo "  If no target files are specified, the script will rename ALL files"
  echo "  in the current directory."
  echo ""
  echo "Example:"
  echo "  $(basename "$0") -m new_name file1.png file2.png"
  echo "  $(basename "$0") new_name (Renames EVERYTHING in the current folder)"
  exit 0
}

# Parse arguments to handle flags, prefix, and multiple target files
while [[ "$#" -gt 0 ]]; do
  case $1 in
    -h|--help) usage ;;
    -m) remove_metadata=true; shift ;;
    -*) 
      # Catch any other dash-prefixed flag that does not exist
      echo "Error: Unknown option '$1'"
      usage 
      ;;
    *)
      if [ -z "$prefix" ]; then
        prefix="$1"
      else
        target_files+=("$1")
      fi
      shift
      ;;
  esac
done

# Check if the prefix is provided
if [ -z "$prefix" ]; then
  echo "Error: Missing prefix."
  usage
fi

# Check if exiftool is installed if the -m flag is used
if [ "$remove_metadata" = true ]; then
  if ! command -v exiftool >/dev/null 2>&1; then
    echo "Error: 'exiftool' is required to remove metadata."
    exit 1
  fi
fi

counter=1

# Function to process a single file
process_file() {
  local file="$1"
  
  # Check if it's a regular file and not the script itself
  if [ ! -f "$file" ] || [ "$file" = "$(basename "$0")" ]; then
    return
  fi

  # Remove metadata if the flag was provided
  if [ "$remove_metadata" = true ]; then
    exiftool -all= -overwrite_original "$file" >/dev/null 2>&1
  fi

  # Extract the extension of the original file
  local extension="${file##*.}"
  local new_name

  # Build the new name, preserving the extension if it exists
  if [ "$file" = "$extension" ]; then
    new_name=$(printf "%s_%02d" "$prefix" "$counter")
  else
    new_name=$(printf "%s_%02d.%s" "$prefix" "$counter" "$extension")
  fi

  # Rename using '--' for security against files starting with '-'
  mv -n -- "$file" "$new_name"
  ((counter++))
}

# Main execution logic
if [ ${#target_files[@]} -gt 0 ]; then
  # Process the specific files provided in the array
  for file in "${target_files[@]}"; do
    if [ ! -e "$file" ]; then
      echo "Warning: File '$file' does not exist. Skipping."
      continue
    fi
    process_file "$file"
  done
else
  # Ask for confirmation before processing the whole directory
  read -p "Are you sure you want to rename ALL files in the current directory? [y/N]: " confirm
  
  # Check whether the answer is 'y' or 'Y'
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    echo "Proceeding..."
    shopt -s nullglob
    for file in *; do
      process_file "$file"
    done
    shopt -u nullglob
  else
    exit 0
  fi
fi

echo "Renaming complete. Processed $((counter - 1)) files."
