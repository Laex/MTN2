-- Centers the lines of the selection (or of the whole document when nothing
-- is selected) within the right margin.
-- Ctrl+Alt+5, or Plugins menu.
macro {
  name = "Center lines",
  area = "editor",
  requires = "editable",
  key = "Ctrl+Alt+5",
  menu = true,
  run = function()
    if not mtn.state().editor_has_selection then
      mtn.key("Ctrl+A")
    end
    mtn.action("EditorAlignCenter")
  end,
}
