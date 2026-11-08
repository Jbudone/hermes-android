#!/data/data/com.termux/files/usr/bin/bash
# ask-hermes.sh — ask the on-device Hermes a question and print the answer.
# Designed for Termux:Tasker: put this in ~/.termux/tasker/, point a plugin
# action at it, pass the prompt as Arguments, read the answer from %stdout.
#
#   ask-hermes.sh "what is eating my battery?"
set -e
export PATH="/data/data/com.termux/files/usr/bin:$PATH"
PROMPT="$*"
[ -n "$PROMPT" ] || { echo "usage: ask-hermes.sh <prompt>"; exit 2; }
exec hermes chat -q "$PROMPT"
