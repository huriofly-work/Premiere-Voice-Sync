using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

// Reads only the caller's own Premiere ancestry. No arbitrary window selection.
internal sealed class PvsNotificationWindow {
    readonly int hostId; readonly DateTime hostStart;
    internal PvsNotificationWindow(Process caller) {
        try {
            var latest=caller.StartTime;var cursor=caller.Id;
            for(int depth=0;depth<16 && cursor>0;depth++) {
                using(var record=Process.GetProcessById(cursor)) {
                    if(record.SessionId!=caller.SessionId || record.StartTime>latest)return;
                    if(record.ProcessName.Equals("Adobe Premiere Pro",StringComparison.OrdinalIgnoreCase)) {
                        if(!System.IO.Path.GetFileName(record.MainModule.FileName).Equals("Adobe Premiere Pro.exe",StringComparison.OrdinalIgnoreCase))return;
                        hostId=record.Id;hostStart=record.StartTime;return;
                    }
                    latest=record.StartTime;
                    var next=PvsNotificationHost.ParentId(cursor);if(next==cursor)return;cursor=next;
                }
            }
        }catch{}
    }
    Process Host(){
        if(hostId<=0)return null;
        try{var host=Process.GetProcessById(hostId);if(host.HasExited||host.StartTime!=hostStart){host.Dispose();return null;}return host;}catch{return null;}
    }
    internal bool? IsForeground(){
        using(var host=Host()){
            if(host==null)return null;
            var foreground=GetForegroundWindow();uint owner;GetWindowThreadProcessId(foreground,out owner);
            // A modal dialog owned by Premiere does not prove the panel is visible.
            if(owner==(uint)hostId)return foreground==host.MainWindowHandle;
            int cursor=(int)owner;
            for(int depth=0;depth<16&&cursor>0;depth++){
                if(cursor==hostId)return true;
                var next=PvsNotificationHost.ParentId(cursor);if(next==cursor)break;cursor=next;
            }
            return false;
        }
    }
    // Exclusively called from a Windows toast activation, never on completion.
    internal void OpenHost(){
        using(var host=Host()){
            if(host==null)return;
            var window=host.MainWindowHandle;uint owner;
            GetWindowThreadProcessId(window,out owner);if(window==IntPtr.Zero||owner!=(uint)hostId)return;
            if(IsIconic(window))ShowWindowAsync(window,9);
            var popup=GetLastActivePopup(window);uint popupOwner;GetWindowThreadProcessId(popup,out popupOwner);
            SetForegroundWindow(popupOwner==(uint)hostId&&IsWindowVisible(popup)?popup:window);
        }
    }
    [DllImport("user32.dll")]static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")]static extern uint GetWindowThreadProcessId(IntPtr window,out uint process);
    [DllImport("user32.dll")]static extern bool IsIconic(IntPtr window);
    [DllImport("user32.dll")]static extern bool ShowWindowAsync(IntPtr window,int command);
    [DllImport("user32.dll")]static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")]static extern IntPtr GetLastActivePopup(IntPtr window);
    [DllImport("user32.dll")]static extern bool IsWindowVisible(IntPtr window);
}
