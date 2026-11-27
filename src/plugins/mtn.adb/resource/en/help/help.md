# Android devices (adb)

The plugin adds **Android** (`adb:///`) to the Change Drive list (Alt+F1 / Alt+F2). It runs the `adb` program of the Android platform-tools, which must be in PATH.

## Getting a device ready

1. On the device turn on the developer options and **USB debugging**.
2. Connect the cable and allow debugging for this computer in the question on the device screen. A device on the network is connected with `adb connect <address>` in a terminal.
3. On Linux the user needs access to the USB device (udev rules of the distribution).

## The list of devices

Each connected device is a folder named by its serial number. A ready device is green; a yellow one cannot be used yet, and its State column says why: `unauthorized` (answer the question on the device), `offline` (reconnect), `no permissions` (udev rules). Opening such a device shows the reason. Ctrl+R reads the list again.

## Files of a device

| Key | Action |
|---|---|
| F3, F4 | view a file; edit and save it |
| F5 | copy between the device and a local folder, or inside the device |
| F6 | rename, move inside the device; moving to or from a local folder copies and then deletes |
| F7 | make a folder |
| F8 | delete a file or a folder with its content (there is no recycle bin) |

Android 7 or later is needed. Without root a part of the system folders is closed; the shared storage is in `sdcard`. Copying between two devices is not supported - copy through a local folder. Viewing and editing pass the file through the program, so large files are better copied with F5.

Columns: in the Custom column mode (**Columns...**) the list of devices can show State, Model and Product.
