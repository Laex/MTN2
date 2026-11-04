-- Reports the files marked in the active panel: how many, and the first
-- name. The notice is one short line, so the name is cut and the rest only
-- counted. Reads the state of the program only; sends no keys.
-- Ctrl+Alt+3, or Plugins menu.
macro {
  name = "Report marked files",
  area = "panels",
  requires = "has_selection",
  key = "Ctrl+Alt+3",
  menu = true,
  run = function()
    local files = mtn.selected()
    local first = files[1]:match("([^/]+)/*$") or files[1]
    if utf8.len(first) and utf8.len(first) > 30 then
      first = first:sub(1, utf8.offset(first, 28) - 1) .. "..."
    end
    local text = #files .. " marked: " .. first
    if #files > 1 then
      text = text .. " (+" .. (#files - 1) .. ")"
    end
    mtn.message(text)
  end,
}
