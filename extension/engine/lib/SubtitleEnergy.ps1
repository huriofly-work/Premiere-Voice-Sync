Set-StrictMode -Version Latest

function Get-PvsSubtitleEnergy {
    param([Parameter(Mandatory)][string]$Path)
    if(-not ('PvsSubtitleEnergy' -as [type])){
        Add-Type -TypeDefinition @'
using System;
using System.IO;
public sealed class PvsSubtitleEnergy {
    public readonly double[] Rms;
    public const double Step = 0.005;
    private PvsSubtitleEnergy(double[] rms) { Rms=rms; }
    public static PvsSubtitleEnergy Read(string path) {
        using(var stream=File.OpenRead(path)) using(var reader=new BinaryReader(stream)) {
            if(new string(reader.ReadChars(4))!="RIFF") throw new Exception("SUBTITLE_ENERGY_WAV_INVALID");
            reader.ReadUInt32();
            if(new string(reader.ReadChars(4))!="WAVE") throw new Exception("SUBTITLE_ENERGY_WAV_INVALID");
            bool pcm=false; long position=0; uint length=0;
            while(stream.Position+8<=stream.Length) {
                string tag=new string(reader.ReadChars(4)); uint size=reader.ReadUInt32(); long next=stream.Position+size+(size%2);
                if(next>stream.Length) throw new Exception("SUBTITLE_ENERGY_WAV_TRUNCATED");
                if(tag=="fmt " && size>=16) { int format=reader.ReadUInt16(), channels=reader.ReadUInt16(); uint rate=reader.ReadUInt32(); reader.ReadUInt32(); reader.ReadUInt16(); int bits=reader.ReadUInt16(); pcm=format==1 && channels==1 && rate==16000 && bits==16; }
                if(tag=="data") { position=stream.Position; length=size; }
                stream.Position=next;
            }
            if(!pcm || length==0 || length%2!=0) throw new Exception("SUBTITLE_ENERGY_FORMAT_INVALID");
            stream.Position=position; var rms=new double[(int)((length/2+79)/80)];
            for(int i=0;i<rms.Length;i++) {
                double sum=0; int count=(int)Math.Min(80,length/2-i*80);
                for(int j=0;j<count;j++) { double v=reader.ReadInt16()/32768.0; sum+=v*v; }
                rms[i]=Math.Sqrt(sum/count);
            }
            return new PvsSubtitleEnergy(rms);
        }
    }
    // Find a relative energy depression near the observed END of the word
    // on the left. A digit token can span several spoken syllables, so its
    // own attention peak must not drag this seam into the middle of a number.
    public double FindBoundary(double anchor,double minimum,double maximum) {
        int lo=Math.Max(1,(int)Math.Ceiling(Math.Max(minimum,anchor-0.12)/Step));
        int hi=Math.Min(Rms.Length-2,(int)Math.Floor(Math.Min(maximum,anchor+0.12)/Step));
        if(hi-lo<3) return double.NaN;
        double best=double.PositiveInfinity; int chosen=-1;
        for(int i=lo;i<=hi;i++) {
            double energy=(Rms[i-1]+Rms[i]+Rms[i+1])/3, left=0,right=0;
            for(int j=Math.Max(0,i-18);j<i-2;j++) left=Math.Max(left,Rms[j]);
            for(int j=i+3;j<=Math.Min(Rms.Length-1,i+18);j++) right=Math.Max(right,Rms[j]);
            double shoulder=Math.Min(left,right);
            if(shoulder<=0 || energy>shoulder*0.65) continue;
            double score=energy/shoulder+Math.Abs((i+0.5)*Step-anchor)*0.4;
            if(score<best) {best=score;chosen=i;}
        }
        if(chosen<0) return double.NaN;
        double floor=(Rms[chosen-1]+Rms[chosen]+Rms[chosen+1])/3*1.25+0.00005;
        int first=chosen,last=chosen;
        while(first>lo && (Rms[first-2]+Rms[first-1]+Rms[first])/3<=floor) first--;
        while(last<hi && (Rms[last]+Rms[last+1]+Rms[last+2])/3<=floor) last++;
        return (first+last+1)*Step/2;
    }
}
'@
    }
    return [PvsSubtitleEnergy]::Read($Path)
}
