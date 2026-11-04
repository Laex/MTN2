-- Creates a folder named "New folder" in the active panel: opens the
-- make-folder dialog (F7), types the name and confirms with Enter.
-- Works on a local folder only. Ctrl+Alt+2, or Plugins menu.
macro {
  name = "Make folder \"New folder\"",
  area = "panels",
  key = "Ctrl+Alt+2",
  menu = true,
  run = function()
    if mtn.state().panel_kind ~= "file" then
      mtn.message("Open a local folder first")
      return
    end
    mtn.key("F7")
    mtn.text("New folder")
    mtn.key("Enter")
  end,
}
