using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Text;
public static class PvsNotificationIdentity {
    public const string AppId = "PremiereVoiceSync.Notifications";
    public static bool IsOwned(string file, string executable) {
        if (!File.Exists(file)) return false;
        var instance=(IShellLinkW)new ShellLink();
        try {
            ((IPersistFile)instance).Load(file,0);
            var target=new StringBuilder(32768);instance.GetPath(target,target.Capacity,IntPtr.Zero,0);
            var store=(IPropertyStore)instance;
            var key=new PropertyKey{format=new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"),id=5};
            PropVariant value;store.GetValue(ref key,out value);
            try { return value.type==31 && Marshal.PtrToStringUni(value.pointer)==AppId && String.Equals(Path.GetFullPath(target.ToString()),Path.GetFullPath(executable),StringComparison.OrdinalIgnoreCase); }
            finally { PropVariantClear(ref value); }
        } finally { Marshal.ReleaseComObject(instance); }
    }
    public static void Install(string file,string executable) {
        if(File.Exists(file) && !IsOwned(file,executable))throw new IOException("NOTIFICATION_SHORTCUT_NOT_OWNED");
        Directory.CreateDirectory(Path.GetDirectoryName(file));
        var instance=(IShellLinkW)new ShellLink();
        try {
            instance.SetPath(executable);instance.SetArguments("--expired");
            instance.SetDescription("Premiere Voice Sync - notifications for the active panel session");
            var store=(IPropertyStore)instance;
            var key=new PropertyKey{format=new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"),id=5};
            var value=new PropVariant{type=31,pointer=Marshal.StringToCoTaskMemUni(AppId)};
            try { store.SetValue(ref key,ref value);store.Commit(); }finally{PropVariantClear(ref value);}
            ((IPersistFile)instance).Save(file,true);
            SHChangeNotify(2,0x1005,file,IntPtr.Zero);
        } finally { Marshal.ReleaseComObject(instance); }
    }
    public static void Remove(string file,string executable) {
        if(!File.Exists(file))return;
        if(!IsOwned(file,executable))throw new IOException("NOTIFICATION_SHORTCUT_NOT_OWNED");
        File.Delete(file);SHChangeNotify(4,0x1005,file,IntPtr.Zero);
    }
    public static void SetProcessIdentity() { Marshal.ThrowExceptionForHR(SetCurrentProcessExplicitAppUserModelID(AppId)); }
    [DllImport("ole32.dll")]static extern int PropVariantClear(ref PropVariant value);
    [DllImport("shell32.dll",CharSet=CharSet.Unicode)]static extern int SetCurrentProcessExplicitAppUserModelID(string id);
    [DllImport("shell32.dll",CharSet=CharSet.Unicode)]static extern void SHChangeNotify(uint action,uint flags,string item,IntPtr second);
    [StructLayout(LayoutKind.Sequential)]struct PropertyKey{public Guid format;public uint id;}
    [StructLayout(LayoutKind.Explicit,Size=24)]struct PropVariant{[FieldOffset(0)]public ushort type;[FieldOffset(8)]public IntPtr pointer;}
    [ComImport,Guid("00021401-0000-0000-C000-000000000046")]class ShellLink{}
    [ComImport,Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]interface IPropertyStore {
        void GetCount(out uint count);void GetAt(uint index,out PropertyKey key);void GetValue(ref PropertyKey key,out PropVariant value);void SetValue(ref PropertyKey key,ref PropVariant value);void Commit();
    }
    [ComImport,Guid("000214F9-0000-0000-C000-000000000046"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]interface IShellLinkW {
        void GetPath([Out,MarshalAs(UnmanagedType.LPWStr)]StringBuilder file,int size,IntPtr data,uint flags);
        void GetIDList(out IntPtr id);void SetIDList(IntPtr id);
        void GetDescription([Out,MarshalAs(UnmanagedType.LPWStr)]StringBuilder value,int size);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)]string value);
        void GetWorkingDirectory([Out,MarshalAs(UnmanagedType.LPWStr)]StringBuilder value,int size);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)]string value);
        void GetArguments([Out,MarshalAs(UnmanagedType.LPWStr)]StringBuilder value,int size);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)]string value);
        void GetHotkey(out short value);void SetHotkey(short value);void GetShowCmd(out int value);void SetShowCmd(int value);
        void GetIconLocation([Out,MarshalAs(UnmanagedType.LPWStr)]StringBuilder file,int size,out int index);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)]string file,int index);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)]string file,uint reserved);void Resolve(IntPtr window,uint flags);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)]string file);
    }
}
