$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\Srt.ps1"
. "$root\extension\engine\lib\Alignment.ps1"
. "$root\extension\engine\lib\DtwEditTrial.ps1"
function Clone($Object){$Object | ConvertTo-Json -Depth 20 | ConvertFrom-Json}
function Reject([scriptblock]$Action,[string]$Message){try{& $Action}catch{if($_.Exception.Message -eq $Message){return};throw};throw "TRIAL_EXPECTED_REJECTION:$Message"}
# A direct legacy caller without a threshold must also protect a 0.5s source gap.
$gapCues=@(
    [pscustomobject]@{Index=1;Text='alpha.';Chapter=0;Confidence=1;Start=0;End=1;OriginalStart=0;OriginalEnd=1;CaptionTimingRevision='dtw-word-boundary-v1';CaptionWordTimings=@([pscustomobject]@{TargetWordIndex=0;Chapter=0;Text='alpha';Start=0.1;End=0.8;Exact=$true})},
    [pscustomobject]@{Index=2;Text='beta.';Chapter=0;Confidence=1;Start=1.2;End=2;OriginalStart=1.5;OriginalEnd=2.5;CaptionTimingRevision='dtw-word-boundary-v1';CaptionWordTimings=@([pscustomobject]@{TargetWordIndex=0;Chapter=0;Text='beta';Start=1.2;End=1.8;Exact=$true})}
)
$gapArgs=@{Cues=$gapCues;Voices=@([pscustomobject]@{start=0;end=3});Silences=@([pscustomobject]@{Start=0.85;End=1.15});FrameRate=30;LegacyFinder={return $null}}
$defaultGap=@(Get-PvsDtwBoundaryTrial @gapArgs)
if($defaultGap.Count -ne 1 -or $defaultGap[0].Reason -ne 'would-add-dialogue-gap'){throw 'TRIAL_DEFAULT_GAP_NOT_HALF_SECOND'}
$customGap=@(Get-PvsDtwBoundaryTrial @gapArgs -MinimumNoDialogueGap 1.5)
if($customGap.Count -ne 1 -or $customGap[0].Status -ne 'candidate'){throw 'TRIAL_CUSTOM_GAP_NOT_PRESERVED'}
$cuePicture=@(Get-PvsDtwBoundaryTrial @gapArgs -MinimumNoDialogueGap 1.5 -PreserveCuePictures)
if($cuePicture.Count -ne 1 -or $cuePicture[0].Status -ne 'unchanged' -or $cuePicture[0].Reason -ne 'cue-picture-anchors-already-planned' -or $cuePicture[0].CutFrame -ne $customGap[0].CutFrame){throw 'TRIAL_REPLANS_ALREADY_REFINED_CUE_PICTURE'}
$main=[pscustomobject]@{nodeId='video-node';start=0;end=4}
$linked=@([pscustomobject]@{nodeId='audio-node';start=0;end=4})
$voices=@([pscustomobject]@{path='fixture.mp3';start=0;end=4;inPoint=0;speedPercent=100})
$job=[pscustomobject]@{workflow='experimental-dtw-direct';editBoundaryTrial='dtw-additive-v1';sequence=[pscustomobject]@{sequenceId='live-template-id';frameRate=30;mainVideoClip=$main;linkedAudio=$linked;voices=$voices}}
$base=[pscustomobject]@{ok=$true;schemaVersion=8;plannerRevision=18;sequenceId='live-template-id';frameRate=30;mainVideoClip=$main;linkedAudio=$linked;voiceClips=$voices;mainVideoSourceEndFrame=120;plannedMainVideoEndFrame=120;plannedMainVideoEnd=4;captions=@([pscustomobject]@{Start=0.1;End=3.9;Text='Same text.'});segments=@([pscustomobject]@{Kind='retime';Chapter=0;SourceStartFrame=0;SourceEndFrame=120;NewStartFrame=0;NewEndFrame=120;OriginalVoiceStartFrame=0;OriginalVoiceEndFrame=120;LastTargetCue=2})}
Assert-PvsDtwTrialJob $job $base
$defaultJob=Clone $job;$defaultJob.workflow='one-click-dtw-direct'
Assert-PvsDtwTrialJob $defaultJob $base
$bad=Clone $job;$bad.PSObject.Properties.Remove('editBoundaryTrial')
Reject {Assert-PvsDtwTrialJob $bad $base} 'TRIAL_EXPLICIT_OPT_IN_REQUIRED'
$bad=Clone $job;$bad.workflow='one-click-direct'
Reject {Assert-PvsDtwTrialJob $bad $base} 'TRIAL_EXPLICIT_OPT_IN_REQUIRED'
$bad=Clone $base;$bad.schemaVersion=0;$bad.ok=$false
Reject {Assert-PvsDtwTrialJob $job $bad} 'TRIAL_STABLE_PLAN_REQUIRED'
$bad=Clone $base;$bad.mainVideoClip.nodeId='changed'
Reject {Assert-PvsDtwTrialJob $job $bad} 'TRIAL_BASELINE_JOB_MISMATCH'
$bad=Clone $job;$bad.sequence.linkedAudio=@()
Reject {Assert-PvsDtwTrialJob $bad $base} 'TRIAL_LIVE_TEMPLATE_REQUIRED'
$bad=Clone $base;$bad.voiceClips[0].path='different.mp3'
Reject {Assert-PvsDtwTrialJob $job $bad} 'TRIAL_BASELINE_VOICES_MISMATCH'
foreach($speed in @(50.0,90.0,100.000005,110.0,150.0)){
    $good=Clone $base;$good.voiceClips[0].speedPercent=$speed
    $inputJob=Clone $job;$inputJob.sequence.voices=$good.voiceClips
    Assert-PvsDtwTrialJob $inputJob $good
}
$bad=Clone $base;$bad.voiceClips[0].inPoint=1
$inputJob=Clone $job;$inputJob.sequence.voices=$bad.voiceClips
Reject {Assert-PvsDtwTrialJob $inputJob $bad} 'TRIAL_VOICE_MEDIA_IN_NONZERO:chapter-1;inPointSeconds=1;speedPercent=100'
foreach($speed in @(0.0,-100.0,[double]::NaN,[double]::PositiveInfinity)){
    $bad=Clone $base;$bad.voiceClips[0].speedPercent=$speed
    $inputJob=Clone $job;$inputJob.sequence.voices=$bad.voiceClips
    Reject {Assert-PvsDtwTrialInput $inputJob} 'TRIAL_VOICE_METADATA_INVALID:chapter-1'
}
$missing=Clone $job;$missing.sequence.voices[0].PSObject.Properties.Remove('inPoint')
Reject {Assert-PvsDtwTrialInput $missing} 'TRIAL_VOICE_METADATA_REQUIRED:chapter-1'
$cta=Clone $job;$cta.sequence.voices=@($cta.sequence.voices)+@([pscustomobject]@{start=7;end=9;speedPercent=110;inPoint=1})
Assert-PvsDtwTrialInput $cta
$cta | Add-Member algorithm ([pscustomobject]@{voiceGroupGapSeconds=10})
Reject {Assert-PvsDtwTrialInput $cta} 'TRIAL_VOICE_MEDIA_IN_NONZERO:chapter-2;inPointSeconds=1;speedPercent=110'
$candidate=Clone $base
$candidate.segments=@([pscustomobject]@{Kind='retime';Chapter=0;SourceStartFrame=0;SourceEndFrame=60;NewStartFrame=0;NewEndFrame=57;OriginalVoiceStartFrame=0;OriginalVoiceEndFrame=57;LastTargetCue=1},[pscustomobject]@{Kind='retime';Chapter=0;SourceStartFrame=60;SourceEndFrame=120;NewStartFrame=57;NewEndFrame=120;OriginalVoiceStartFrame=57;OriginalVoiceEndFrame=120;LastTargetCue=2})
$rows=@([pscustomobject]@{Status='candidate';Chapter=0;CutFrame=57;LeftCue=1})
Assert-PvsDtwTrialCuts $base $candidate $rows
$bad=Clone $candidate;$bad.segments[0].LastTargetCue=99
Reject {Assert-PvsDtwTrialCuts $base $bad $rows} 'TRIAL_CANDIDATE_CUT_NOT_USED'
$bad=Clone $candidate;$bad.segments[1].LastTargetCue=99
Reject {Assert-PvsDtwTrialCuts $base $bad $rows} 'TRIAL_EXISTING_CUT_MOVED'
$bad=Clone $candidate;$bad.linkedAudio[0].nodeId='wrong'
Reject {Assert-PvsDtwTrialCuts $base $bad $rows} 'TRIAL_PROTECTED_PLAN_FIELD_CHANGED:linkedAudio'
Reject {Assert-PvsDtwTrialCuts $base $candidate @()} 'TRIAL_UNEXPECTED_CUT_COUNT'
foreach($file in @('build-sentence-plan.ps1','run-alignment.ps1','run-captions.ps1')){
    if([IO.File]::ReadAllText("$root\extension\engine\$file").Contains('DtwEditTrial.ps1')){throw 'TRIAL_IMPORTED_BY_STABLE_PATH'}
}
$wrapper=[IO.File]::ReadAllText("$root\extension\engine\build-dtw-trial-plan.ps1")
foreach($forbidden in @('executePlan','evalScript','host.jsx')){if($wrapper.Contains($forbidden)){throw 'TRIAL_PLANNER_MUTATES_PREMIERE'}}
$main=[IO.File]::ReadAllText("$root\extension\js\main.js")
if($main -match 'localStorage\.[^(]+\([^\r\n]*(allowDtwTrial|dtwTrial)'){throw 'TRIAL_CONSENT_PERSISTED'}
$html=[IO.File]::ReadAllText("$root\extension\index.html")
if($html -match 'id="(allowDtwTrial|allowSpeedMerge|runDtwTrial)"'){throw 'DEFAULT_ALGORITHM_EXPOSED_AS_OPTION'}
& node (Join-Path $PSScriptRoot 'default-edit-ui.test.js')
if($LASTEXITCODE -ne 0){throw 'DEFAULT_EDIT_UI_FAILED'}
Write-Host 'DTW_EDIT_GATES_OK:default-and-legacy-protocol;variable-voice-speed;invalid-or-trimmed-input-rejected;CTA-scope;live-template;planner-isolation;cut-identity;conservation'
