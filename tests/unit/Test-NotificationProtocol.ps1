$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
Add-Type -Path (Join-Path $root 'extension\native\NotificationProtocol.cs')
$script:checks=0
function Valid-Command {
 $d=New-Object 'Collections.Generic.Dictionary[string,object]'
 $d['sessionId']='a'*32;$d['incidentId']='incident-1';$d['runId']='run-1';$d['type']='incident'
 $d['kind']='completed';$d['workflow']='captions';$d['toast']=$false;$d['panelVisible']=$false;$d['hasWarnings']=$false;$d['playSound']=$false
 return ,$d
}
function Check($d,[bool]$expected){if([PvsNotificationProtocol]::IsValid($d) -ne $expected){throw 'PROTOCOL_VALIDATION_FAILED'};$script:checks++}
Check $null $false;Check (Valid-Command) $true
foreach($field in @('sessionId','incidentId','runId','type','kind','workflow','toast','playSound','panelVisible','hasWarnings')){
 $d=Valid-Command;$d.Remove($field)|Out-Null;Check $d $false
 foreach($value in @($null,42)){$d=Valid-Command;$d[$field]=$value;Check $d $false}
}
foreach($type in @('clear','hide-toast','observe')){$d=Valid-Command;$d['type']=$type;Check $d $true}
foreach($type in @('review','approve','retry','save','undo','execute')){$d=Valid-Command;$d['type']=$type;Check $d $false}
foreach($kind in @('failure','approval','completed','cancelled','test')){$d=Valid-Command;$d['kind']=$kind;Check $d $true}
foreach($value in @('true',$null,42)){$d=Valid-Command;$d['playSound']=$value;Check $d $false}
$audible=New-Object Xml.XmlDocument
$audible.LoadXml([PvsNotificationAudio]::Xml($true))
if($audible.audio.src -ne 'ms-winsoundevent:Notification.Default' -or $audible.audio.loop -ne 'false'){throw 'AUDIO_MUST_USE_DEFAULT_ONCE'}
$silent=New-Object Xml.XmlDocument
$silent.LoadXml([PvsNotificationAudio]::Xml($false))
if($silent.audio.silent -ne 'true'){throw 'AUDIO_OPT_OUT_MUST_BE_SILENT'}
$script:checks+=2
foreach($pair in @(@('sessionId',('a'*31)),@('sessionId',('G'*32)),@('incidentId',('x'*65)),@('runId',('x'*97)),@('incidentId',"valid`n"),@('workflow','private path'),@('kind','unknown'),@('toast','true'))){$d=Valid-Command;$d[$pair[0]]=$pair[1];Check $d $false}
$hostSource=Get-Content -LiteralPath (Join-Path $root 'extension\native\NotificationHost.cs') -Raw
if($hostSource -match 'ShowReview|Form review|TopMost|FlashWindowEx'){throw 'DUPLICATE_CHANNEL_REINTRODUCED'}
if($hostSource -notmatch 'toast\.Activated[^\r\n]+RequestPanel\(\)'){throw 'TOAST_MUST_OPEN_CANONICAL_PANEL'}
if($hostSource -notmatch 'duration=\\"long\\"'){throw 'TOAST_DURATION_INVALID'}
Write-Host "NOTIFICATION_PROTOCOL_OK:checks=$script:checks;no-review;no-mutation;typed-curated-event;bounds"
