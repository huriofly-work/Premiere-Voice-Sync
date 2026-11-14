param([string]$EntrypointPath)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\CaptionOnly.ps1"
. "$root\extension\engine\lib\SubtitleTiming.ps1"
$tokens=$null;$errors=$null
if(-not $EntrypointPath){$EntrypointPath="$root\extension\engine\run-captions.ps1"}
$ast=[Management.Automation.Language.Parser]::ParseFile($EntrypointPath,[ref]$tokens,[ref]$errors)
$node=$ast.Find({param($n);$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-CaptionReferenceWindow'},$true)
Invoke-Expression $node.Extent.Text
function New-PrimaryFixture {
    $texts=@('đây','là','phần','kết','thúc','của','câu','trước','Xin','cảm','ơn','các','bạn','đã','ủng','hộ','kênh.')
    $words=@(for($i=0;$i -lt $texts.Count;$i++){
        $start=if($i -lt 8){$i*0.3}else{4.0+($i-8)*0.3}
        [pscustomobject]@{Text=@(ConvertTo-NormalizedWords $texts[$i])[0];Start=$start;End=$start+0.25;Chapter=0;SubtitleTimingQuality='dtw';SubtitleTimingOrigin='primary-source';DtwFirst=$start+0.05;DtwLast=$start+0.15;DtwBoundaryStart=$start}
    })
    $surfaces=@(for($i=0;$i -lt $texts.Count;$i++){[pscustomobject]@{Text=$texts[$i];Start=$words[$i].Start;End=$words[$i].End;FirstWord=$i;LastWord=$i}})
    [pscustomobject]@{Recognition=[pscustomobject]@{Words=$words;Surfaces=$surfaces};Energy=[pscustomobject]@{Rms=[double[]](@(0.02)*2600)};SourceStart=10.0;SourceEnd=23.0;Chapter=0}
}
$script:source=[pscustomobject]@{start=10.0;end=23.0};$script:sources=@($source)
$script:characterMode=$false;$script:allSilences=New-Object System.Collections.Generic.List[object]
$script:referenceSupplementInvocationCount=0;$script:recognitionRejectedRanges=New-Object System.Collections.Generic.List[object]
$script:job=[pscustomobject]@{outputFolder='unused-private-fixture'}
$script:referenceSelection=[pscustomobject]@{Cues=@([pscustomobject]@{Index=1;Text='đây là phần kết thúc của câu trước';Start=10.0;End=12.35;CaptionEnd=12.35;Chapter=0});UnverifiedRanges=@()}
$script:primary=New-PrimaryFixture
$script:raw=[pscustomobject]@{Words=$primary.Recognition.Words[0..7];Surfaces=$primary.Recognition.Surfaces[0..7]}
$script:energy=$primary.Energy
function Get-PvsSubtitleEnergy {param($Path);$script:energy}
function Invoke-CaptionReferenceSlice {param($Source,$Start,$End,$Chapter,$Kind);$script:referenceSupplementInvocationCount++;$script:raw}
$before=$primary | ConvertTo-Json -Depth 10 -Compress
$heard=Invoke-CaptionReferenceWindow $source 12.5 23.0 0 supplement -PrimaryRecognition $primary
if($heard.Words.Count -ne 9 -or ($heard.Surfaces.Text -join ' ') -cne 'Xin cảm ơn các bạn đã ủng hộ kênh.'){throw 'PRIMARY_DTW_OUTRO_LOST_AFTER_EMPTY_CONTEXT_RECOGNITION'}
if(-not $heard.PrimaryRecognitionReused -or $heard.CoveredByReferenceContext -or [Math]::Abs($heard.Words[0].Start-1.5) -gt 0.000001){throw 'PRIMARY_SUPPLEMENT_COORDINATES_OR_PROVENANCE_WRONG'}
if(($primary | ConvertTo-Json -Depth 10 -Compress) -cne $before){throw 'PRIMARY_RECOGNITION_MUTATED'}
$cases=@('estimated','missing-quality','missing-origin','missing-anchor','bad-anchor','anchor-overrun','nan-anchor','partial-edge','tiny-tail','wrong-chapter','wrong-source','nan','overrun','overlap','silence','no-left-context','ambiguous-left','unresolved-tail','interior-gap')
foreach($case in $cases){
    $fixture=New-PrimaryFixture;$finish=23.0;$savedSelection=$referenceSelection
    switch($case){
        'estimated' {$fixture.Recognition.Words[8].SubtitleTimingQuality='estimated'}
        'missing-quality' {$fixture.Recognition.Words[8].PSObject.Properties.Remove('SubtitleTimingQuality')}
        'missing-origin' {$fixture.Recognition.Words[8].PSObject.Properties.Remove('SubtitleTimingOrigin')}
        'anchor-overrun' {$fixture.Recognition.Words[8].DtwLast=14.0}
        'nan-anchor' {$fixture.Recognition.Words[8].DtwFirst=[double]::NaN}
        'partial-edge' {$fixture.Recognition.Words[8].Start=2.4}
        'tiny-tail' {$fixture.Recognition.Words=@($fixture.Recognition.Words[0..10]);$fixture.Recognition.Surfaces=@($fixture.Recognition.Surfaces[0..10])}
        'missing-anchor' {$fixture.Recognition.Words[8].PSObject.Properties.Remove('DtwFirst')}
        'bad-anchor' {$fixture.Recognition.Words[8].DtwFirst=-1}
        'wrong-chapter' {$fixture.Recognition.Words[8].Chapter=2}
        'wrong-source' {$fixture.SourceStart=9}
        'nan' {$fixture.Recognition.Words[8].Start=[double]::NaN}
        'overrun' {$fixture.Recognition.Words[-1].End=20.0}
        'overlap' {$fixture.Recognition.Words[9].Start=$fixture.Recognition.Words[8].Start}
        'silence' {$fixture.Energy=[pscustomobject]@{Rms=[double[]](@(0.0)*2600)}}
        'no-left-context' {$referenceSelection=[pscustomobject]@{Cues=@();UnverifiedRanges=@()}}
        'ambiguous-left' {$fixture.Recognition.Words=@($fixture.Recognition.Words[0..7]) + @($fixture.Recognition.Words)}
        'unresolved-tail' {$referenceSelection=$referenceSelection.PSObject.Copy();$referenceSelection.UnverifiedRanges=@([pscustomobject]@{sourceIndex=0;start=12.5;end=23.0;cueIndices=@(2)})}
        'interior-gap' {$finish=22.0}
    }
    $result=Invoke-CaptionReferenceWindow $source 12.5 $finish 0 supplement -PrimaryRecognition $fixture
    if($result.Words.Count){throw "UNSAFE_PRIMARY_SUPPLEMENT_ACCEPTED:$case"}
    $referenceSelection=$savedSelection
}
# Fully estimated local timing cannot erase a complete primary DTW tail.
$degraded=New-PrimaryFixture;$script:raw=$degraded.Recognition
foreach($word in $raw.Words){$word.SubtitleTimingQuality='estimated'}
for($i=8;$i -lt $raw.Words.Count;$i++){$raw.Words[$i].Text='alternative'+$i;$raw.Surfaces[$i].Text='alternative'+$i}
$preferred=Invoke-CaptionReferenceWindow $source 12.5 23.0 0 supplement -PrimaryRecognition $primary
if($preferred.Words.Count -ne 9 -or ($preferred.Surfaces.Text -join ' ') -cne 'Xin cảm ơn các bạn đã ủng hộ kênh.' -or -not $preferred.PrimaryRecognitionReused){throw 'PRIMARY_DTW_LOST_TO_ESTIMATED_SUPPLEMENT'}
if($preferred.PrimaryReuseReason -cne 'estimated-context-rerecognition'){throw 'ESTIMATED_REUSE_REASON_LOST'}
$invalid=New-PrimaryFixture;$invalid.Recognition.Words[8].SubtitleTimingQuality='estimated'
$kept=Invoke-CaptionReferenceWindow $source 12.5 23.0 0 supplement -PrimaryRecognition $invalid
if(($kept.Surfaces.Text -join ' ') -notmatch 'alternative8' -or ($kept.PSObject.Properties['PrimaryRecognitionReused'] -and $kept.PrimaryRecognitionReused)){throw 'INVALID_PRIMARY_REPLACED_ESTIMATED_SUPPLEMENT'}
$raw.Words[8].SubtitleTimingQuality='dtw'
$mixed=Invoke-CaptionReferenceWindow $source 12.5 23.0 0 supplement -PrimaryRecognition $primary
if(($mixed.Surfaces.Text -join ' ') -notmatch 'alternative8' -or ($mixed.PSObject.Properties['PrimaryRecognitionReused'] -and $mixed.PrimaryRecognitionReused)){throw 'MIXED_DTW_SUPPLEMENT_REPLACED'}
# Existing nonempty DTW re-recognition wins; no transcript vote or merging.
$script:raw=$primary.Recognition
$normal=Invoke-CaptionReferenceWindow $source 12.5 23.0 0 supplement -PrimaryRecognition $primary
if($normal.PSObject.Properties['PrimaryRecognitionReused'] -and $normal.PrimaryRecognitionReused){throw 'NONEMPTY_RECOGNITION_REPLACED_BY_PRIMARY'}
$other=New-PrimaryFixture;$other.Chapter=2
foreach($word in $other.Recognition.Words){$word.Chapter=2}
$multi=Select-PvsPrimarySubtitleTail $other $source 12.5 23.0 2 'đây là phần kết thúc của câu trước'
if($multi.Words.Count -ne 9 -or @($multi.Words | Where-Object Chapter -ne 2).Count -or [Math]::Abs($multi.Words[0].DtwFirst-1.55) -gt 0.000001){throw 'PRIMARY_SOURCE_CHAPTER_OR_ANCHOR_OFFSET_WRONG'}
function Invoke-CaptionReferenceSlice {param($Source,$Start,$End,$Chapter,$Kind);throw 'NATIVE_TEST_FAILURE'}
$caught=$false
try{Invoke-CaptionReferenceWindow $source 12.5 23.0 0 supplement -PrimaryRecognition $primary | Out-Null}catch{if($_.Exception.Message -eq 'NATIVE_TEST_FAILURE'){$caught=$true}else{throw}}
if(-not $caught){throw 'PRIMARY_FALLBACK_SWALLOWED_NATIVE_FAILURE'}
Write-Host 'SUBTITLE_PRIMARY_SUPPLEMENT_OK:empty-context-outro;DTW-only;unique-left;source-chapter-offset;raw-immutable;estimated-invalid-silence-repeat-unresolved-interior-rejected;estimated-local-DTW-primary-preferred;invalid-primary-keeps-local;mixed-and-DTW-local-unchanged'
