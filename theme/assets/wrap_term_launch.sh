#!/usr/bin/env sh

cat ~/.local/state/astral-plasma/sequences.txt 2>/dev/null

exec "$@"
