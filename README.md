# mkautofshomedir.sh: Bash equivalent of PAM's mkhomedir_helper.c with preflight mkdirs for autofs maps

## Description

This script will enable automatic home directory creation when /home is served as an autofs map with user-specific home backend directories. In browse-enabled mode (historically ghost mode), autofs will make mount points visible in /home even though they may not exist in the actual backend, thus preventing automatic home directory creation with the traditional pam_mkhomedir.so PAM module. In addition to this, direct mkdirs in an autofs-mapped /home may also be restricted. This script addresses these issues by reimplementing the logic behind the PAM's mkhomedir_helper.c, and additionally issuing preflight mkdirs in the home backend directories that are configured in autofs and supplied as arguments to this script. At the end of the execution, excess preflight directories are cleaned up, leaving only the actual user's home directory in the relevant backend.

## Usage

The script will be called by pam_exec. It uses the PAM_USER and PAM_TYPE environment variables, and additionally accepts a number of arguments described below.

**In /etc/pam.d/common-session, add before pam_mkhomedir.so:**

```session optional pam_exec.so [seteuid] [stdout] /path/to/mkautofshomedir.sh [umask] [skeldir] [homemode] [preflightdir_1] [preflightdir_2] [...] [preflightdir_n]```

**pam_exec.so arguments:**
* seteuid: Add this if /path/to/mkautofshomedir.sh is only executable by root
* stdout: Add this to print additional information during script execution at login

**mkautofshomedir.sh arguments:**
* umask: Defaults to 0022
* skeldir: Defaults to /etc/skel
* homemode: Defaults to 0700
* preflightdirs: None by default, add any preflight home directories, e.g. /srv/homes/local, /srv/homes/nfs, etc.
