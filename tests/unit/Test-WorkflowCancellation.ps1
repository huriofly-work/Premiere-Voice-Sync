$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
foreach($file in @('workflow-cancellation.test.js','workflow-pause.test.js','workflow-process.test.js','workflow-pause-host.test.js')) {
    & node (Join-Path $PSScriptRoot $file)
    if($LASTEXITCODE -ne 0){throw "WORKFLOW_CANCELLATION_FAILED:$file"}
}
