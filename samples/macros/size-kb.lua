-- Adds a "KB" column to the file panels: the size of each file in kilobytes.
-- The column is listed in the Columns dialog; folders are left empty.
mtn.column {
  id = "kb",
  title = "KB",
  width = 8,
  align = "right",
  value = function(f)
    if f.dir then
      return nil
    end
    return (f.size + 1023) // 1024
  end,
}
