using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Windows.Data.Xml.Dom;
using Windows.UI.Notifications;

// Live-session adapter only. It cannot edit a project, approve, retry, Undo or Save.
public static class PvsNotificationHost {
    [STAThread] public static int Main(string[] args) {
        if(args.Length==1 && args[0]=="--expired") return 0;
        int caller;
        if(args.Length!=3 || args[0]!="--pipe" || !Int32.TryParse(args[1],out caller) || !System.Text.RegularExpressions.Regex.IsMatch(args[2],"^[a-f0-9]{32}$"))return 2;
        try {
            // The inherited anonymous pipes must belong to the process that launched us.
            if(ParentId(Process.GetCurrentProcess().Id)!=caller)return 3;
            using(var parent=Process.GetProcessById(caller)) {
                if(parent.SessionId!=Process.GetCurrentProcess().SessionId || parent.HasExited)return 3;
                Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
                using(var context=new NotificationContext(parent,args[2]))Application.Run(context);
            }
            return 0;
        }catch{return 1;}
    }
    internal static int ParentId(int processId) {
        var snapshot=CreateToolhelp32Snapshot(2,0);
        if(snapshot==new IntPtr(-1))return 0;
        try {
            var entry=new ProcessEntry();entry.size=(uint)Marshal.SizeOf(entry);
            if(Process32First(snapshot,ref entry))do{if(entry.id==(uint)processId)return (int)entry.parent;}while(Process32Next(snapshot,ref entry));
        }finally{CloseHandle(snapshot);}return 0;
    }
    [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]struct ProcessEntry {
        public uint size,usage,id;public IntPtr heap;public uint module,threads,parent;public int priority;public uint flags;
        [MarshalAs(UnmanagedType.ByValTStr,SizeConst=260)]public string name;
    }
    [DllImport("kernel32.dll")]static extern IntPtr CreateToolhelp32Snapshot(uint flags,uint id);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode)]static extern bool Process32First(IntPtr snapshot,ref ProcessEntry entry);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode)]static extern bool Process32Next(IntPtr snapshot,ref ProcessEntry entry);
    [DllImport("kernel32.dll")]static extern bool CloseHandle(IntPtr handle);
}

sealed class NotificationContext:ApplicationContext {
    readonly Process parent;
    readonly string session,tag;
    readonly DateTime parentStart;
    readonly Form dispatcher=new Form();
    readonly JavaScriptSerializer json=new JavaScriptSerializer{MaxJsonLength=32768,RecursionLimit=8};
    readonly StreamWriter output=new StreamWriter(Console.OpenStandardOutput(),new UTF8Encoding(false)){AutoFlush=true};
    readonly System.Windows.Forms.Timer lifetime=new System.Windows.Forms.Timer{Interval=2000};
    ToastNotifier notifier;
    ToastNotification toast;
    int toastGeneration;
    readonly PvsNotificationWindow window;
    string incident="",run="",workflow="other",kind="completed";
    bool closing,hasWarnings,panelVisible,viewed,playSound;
    internal NotificationContext(Process parent,string session) {
        this.parent=parent;this.session=session;this.tag=session.Substring(0,16);parentStart=parent.StartTime;
        window=new PvsNotificationWindow(parent);
        var handle=dispatcher.Handle; // Marshal pipe messages onto this UI thread without displaying a hidden host.
        try {
            PvsNotificationIdentity.SetProcessIdentity();
            notifier=ToastNotificationManager.CreateToastNotifier(PvsNotificationIdentity.AppId);
        }catch{notifier=null;}
        string capability=notifier==null?"unavailable":"available";
        if(notifier!=null)try{if(notifier.Setting!=NotificationSetting.Enabled)capability="disabled";}catch{}
        Emit("ready",capability);
        lifetime.Tick+=(s,e)=>{try{if(parent.HasExited || parent.StartTime!=parentStart)ExitThread();else if(incident.Length>0&&!viewed)Observe();}catch{ExitThread();}};lifetime.Start();
        var reader=new Thread(Read){IsBackground=true};reader.Start();
    }
    void Read() {
        try {
            var parser=new JavaScriptSerializer{MaxJsonLength=32768,RecursionLimit=8};
            using(var input=new StreamReader(Console.OpenStandardInput(),new UTF8Encoding(false,true))) {
                while(!closing) {
                    // Bounded read: a faulty sender cannot grow a line indefinitely.
                    var line=new StringBuilder();int character;
                    while((character=input.Read())>=0 && character!=10){if(line.Length>=32768)throw new InvalidDataException();line.Append((char)character);}
                    if(character<0)break;
                    var command=parser.Deserialize<Dictionary<string,object>>(line.ToString());
                    if(!PvsNotificationProtocol.IsValid(command))throw new InvalidDataException("INVALID_NOTIFICATION_COMMAND");
                    dispatcher.BeginInvoke((Action)(()=>Handle(command)));
                }
            }
        }catch{}finally{try{dispatcher.BeginInvoke((Action)(()=>ExitThread()));}catch{}}
    }
    static string Text(Dictionary<string,object> data,string key,int limit) {
        object value;var text=data.TryGetValue(key,out value)?value as string:null;
        return text==null?"":text.Substring(0,Math.Min(limit,text.Length));
    }
    static bool Flag(Dictionary<string,object> data,string key) {object value;return data.TryGetValue(key,out value) && value is bool && (bool)value;}
    void Handle(Dictionary<string,object> command) {
        if(closing || !PvsNotificationProtocol.IsValid(command) || Text(command,"sessionId",64)!=session)return;
        var type=Text(command,"type",24);
        var next=Text(command,"incidentId",64);var nextRun=Text(command,"runId",96);
        if(type=="incident") {
            if(next.Length==0 || nextRun.Length==0)return;
            Clear();incident=next;run=nextRun;workflow=Text(command,"workflow",16);kind=Text(command,"kind",16);hasWarnings=Flag(command,"hasWarnings");panelVisible=Flag(command,"panelVisible");viewed=false;playSound=Flag(command,"playSound");
            if(!Observe()&&Flag(command,"toast"))SendToast();
            Emit("state","active");
        }else if(next==incident && nextRun==run && incident.Length>0) {
            if(type=="clear"){Clear();Emit("state","cleared");}
            else if(type=="hide-toast")HideToast();
            else if(type=="observe"){panelVisible=Flag(command,"panelVisible");Observe();}
        }
    }
    void SendToast() {
        if(notifier==null){Emit("delivery","unavailable");return;}
        var captured=incident;var capturedRun=run;
        var capturedGeneration=++toastGeneration;
        try {
            try{if(notifier.Setting!=NotificationSetting.Enabled){Emit("delivery","disabled");return;}}catch{}
            var xml=new XmlDocument();
            // No filenames, transcripts, raw errors or user-supplied title in the Windows notification.
            var task=workflow=="captions"?"Tạo phụ đề":workflow=="edit"?"Dựng theo voice":"Tác vụ";
            var summary=kind=="test"?"Đây là thông báo kiểm thử. Không có thao tác project.":kind=="approval"?"Cần quyết định để tiếp tục.":kind=="failure"?task+" chưa hoàn tất.":kind=="cancelled"?task+" đã dừng.":task+" đã hoàn tất"+(hasWarnings?" — có vùng cần kiểm tra.":".");
            xml.LoadXml("<toast launch=\"open\" duration=\"long\"><visual><binding template=\"ToastGeneric\"><text>"+(kind=="test"?"Kiểm thử thông báo":"Premiere Voice Sync")+"</text><text>"+summary+"</text></binding></visual><actions><action content=\"Mở kết quả\" arguments=\"open\" activationType=\"foreground\"/></actions>"+PvsNotificationAudio.Xml(playSound)+"</toast>");
            toast=new ToastNotification(xml){Tag=tag,Group="pvs",ExpirationTime=new DateTimeOffset(DateTime.Now.AddMinutes(10))};
            toast.Activated+=(s,e)=>Dispatch(()=>{if(incident==captured && run==capturedRun && capturedGeneration==toastGeneration && !closing)RequestPanel();});
            toast.Failed+=(s,e)=>Dispatch(()=>{if(incident==captured && run==capturedRun && capturedGeneration==toastGeneration)Emit("delivery","unavailable");});
            notifier.Show(toast);Emit("delivery","submitted");
        }catch{Emit("delivery","unavailable");}
    }
    void Dispatch(Action action){try{dispatcher.BeginInvoke(action);}catch{}}
    bool Observe() {
        if(panelVisible&&window.IsForeground()==true){viewed=true;HideToast();Emit("observed","visible");return true;}
        return false;
    }
    void RequestPanel() {
        window.OpenHost();HideToast();Emit("open","");
    }
    void Clear() {
        incident="";run="";
        HideToast();
    }
    void HideToast() {
        ++toastGeneration;
        try{if(toast!=null && notifier!=null)notifier.Hide(toast);}catch{}
        try{ToastNotificationManager.History.Remove(tag,"pvs",PvsNotificationIdentity.AppId);}catch{}toast=null;
    }
    void Emit(string type,string capability) {
        try{output.WriteLine(json.Serialize(new{type=type,sessionId=session,incidentId=incident,runId=run,toast=capability}));}catch{ExitThread();}
    }
    protected override void ExitThreadCore() {if(closing)return;closing=true;lifetime.Stop();Clear();base.ExitThreadCore();}
    protected override void Dispose(bool disposing) {if(disposing){lifetime.Dispose();dispatcher.Dispose();output.Dispose();}base.Dispose(disposing);}
}
