# Git status

The status line shows the git state of the folder of the active panel as colored badges: the branch, commits ahead and behind, staged, modified, new and conflicted files, or `clean`.

The file names in the panels are colored by their git state.

| Key | Action |
|---|---|
| Ctrl+Shift+G | show the git diff of the file under the cursor in the viewer |

## Plugins menu

- **Git: add to the index** and **Git: remove from the index** work on the marked files and folders, or on the one under the cursor when nothing is marked. Deletions inside a folder are added with it. Removing from the index leaves the files as they are.
- **Git: commit...** shows what is in the index and asks for a one-line message. The message of a commit that failed is kept for the next try.
- **Git: switch branch...** switches to a local branch you pick. git refuses when that would overwrite local changes.

The commands run in the background and can be cancelled in the job list. A long answer of git, a refused hook for one, opens in the viewer. Pull, push and stash are done in the console.

`git` must be in PATH. A folder outside a repository shows nothing.
