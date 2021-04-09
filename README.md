# lepasd
Storage-less labeled password derivation daemon

This password derivation tool is something I would use personally, having strict requirements for password management:
- no 3rd party or cloud service
- portable: no fetching or synchronizing a vault; usable on any Linux machine
- storage-less: nothing on the filesystem can be used to reproduce a password after a power-off
- secure: proven key derivation (Argon2), open, no backdoors
- easy to change or update a single password
- the main password is rarely entered (once it's needed after a reboot)

Once chosen, the main password should be considered fixed. Changing it would require updating all derived passwords in use.

### Install
Prerequisites: Linux, git, make, C and D compilers. Replace ```REPOS``` with desired path.
```
$ cd ~/REPOS
$ git clone --recursive https://github.com/isrvoid/lepasd.git
$ cd lepasd
$ RELEASE=1 make
$ sudo ln -s ~/REPOS/lepasd/bin/lepasd /usr/local/bin
```

### Attacks
#### Main password
- weak: can be brute-forced if a derived password is leaked
- not unique: is leaked somewhere else and tried as seed by an attacker
- compromised machine: read from the keyboard when entered
#### Daemon process
- compromised machine: attacker dumps process memory and recovers the SHA3 context; context is used to generate passwords
- process memory is stored: swap or hibernate writes the process memory to drive; the SHA3 context could be recovered from an improperly disposed drive
- compromised machine: attacker interacts with running daemon to generate passwords
- unattended, unlocked machine: another person interacts with running lepasd to generate passwords

### Mitigation
Use a unique phrase or a combination of words as the main password. Don't reuse the exact or similar phrase anywhere else. Only run lepasd on a secure machine. Kill the daemon before leaving, if an untrusted administrator might have intermediate access. Lock the screen or log out before leaving, when other people can access the machine. Wipe any unencrypted drives or disks before disposal.
