#!/usr/bin/env bash

set -ex

command_exists() {
	command -v "$1" >/dev/null 2>&1
}

if [[ "$OSTYPE" == "darwin"* ]]; then
	echo "You are running macOS."

	if command_exists nix; then
		echo "Looks like you have nix set up already. Nice!"

	else
		echo "Looks like Nix is not installed, doing so now. Pleaes follow the prompts."
        sh <(curl -L https://nixos.org/nix/install)
	fi

	# Continue with the rest of the script for macOS
	# ...

elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
	echo "You are running Linux."
	# Add Linux-specific instructions here
	# ...

else
	echo "Unsupported operating system."
	exit 1
fi


glow (ls)
