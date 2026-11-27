# Temporary panel

The Temporary entry of the Change Drive list (Alt+F1 / Alt+F2) opens `tmp:///`: a panel that holds a list of files and folders collected from anywhere. The files stay where they are; F7 removes them from the list, F8 deletes the files themselves.

- Plugins menu, Panel from command output: runs a command and lists the existing file and folder names it prints.
- Plugins menu, Find duplicate files: scans the folder of the active panel and lists files with identical content.
- Plugins menu, Mark duplicate copies: after that search, marks the spare copies in the temporary panel. One copy per group stays unmarked: the newest, the oldest or the one with the shortest path; or every copy under a chosen folder stays, and groups with no copy there are left alone. Files changed since the search are not marked. Nothing is deleted until F8.
- F5 and F6 copy and move the listed files like in any panel.
