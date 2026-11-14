using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;
public static class PvsNotificationProtocol {
    static bool Text(Dictionary<string,object> d,string k,int max){object v;return d.TryGetValue(k,out v)&&v is string&&((string)v).Length>0&&((string)v).Length<=max;}
    static bool Bool(Dictionary<string,object> d,string k){object v;return d.TryGetValue(k,out v)&&v is bool;}
    static bool OneOf(Dictionary<string,object> d,string k,string[] values){object v;return d.TryGetValue(k,out v)&&v is string&&Array.IndexOf(values,(string)v)>=0;}
    public static bool IsValid(Dictionary<string,object> d){
        if(d==null||!Text(d,"sessionId",32)||!Regex.IsMatch((string)d["sessionId"],@"\A[a-f0-9]{32}\z")||!Text(d,"type",24)||!Text(d,"incidentId",64)||!Text(d,"runId",96))return false;
        if(!Regex.IsMatch((string)d["incidentId"],@"\A[a-zA-Z0-9._-]+\z")||!Regex.IsMatch((string)d["runId"],@"\A[a-zA-Z0-9._-]+\z"))return false;
        var type=(string)d["type"];
        if(type=="clear"||type=="hide-toast")return true;
        if(type=="observe")return Bool(d,"panelVisible");
        return type=="incident"&&Bool(d,"toast")&&Bool(d,"playSound")&&Bool(d,"panelVisible")&&Bool(d,"hasWarnings")&&OneOf(d,"workflow",new[]{"edit","captions","other"})&&OneOf(d,"kind",new[]{"completed","failure","approval","cancelled","test"});
    }
}

// Pure toast audio markup: the Windows notification owns playback and system policy.
public static class PvsNotificationAudio {
    public static string Xml(bool enabled) {
        return enabled ? "<audio src=\"ms-winsoundevent:Notification.Default\" loop=\"false\"/>" : "<audio silent=\"true\"/>";
    }
}
