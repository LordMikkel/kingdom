#!/usr/bin/env bash
# Toggle voxtype dictation with the microphone live only while recording.
#
# The microphone stays muted the rest of the time. On start this unmutes it;
# on stop it asks voxtype to transcribe and paste, then mutes it again.
# Bound to CTRL+SHIFT+Space in ~/.config/caelestia/hypr-user.lua.

case "$(voxtype status)" in
    idle)
        pactl set-source-mute @DEFAULT_SOURCE@ 0
        voxtype record start
        ;;
    recording)
        voxtype record stop
        # Give the daemon a moment to close the audio stream.
        sleep 0.3
        pactl set-source-mute @DEFAULT_SOURCE@ 1
        ;;
    *)
        # Still transcribing: ignore the key press.
        ;;
esac
