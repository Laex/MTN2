$s = @'
$ProgressPreference = 'SilentlyContinue'
while ($null -ne ($line = [Console]::In.ReadLine())) {
  if ($line) {
    $result = Invoke-Expression $line
    if ($null -ne $result) {
      @($result) | Format-Table -AutoSize | Out-String -Width 4096
    }
  }
}
'@
$bytes = [System.Text.Encoding]::Unicode.GetBytes($s)
[Convert]::ToBase64String($bytes)
