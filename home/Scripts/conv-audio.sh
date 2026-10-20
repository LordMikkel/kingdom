#!/usr/bin/env bash

# Check if at least one argument is provided
if [ "$#" -eq 0 ]; then
    echo "Usage: conv-audio <input_file> [input_file2 ...]"
    exit 1
fi

# Loop through all provided arguments
for INPUT in "$@"; do
    # Check if the file actually exists
    if [ ! -f "$INPUT" ]; then
        echo "⚠️ Error: File '$INPUT' does not exist. Skipping..."
        continue
    fi

    # Extract the base name (without extension)
    BASENAME="${INPUT%.*}"
    OUTPUT="${BASENAME}.mov"
    TEMP_OUTPUT="${BASENAME}_tmp.mov"

    echo "Processing '$INPUT'..."

    # Run ffmpeg (suppressing excessive output)
    if ffmpeg -i "$INPUT" -c:v copy -c:a pcm_s32le -y "$TEMP_OUTPUT" -hide_banner -loglevel warning; then
        # If successful, delete the original and keep the new .mov
        rm "$INPUT"
        mv "$TEMP_OUTPUT" "$OUTPUT"
        echo "✅ Success: Original deleted. New file ready"
    else
        # If it failed, clean up the temporary file and warn the user
        echo "❌ Error during conversion of '$INPUT'. Original is intact."
        rm -f "$TEMP_OUTPUT"
    fi
done
