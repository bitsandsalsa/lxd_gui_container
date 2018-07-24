# Introduction

These are example freedesktop.org [desktop files](https://specifications.freedesktop.org/desktop-entry-spec/latest/) to make launching containerized apps more user friendly and integrated into your desktop system.

# Usage

1. Find the icons you want to use for the app. One way to find them is to install app in a container or VM and search in the "icons" directory of one of the directories in $XDG_DATA_DIRS.

2. Install each of the variably sized icons:

   ```
   $ xdg-icon-resource \
   install \
   --size 32 \
   --novendor \
   /tmp/icons/hicolor/32x32/apps/myapp.png
   ```

   You should then see these in *~/.local/share/icons/*.

3. Install the desktop file:

   `$ xdg-desktop-menu install containerized-app.desktop`

   You should then see this in *~/.local/share/applications*.

