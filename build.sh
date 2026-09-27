#!/usr/bin/env bash
# we just dump the binary in the root directory for simplicity
mkdir build
odin build app_raylib -out:build/hirsiz
