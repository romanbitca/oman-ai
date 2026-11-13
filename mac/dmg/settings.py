# dmgbuild's settings for OmanAI's disk image: the app beside a link to Applications, over a picture that says to
# drag one onto the other. scripts/make-dmg.sh passes the app and the picture with -D app=… -D background=….
# dmgbuild runs this file with `defines` already set.
import os.path

application = defines["app"]  # noqa: F821
appname = os.path.basename(application)

format = "ULMO"
files = [application]
symlinks = {"Applications": "/Applications"}
hide_extensions = [appname]
icon = os.path.join(application, "Contents", "Resources", "AppIcon.icns")

# background@2x.png beside it is picked up too, so the window is sharp on a Retina screen.
background = defines["background"]  # noqa: F821
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

# The picture is 660 by 400 points. The window is taller by its title bar.
window_rect = ((200, 140), (660, 428))
default_view = "icon-view"
icon_size = 128
text_size = 13
# The centres of the icons, which the arrow in the picture runs between.
icon_locations = {appname: (180, 210), "Applications": (480, 210)}
