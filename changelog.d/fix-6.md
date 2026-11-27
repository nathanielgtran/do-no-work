install.sh always wires the shell rc even without git identity (it used to return early when GIT_NAME was unset and there was no TTY); the identity hint still prints
