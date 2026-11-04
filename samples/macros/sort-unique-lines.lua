-- Sorts the lines of the open document and removes repeated lines.
-- Runs in the editor only, and only when the document can be edited.
-- Ctrl+Alt+1, or Plugins menu.
macro {
  name = "Sort and deduplicate lines",
  area = "editor",
  requires = "editable",
  key = "Ctrl+Alt+1",
  menu = true,
  run = function()
    if not mtn.state().editor_has_selection then
      mtn.key("Ctrl+A")            -- no selection: take the whole document
    end
    mtn.action("EditorSortLines")
    mtn.action("EditorUniqueLines")
  end,
}
