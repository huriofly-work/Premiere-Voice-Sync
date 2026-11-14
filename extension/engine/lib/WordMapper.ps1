Set-StrictMode -Version Latest
# Compiled implementation of the existing lexical edit-distance mapper.
# The edit-distance recurrence and substitution/deletion/insertion tie order
# match Get-SequentialWordMapping. Only representation/execution changes.
function Initialize-PvsCompiledWordMapper {
    if('PremiereVoiceSync.RollingWordMapperV1' -as [type]){return}
    Add-Type -TypeDefinition @'
using System;
namespace PremiereVoiceSync {
    public static class RollingWordMapperV1 {
        public static int[] Map(string[] target, string[] recognized) {
            int n=target.Length, m=recognized.Length;
            if(n==0 || m==0) return new int[0];
            long cells=((long)n+1)*((long)m+1);
            if(cells>Int32.MaxValue) throw new ArgumentException("LEXICAL_MATRIX_TOO_LARGE");
            int width=m+1;
            var back=new byte[(int)cells];
            var previous=new int[width];
            var current=new int[width];
            for(int j=1;j<=m;j++){previous[j]=j;back[j]=2;}
            for(int i=1;i<=n;i++){
                current[0]=i;int row=i*width;back[row]=1;
                for(int j=1;j<=m;j++){
                    int sub=previous[j-1]+(StringComparer.InvariantCultureIgnoreCase.Equals(target[i-1],recognized[j-1])?0:1);
                    int del=previous[j]+1, ins=current[j-1]+1;
                    if(sub<=del && sub<=ins){current[j]=sub;back[row+j]=0;}
                    else if(del<=ins){current[j]=del;back[row+j]=1;}
                    else{current[j]=ins;back[row+j]=2;}
                }
                var swap=previous;previous=current;current=swap;
            }
            var mapping=new int[n];for(int k=0;k<n;k++)mapping[k]=-1;
            int ti=n,rj=m;
            while(ti>0 || rj>0){
                byte direction=back[ti*width+rj];
                if(ti>0 && rj>0 && direction==0){mapping[ti-1]=rj-1;ti--;rj--;}
                else if(ti>0 && (rj==0 || direction==1)){ti--;}
                else{rj--;}
            }
            return mapping;
        }
    }
}
'@
}

function Invoke-PvsCompiledWordMapping {
    param([AllowEmptyCollection()][string[]]$TargetWords,[AllowEmptyCollection()][object[]]$RecognizedWords)
    Initialize-PvsCompiledWordMapper
    $texts=New-Object 'string[]' $RecognizedWords.Count
    for($i=0;$i -lt $RecognizedWords.Count;$i++){
        # The production reader emits strings. Reject other types in this
        # fast path rather than silently changing PowerShell coercion rules.
        if($RecognizedWords[$i].Text -isnot [string]){throw 'LEXICAL_NON_STRING_TEXT'}
        $texts[$i]=$RecognizedWords[$i].Text
    }
    return [PremiereVoiceSync.RollingWordMapperV1]::Map($TargetWords,$texts)
}
