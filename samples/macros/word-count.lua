-- Counts the lines and words of the selection (or the whole document when
-- nothing is selected) and shows them in a notice. Reads the editor only.
-- Ctrl+Alt+4, or Plugins menu.
macro {
  name = "Count words",
  area = "editor",
  key = "Ctrl+Alt+4",
  menu = true,
  run = function()
    local text = mtn.editor.selection()
    if not text or text == "" then
      text = mtn.editor.text() or ""
    end
    local lines, words = 0, 0
    for line in (text .. "\n"):gmatch("(.-)\n") do
      lines = lines + 1
      for _ in line:gmatch("%S+") do
        words = words + 1
      end
    end
    mtn.message(lines .. " lines, " .. words .. " words")
  end,
}
