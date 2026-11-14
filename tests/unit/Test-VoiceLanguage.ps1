$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Resolve-Path (Join-Path $PSScriptRoot '..\..')
. "$root\extension\engine\lib\RecognitionBackend.ps1"
$ast=[Management.Automation.Language.Parser]::ParseFile("$root\extension\engine\run-alignment.ps1",[ref]$null,[ref]$null)
# Execute the production argument builders for primary recognition, CPU
# fallback and recovery windows, without invoking any external program.
$builders=@($ast.FindAll({param($node)
    $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Operator -eq 'Equals' -and
    $node.Left.Extent.Text -in @('$recognitionArgs','$recoveryArgs')
},$true))
if($builders.Count -ne 4){throw 'VOICE_LANGUAGE_RECOGNITION_PATH_MISSING'}
$whisperArguments=@('--no-gpu');$modelPath='model.bin';$wav='voice.wav';$outBase='recognition'
foreach($language in @('vi','en','auto','zh')){
    foreach($builder in $builders){
        $recognitionArgs=@();$recoveryArgs=@()
        . ([scriptblock]::Create($builder.Extent.Text))
        $arguments=if($recognitionArgs.Count){$recognitionArgs}else{$recoveryArgs}
        $legacy=@('--no-gpu','-m',$modelPath,'-f',$wav,'-l',$language,'-ojf','-ml','1','-sow','-np','-of',$outBase)
        if(($arguments|ConvertTo-Json -Compress) -cne ($legacy|ConvertTo-Json -Compress)){throw "VOICE_ARGUMENTS_74_COMPATIBILITY_CHANGED:$language"}
        $index=[Array]::IndexOf([object[]]$arguments,'-l')
        if($index -lt 0 -or $arguments[$index+1] -cne $language){throw "VOICE_LANGUAGE_NOT_FORWARDED:$language"}
    }
}
. "$root\extension\engine\lib\Alignment.ps1"
foreach($language in @('en','auto','zh')){
    $result=Repair-PvsNumericCaptionTimings -Cues @([pscustomobject]@{Text='12 percent'}) -VoiceClips @() -Language $language -RecognizeWindow {throw 'VIETNAMESE_NUMERIC_RETRY_USED_FOR_OTHER_LANGUAGE'}
    if($result.Refined.Count -or $result.Review.Count){throw 'OTHER_LANGUAGE_NUMERIC_RETRY_NOT_SKIPPED'}
}
Write-Host 'VOICE_LANGUAGE_OK:primary;CPU-fallback;recovery;recovery-CPU;vi;en;auto;zh;Vietnamese-numeric-guard'
