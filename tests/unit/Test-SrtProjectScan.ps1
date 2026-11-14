$ErrorActionPreference='Stop'
foreach($test in @('srt-scan-host.test.js','srt-scan-ui.test.js')){
    & node (Join-Path $PSScriptRoot $test)
    if($LASTEXITCODE -ne 0){throw "SRT_PROJECT_SCAN_FAILED:$test"}
}
