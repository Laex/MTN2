# Native window (C++)

Shows how a plugin gets a window of its own inside the program.

## Use

Press **Ctrl+Shift+G** over the file panels. A tab opens; its area is a window drawn by the plugin: a gradient, a bouncing ball and a mark where you click. **Space** pauses the ball, **Esc** closes the tab. A dialog or the menu opened over the tab hides the window until it is closed.

## For authors

Source: `samples/plugins/mtn.demo.nativeview/plugin.cpp`. The plugin opens a surface with `surface_open_ex` and the native flag (256 added to the mode), reads the handle of the area with `surface_native_handle` and creates its own child window in it. The program keeps the area over the cells of the tab, hides it under dialogs and menus, and resizes the windows inside it to fill it; mouse messages go straight to the plugin window, while keys reach the plugin through the surface callback. A player that draws into a window (libmpv) is given the same handle as its output window. See `docs/PLUGIN_DEVELOPMENT.md`, section "Pictures and video".
