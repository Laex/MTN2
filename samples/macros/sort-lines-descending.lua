-- Sorts the lines of the selection (or of the whole document when nothing
-- is selected) in descending order.
-- Ctrl+Alt+4, or Plugins menu.
macro {
  name = "Sort lines descending",
  area = "editor",
  requires = "editable",
  key = "Ctrl+Alt+4",
  menu = true,
  run = function()
    if not mtn.state().editor_has_selection then
      mtn.key("Ctrl+A")
    end
    mtn.action("EditorSortLinesDesc")
  end,
}
