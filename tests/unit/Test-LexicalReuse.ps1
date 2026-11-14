$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. "$root\extension\engine\lib\CaptionOnly.ps1"
function Check([bool]$Value,[string]$Message){if(-not $Value){throw "LEXICAL_REUSE_TEST_FAILED:$Message"}}
function Key([string]$Text){@(ConvertTo-NormalizedWords $Text) -join '|'}
$cases=@(
    @{Text='';Expected=''},@{Text='   ';Expected=''},
    @{Text='Câu A: LV-223, 0,5 giây!';Expected='câu|a|lv|223|0|5|giây'},
    @{Text='ĐẶNG – đặng';Expected='đặng|đặng'},
    @{Text='中文 日本語 한국어';Expected='中文|日本語|한국어'},
    @{Text='I i İ ı';Expected="i|i|İ|ı"}
)
foreach($pass in 1..3){foreach($case in $cases){Check ((Key $case.Text) -ceq $case.Expected) 'cold-and-reused-lexical-output'}}
$decomposed='Tie'+[char]0x0302+'ng Vie'+[char]0x0323+[char]0x0302+'t'
Check ((Key $decomposed) -ceq 'tiêng|việt') 'decomposed-unicode'
$collected=@(ConvertTo-NormalizedWords 'Câu cần giữ');$collected[0]='corrupted'
Check ((Key 'Câu cần giữ') -ceq 'câu|cần|giữ') 'caller-cannot-corrupt-reused-words'
Check ((Key 'Số 123') -ceq 'số|123') 'original-number'
Check ((Key 'Số 124') -ceq 'số|124') 'edited-number-is-new-content'
# Exercise eviction and oversized inputs while old text remains correct.
for($i=0;$i -lt 2200;$i++){Check ((Key "từ $i") -ceq "từ|$i") 'bounded-churn'}
Check ((Key 'Câu cần giữ') -ceq 'câu|cần|giữ') 'evicted-text-recomputes'
$long=('a ' * 2200).Trim();Check (@(ConvertTo-NormalizedWords $long).Count -eq 2200) 'oversized-text-retained'
Check ((Key 'Câu cần giữ') -ceq 'câu|cần|giữ') 'oversized-input-does-not-corrupt-cache'
Write-Host 'LEXICAL_REUSE_OK:unicode;numbers;caller-isolation;edited-content;eviction;long-text'
