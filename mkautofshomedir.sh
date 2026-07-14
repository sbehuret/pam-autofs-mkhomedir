#!/bin/bash

set -euo pipefail

# Default values
DEFAULT_UMASK='0022'
DEFAULT_SKELDIR='/etc/skel'
DEFAULT_HOMEMODE='0700'

# Get username from PAM environment variable
USERNAME="${PAM_USER:-}"

# Get umask, skeldir and preflightdirs parameters
UMASK="${1:-$DEFAULT_UMASK}"
SKELDIR="${2:-$DEFAULT_SKELDIR}"
HOMEMODE="${3:-$DEFAULT_HOMEMODE}"
PREFLIGHTDIRS=("${@:4}")

# Validate username
if [ -z "$USERNAME" ] ; then
	echo "Error: PAM_USER environment variable not set" >&2
	exit 1
fi

# Check PAM_TYPE - only run during session phase
if [ "${PAM_TYPE:-}" != 'open_session' ] ; then
	# Silently exit if not in the correct PAM phase
	exit 0
fi

# Get user information
if ! USER_INFO=$(getent passwd "$USERNAME" 2>/dev/null) ; then
	echo "Error: User '$USERNAME' not found" >&2
	exit 1
fi

# Parse user info
IFS=':' read -r username password uid gid gecos homedir shell <<< "$USER_INFO"

# Check if home directory already exists - Add a trailing slash to traverse autofs maps
if [ -d "$homedir/" ] ; then
	echo "Home directory '$homedir' already exists"
	exit 0
fi

# Check preflight home directories
if [ ${#PREFLIGHTDIRS[@]} -gt 0 ] && [[ "$homedir" =~ ^/home/([^/]+)$ ]] ; then
	realhome="$(realpath /home)"

	for preflightdir in "${PREFLIGHTDIRS[@]}"; do
		if [ ! -d "$preflightdir" ] ; then
			echo "Warning: Ignoring missing preflight home directory '$preflightdir'" >&2
		fi

		realpreflightdir="$(realpath "$preflightdir")"

		if [ "$realpreflightdir" = '/' -o "$realpreflightdir" = "$realhome" ] ; then
			echo 'Error: Dangerous use of / or /home as preflight home directory' >&2
			exit 1
		fi
	done
fi

# Get parent directory
parent_dir=$(dirname "$homedir")

# Create parent directory if it doesn't exist
if [ ! -d "$parent_dir" ] ; then
	if ! mkdir -p "$parent_dir" ; then
		echo "Error: Failed to create parent directory '$parent_dir'" >&2
		exit 1
	fi
fi

# Set umask
umask "$UMASK"

# Create preflight home directories
if [ ${#PREFLIGHTDIRS[@]} -gt 0 ] && [[ "$homedir" =~ ^/home/([^/]+)$ ]] ; then
	homename="${BASH_REMATCH[1]}"

	for preflightdir in "${PREFLIGHTDIRS[@]}"; do
		if [ ! -d "$preflightdir" ] ; then
			continue
		fi

		echo "Processing preflight home directory: $preflightdir"

		if ! mkdir "$preflightdir/$homename" ; then
			echo "Error: Failed to create preflight home directory '$preflightdir/$homename'" >&2
			exit 1
		fi
	done

	if systemctl -q is-active autofs.service && ! systemctl restart autofs.service ; then
		echo 'Error: Failed to restart autofs' >&2
		exit 1
	fi
# Standard home mkdir
else
	if ! mkdir "$homedir" ; then
		echo "Error: Failed to create home directory '$homedir'" >&2
		exit 1
	fi
fi

# Copy skeleton files if skeleton directory exists
if [ -d "$SKELDIR" ] ; then
	# Copy all files from skeleton directory, including hidden files
	if ! cp -r "$SKELDIR"/. "$homedir/" 2>/dev/null ; then
		echo "Warning: Failed to copy some skeleton files from '$SKELDIR'" >&2
	fi
else
	echo "Warning: Skeleton directory '$SKELDIR' does not exist" >&2
fi

# Set ownership recursively
if ! chown -R "$uid:$gid" "$homedir" ; then
	echo "Error: Failed to set ownership of '$homedir'" >&2
	exit 1
fi

# Set permissions on home directory
if ! chmod "$HOMEMODE" "$homedir" ; then
	echo "Error: Failed to set permissions on '$homedir'" >&2
	exit 1
fi

# Cleanup preflight home directories
if [ ${#PREFLIGHTDIRS[@]} -gt 0 ] && [[ "$homedir" =~ ^/home/([^/]+)$ ]] ; then
	homename="${BASH_REMATCH[1]}"

	for preflightdir in "${PREFLIGHTDIRS[@]}"; do
		if [ ! -d "$preflightdir" ] ; then
			continue
		fi

		if [ -d "$preflightdir/$homename" -a -z "$(ls -A "$preflightdir/$homename" 2>/dev/null)" ] ; then
			echo "Removing preflight home directory '$preflightdir/$homename'"
			rm -rf "$preflightdir/$homename"
		fi
	done

	if systemctl -q is-active autofs.service && ! systemctl restart autofs.service ; then
		echo 'Error: Failed to restart autofs' >&2
		exit 1
	fi
fi

# Check if home directory already exists - Add a trailing slash to traverse autofs maps
if [ -d "$homedir/" ] ; then
	echo "Successfully created home directory '$homedir' for user '$username'"
	exit 0
else
	echo "Error: Creation of home directory '$homedir' for user '$username' failed"
	exit 1
fi
