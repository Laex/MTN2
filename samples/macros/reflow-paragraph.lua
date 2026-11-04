-- Re-wraps the selected text (or the whole document) to the right margin.
-- Ctrl+Alt+6, or Plugins menu.
macro {
  name = "Reflow text",
  area = "editor",
  requires = "editable",
  key = "Ctrl+Alt+6",
  menu = true,
  run = function()
    if not mtn.state().editor_has_selection then
      mtn.key("Ctrl+A")
    end
    mtn.action("EditorReflow")
  end,
}
