# Firejail

* fails to start when including the display server in sandbox (i.e., "--x11"). With XPRA installed, Firejail tries using it, but fails due to the same problem of non-console users trying to start an X server.
* version in Ubuntu repo is old
* how does it call xpra? Use as guide for calling with lxd. `xpra start :100 --no-daemon`

## Firejail Dependencies

firejail, firejail-profiles

## Openbox Dependencies

giblib1, gnome-icon-theme, libfm-extra4, libgif7, libid3tag0, libimlib2, libmenu-cache-bin, libmenu-cache3, libobrender32v5, libobt2v5, obconf, obsession, openbox, openbox-menu, scrot

# XPRA

* fails to start. The fix is to allow non-console users to start X servers. Change "allowed_users=console" to "allowed_users=anybody". Security risk? Can a rogue app now trick user with malicious windows? But if they have that access, can't they do other things? Would need root, but can we temporarily change this on-demand when we start xpra?
* commandline
  * in container, start the server: `xpra start :100 --daemon=no --debug=all --mdns=no --socket-dir=$PWD --bind=$PWD/browser --auth=peercred --socket-permissions=660`
  * in container, start client app either by including in server start command with `--start=firefox` or start separately like `DISPLAY=:100 firefox`
  * on host, attach client display: `xpra attach socket:path_to_socket_file`
* permission errors when telling xpra server to create sockets in home directory. Workaround is to link to home directory in container

## Dependencies

freeglut3, libgtkglext1, libpango1.0-0, libpangox-1.0-0, python-gobject-2, python-gtk2, python-gtkglext1, python-lz4, python-lzo, python-olefile, python-opengl, python-pil, python-rencode, ssh-askpass, xpra, xserver-xorg-input-void, xserver-xorg-video-dummy

## TODO

* should we start container on host boot? and keep running after app instance closes?
* how to handle client closing GUI window
  * use `systemd-run` config param?
  * "attach" script starts and stops container per script invocation. Assumes container is first stopped
* convert to Python and merge into one frontend script with subcommands
* prompt user about non-empty file share bind mount when exiting app?
* unprivileged containers make file sharing with host more complex. Do we get much security benefit at this cost?
  * the crux of the problem is that some parts of the kernel are not namespace aware and so they see uid 0 and assume process is from real root user
  * [Linux sandboxing improvements in Firefox 60](https://www.morbo.org/2018/05/linux-sandboxing-improvements-in_10.html)
  * [Firejail GitHub issue - Implications of CONFIG_USER_NS](https://github.com/netblue30/firejail/issues/1347)
   * with user namespaces, when things go wrong, you blame the kernel devs. With setuid, you blame the app and can probably fix it more easily than waiting on a kernel patch
  * [Oz GitHub issue - User namespaces not used?](https://github.com/subgraph/oz/issues/11)

### xpra Management
* start xpra on container boot
  * cloud-init runcmd is only once per instance
  * hooks in raw.lxc are too early in boot
  * make a systemd service?
  * scripts-per-boot works. Can we get it managed by systemd? xpra has a commandline "--systemd-run"
  * TODO: need ability to pass app arguments and multiple app instances
* start xpra from host per app instance
  * too slow to start xpra server? Attaching client already takes several seconds

### IO
* set up audio
  * test with `pactl info`
* set up graphics acceleration
  * test with `glxgears`
* check out at least the following options affecting IO between host and container
  * clipboard
  * webcam
  * speaker
  * microphone
  * notifications
  * dbus-proxy
  * is there a printer config option?
  * file-transfer
  * cursors
  * bell
  * open-url
  * open-files
  * forward-xdg-open
  * printing
* ask user to map file-to-be-opened into container so they can directly pass filenames to target app via "attach" script
  * particularly useful when a user's file manager uses the script to access target file
  * need to address file ownership and permissions
   * temporary files are undesirable
   * transparently change ownership and permissions?
  * can bind mount a file into container

### Performance
* fix errors in xpra client and server logs
* improve performance by modifying "encoding" config param
* improve attach time

