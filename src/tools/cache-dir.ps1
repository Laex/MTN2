# Prints the folder where builds keep files that are expensive to fetch or
# rebuild, between runs: the wasmtime runtime and the Rust plugin's target
# folder. Prints nothing when no such folder is configured, and callers then
# keep those files in the source tree as usual.
#
# The folder is $env:MTN2_CACHE, or on a GitHub Actions runner the runner's
# tool cache. The tool cache sits outside the checkout, so it survives the
# `git clean -ffdx` that actions/checkout runs before every job.
$Dir = $env:MTN2_CACHE
if (-not $Dir -and $env:GITHUB_ACTIONS -eq 'true' -and $env:RUNNER_TOOL_CACHE) {
    $Dir = Join-Path $env:RUNNER_TOOL_CACHE 'mtn2'
}
if ($Dir) {
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    $Dir
}
