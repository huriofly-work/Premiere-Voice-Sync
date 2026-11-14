$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$tempRoot=Join-Path $root '.tmp-edited-reference-tests'
$temp=Join-Path $tempRoot ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -Force | Out-Null
try{
    $source=Join-Path $root 'extension\engine';$engine=Join-Path $temp 'engine'
    New-Item -ItemType Directory -Path (Join-Path $engine 'lib'),(Join-Path $engine 'runtime') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $source 'build-sentence-plan.ps1') -Destination $engine
    Get-ChildItem -LiteralPath (Join-Path $source 'lib') -File | Copy-Item -Destination (Join-Path $engine 'lib')
    foreach($name in @('runtime-lock.json','cuda-lock.json')){Copy-Item -LiteralPath (Join-Path $source $name) -Destination $engine}
    Set-Content -LiteralPath (Join-Path $engine 'lib\Native.ps1') -Encoding ASCII -Value '. "$PSScriptRoot\Security.ps1"; . "$PSScriptRoot\AudioCache.ps1"; function Invoke-NativeCapture {param($FilePath,$Arguments);[pscustomobject]@{ExitCode=0;Output=""}}'
    Set-Content -LiteralPath (Join-Path $engine 'runtime\engine.json') -Encoding ASCII -Value '{"ffmpeg":"fixture"}'
    . "$source\lib\ReferenceAlignment.ps1"
    . "$source\lib\SpeedMergeTrial.ps1"
    . "$source\lib\DtwEditTrial.ps1"
    $cues=@(for($i=0;$i -lt 7;$i++){[pscustomobject]@{Index=$i+1;Start=$i*3.0;End=($i+1)*3.0;Text="Cau$i giu nguyen chu nguon day."}})
    $words=@();$word=0
    foreach($i in @(0,3,6)){foreach($text in @(ConvertTo-NormalizedWords $cues[$i].Text)){$words+=[pscustomobject]@{Text=$text;Start=$word*0.1;End=(++$word)*0.1;Chapter=0}}}
    $wav=Join-Path $temp 'voice.wav';Set-Content -LiteralPath $wav -Encoding ASCII -Value ''
    $voices=@([pscustomobject]@{start=0.0;end=1.8;path=$wav;name='voice.wav';speedPercent=100;inPoint=0})
    $edited=Resolve-PvsEditedReference $cues $words $voices {
        param($voice,$start,$end)
        foreach($w in $words){if($w.Start -ge $start-0.000001 -and $w.End -le $end+0.000001){[pscustomobject]@{Text=$w.Text;Start=$w.Start-$start;End=$w.End-$start;Chapter=0}}}
    }
    foreach($fps in @(30.0,29.97)){
        $folder=Join-Path $temp ([string]$fps);New-Item -ItemType Directory -Path $folder | Out-Null
        $main=[pscustomobject]@{start=0.0;end=21.0}
        $map=New-PvsEditedSourceMap $edited $cues $main $fps
        [ordered]@{voiceChapterCount=1;cues=$edited.Cues;editedSourceMap=$map;omittedReferenceCueIndices=$edited.OmittedCueIndices} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $folder 'alignment-result.json') -Encoding UTF8
        $job=[ordered]@{algorithm=[ordered]@{useWhisperCache=$false};outputFolder=$folder;speedWarningMinPercent=70;speedWarningMaxPercent=130;sequence=[ordered]@{sequenceId='edited';name='edited';frameRate=$fps;mainVideoClip=$main;linkedAudio=@();voiceTrackIndex=1;voices=$voices}}
        $jobPath=Join-Path $folder 'job.json';$job | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jobPath -Encoding UTF8
        & "$engine\build-sentence-plan.ps1" -JobPath $jobPath | Out-Null
        $plan=Get-Content -LiteralPath (Join-Path $folder 'sentence-edit-plan.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        if($plan.summary.captionCueCount -ne 3 -or $plan.summary.longNoDialogueGapCount -ne 0 -or $plan.summary.safeSentenceGroupCount -ne 1 -or $plan.summary.omittedReferenceCueCount -ne 4){throw 'EDITED_PLANNER_REINSERTED_DELETED_PICTURE_OR_CAPTIONS'}
        if(($plan.captions.Text -join '|') -cne ($cues[0,3,6].Text -join '|')){throw 'EDITED_PLANNER_TEXT_CHANGED'}
        $null=Assert-PvsTrialPlanConservation $plan ($plan | ConvertTo-Json -Depth 20 | ConvertFrom-Json)
        $balanced=Get-PvsSpeedMergeTrial $plan
        $balancedPath=Join-Path $folder 'balanced.json';$balanced | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $balancedPath -Encoding UTF8
        & node (Join-Path $root 'tests\helpers\Check-EditedSourcePlan.js') $balancedPath
        if($LASTEXITCODE -ne 0){throw 'EDITED_PLANNER_HOST_MAP_FAILED'}
    }
    Write-Host 'EDITED_PLANNER_OK:real-planner;subtitle-output;no-added-pauses;30,29.97fps;DTW;speed-merge;host-expansion'
}finally{
    $full=[IO.Path]::GetFullPath($temp)
    if(-not $full.StartsWith(([IO.Path]::GetFullPath($tempRoot).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'UNSAFE_TEST_CLEANUP'}
    if(Test-Path -LiteralPath $full){Remove-Item -LiteralPath $full -Recurse -Force}
}
