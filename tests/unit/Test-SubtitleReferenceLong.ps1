$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\Srt.ps1"
. "$root\extension\engine\lib\Alignment.ps1"
. "$root\extension\engine\lib\CaptionOnly.ps1"

# Independent full-matrix oracle: old recurrence, tie order and endpoint list.
# Small seeded cases include repeats, substitutions, insertions and deletions.
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
public static class SubtitleScopeOracle {
    public static string Find(string[] reference,string[] audio) {
        int n=reference.Length,m=audio.Length,best=m;
        int[,] cost=new int[n+1,m+1];byte[,] back=new byte[n+1,m+1];
        for(int j=0;j<=m;j++){cost[0,j]=j;back[0,j]=2;}
        for(int i=1;i<=n;i++){
            back[i,0]=1;
            for(int j=1;j<=m;j++){
                int sub=cost[i-1,j-1]+(reference[i-1]==audio[j-1]?0:1);
                int del=cost[i-1,j]+1,ins=cost[i,j-1]+1;
                if(sub<=del && sub<=ins){cost[i,j]=sub;back[i,j]=0;}
                else if(del<=ins){cost[i,j]=del;back[i,j]=1;}
                else{cost[i,j]=ins;back[i,j]=2;}
            }
            best=Math.Min(best,cost[i,m]);
        }
        var output=new List<string>();
        for(int end=1;end<=n;end++){
            if(cost[end,m]>best+Math.Max(1,(int)Math.Floor(m*0.005)))continue;
            int[] map=new int[n];for(int k=0;k<n;k++)map[k]=-1;
            int i=end,j=m,first=n,last=-1,exact=0;
            while(j>0){
                byte d=back[i,j];
                if(i>0 && d==0){map[i-1]=j-1;first=i-1;if(last<0)last=i-1;if(reference[i-1]==audio[j-1])exact++;i--;j--;}
                else if(i>0 && d==1)i--;else j--;
            }
            if(last>=0)output.Add(cost[end,m]+"|"+exact+"|"+first+"|"+last+"|"+String.Join(",",map));
        }
        return String.Join(";",output);
    }
}
'@

$warmCue=@([pscustomobject]@{Index=1;Text='alpha bravo charlie delta';Start=90;End=91})
$warmWords=for($i=0;$i -lt 4;$i++){[pscustomobject]@{Text=@('alpha','bravo','charlie','delta')[$i];Start=$i;End=$i+1;Chapter=0}}
Select-PvsSubtitleReference $warmCue @($warmWords) @([pscustomobject]@{start=10;end=14}) | Out-Null
$random=New-Object Random 314159
for($case=0;$case -lt 120;$case++){
    [string[]]$reference=for($i=0;$i -lt (1+$random.Next(110));$i++){[string]$random.Next(8)}
    [string[]]$audio=for($i=0;$i -lt (1+$random.Next(90));$i++){[string]$random.Next(8)}
    $expected=[SubtitleScopeOracle]::Find($reference,$audio)
    $actual=(@([PvsSubtitleScopeV2]::Find($reference,$audio)) | ForEach-Object {"$($_.Cost)|$($_.Exact)|$($_.First)|$($_.Last)|$($_.Mapping -join ',')"}) -join ';'
    if($actual -cne $expected){throw "CHECKPOINT_TRACEBACK_PARITY_FAILED:case-$case"}
}

# 36 million cells: must cross the former 25M guard and several checkpoints.
$cues=for($i=0;$i -lt 600;$i++){
    $text=((0..9 | ForEach-Object {"token$($i*10+$_)"}) -join ' ')+'.'
    [pscustomobject]@{Index=$i+1;Text=$text;Start=9000+$i;End=9001+$i}
}
$words=for($i=0;$i -lt 6000;$i++){[pscustomobject]@{Text="token$i";Start=$i*0.2;End=($i+1)*0.2;Chapter=0}}
$source=@([pscustomobject]@{start=10;end=1210})
$result=Select-PvsSubtitleReference @($cues) @($words) $source
if($result.SelectedCueCount -ne 600 -or $result.OutsideCueCount -ne 0 -or ($result.Cues.Text -join '|') -cne ($cues.Text -join '|')){throw 'LONG_REFERENCE_CONTENT_LOST'}
if($result.Cues[0].Start -ne 10 -or $result.Cues[-1].End -ne 1210 -or @($result.Cues | Where-Object {$_.Confidence -ne 1 -or $_.WordTimings.Count -ne 10}).Count){throw 'LONG_REFERENCE_TIMING_INVALID'}

# Large matrix with free prefix/suffix, original cue indices and audio offset.
$middle=@($words[500..5499] | ForEach-Object {$copy=$_.PSObject.Copy();$copy.Start-=100;$copy.End-=100;$copy})
$result=Select-PvsSubtitleReference @($cues) $middle @([pscustomobject]@{start=30;end=1030})
if($result.Ranges[0].firstCue -ne 51 -or $result.Ranges[0].lastCue -ne 550 -or $result.Cues[0].Start -ne 30 -or $result.Cues[-1].End -ne 1030){throw 'LONG_REFERENCE_MIDDLE_RANGE_INVALID'}

# Repeated long passages must still be rejected, even across checkpoints.
$failed=$false
try{Select-PvsSubtitleReference @($cues+$cues) $middle $source | Out-Null}catch{if($_.Exception.Message -match 'SUBTITLE_REFERENCE_SCOPE_AMBIGUOUS'){$failed=$true}else{throw}}
if(-not $failed){throw 'LONG_AMBIGUOUS_REFERENCE_ACCEPTED'}
$failed=$false
$missing=@($words[0..2999]) + @($words[3010..5999])
try{Select-PvsSubtitleReference @($cues) $missing $source | Out-Null}catch{if($_.Exception.Message -match 'SUBTITLE_REFERENCE_(WORD_UNALIGNED|MISMATCH)'){$failed=$true}else{throw}}
if(-not $failed){throw 'LONG_MISSING_CUE_ACCEPTED'}

# Full reference inside a longer continuous audio range: exclude only the
# external intro/outro; preserve source text and ASR times without SRT offsets.
function Add-OutsideSpeech {
    param([object[]]$Body)
    $all=New-Object System.Collections.Generic.List[object]
    for($i=0;$i -lt 12;$i++){$all.Add([pscustomobject]@{Text="intro$i";Start=$i*0.2;End=($i+1)*0.2;Chapter=0})}
    foreach($word in $Body){$copy=$word.PSObject.Copy();$copy.Start+=2.4;$copy.End+=2.4;$all.Add($copy)}
    $end=$all[$all.Count-1].End
    for($i=0;$i -lt 12;$i++){$all.Add([pscustomobject]@{Text="outro$i";Start=$end+$i*0.2;End=$end+($i+1)*0.2;Chapter=0})}
    return $all.ToArray()
}
$outside=@(Add-OutsideSpeech @($words))
$outsideSource=@([pscustomobject]@{start=10;end=1215})
$result=Select-PvsSubtitleReference @($cues) $outside $outsideSource -AllowAudioOutsideReference
if($result.SelectedCueCount -ne 600 -or $result.OutsideAudioWordCount -ne 24 -or ($result.Cues.Text -join '|') -cne ($cues.Text -join '|') -or [Math]::Abs($result.Cues[0].Start-12.4) -gt 0.000001 -or [Math]::Abs($result.Cues[-1].End-1212.4) -gt 0.000001){throw 'LONG_OUTSIDE_AUDIO_NOT_SCOPED'}
$failed=$false
try{Select-PvsSubtitleReference @($cues) @(Add-OutsideSpeech $missing) $outsideSource -AllowAudioOutsideReference | Out-Null}catch{if($_.Exception.Message -match 'SUBTITLE_REFERENCE_(WORD_UNALIGNED|MISMATCH)'){$failed=$true}else{throw}}
if(-not $failed){throw 'LONG_OUTSIDE_AUDIO_HID_MISSING_CUE'}
$repeat=@($outside)+@($outside | ForEach-Object {$copy=$_.PSObject.Copy();$copy.Start+=1210;$copy.End+=1210;$copy})
$failed=$false
try{Select-PvsSubtitleReference @($cues) $repeat @([pscustomobject]@{start=0;end=2430}) -AllowAudioOutsideReference | Out-Null}catch{if($_.Exception.Message -match 'SUBTITLE_REFERENCE_SCOPE_AMBIGUOUS'){$failed=$true}else{throw}}
if(-not $failed){throw 'REPEATED_AUDIO_REFERENCE_ACCEPTED'}
# Memory protection applies before allocation; matrix cell count alone no
# longer rejects a valid long reference.
$failed=$false
try{[PvsSubtitleScopeV2]::Find((New-Object 'string[]' 100000),(New-Object 'string[]' 100000)) | Out-Null}catch{if($_.Exception.Message -match 'SUBTITLE_REFERENCE_SCOPE_MEMORY_LIMIT'){$failed=$true}else{throw}}
if(-not $failed){throw 'LONG_REFERENCE_MEMORY_GUARD_MISSING'}
Write-Host 'SUBTITLE_REFERENCE_LONG_OK:120 oracle cases;36M full,30M middle,60M ambiguous;outside intro/outro;missing/repeated audio rejected;content,timing,offset preserved'
