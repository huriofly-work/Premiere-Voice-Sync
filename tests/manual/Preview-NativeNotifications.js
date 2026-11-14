"use strict";
// Explicit synthetic Windows toast only. No duplicate review window or project action.
if(!process.argv.includes("--show-toast"))throw Error("VISIBLE_PREVIEW_REQUIRES_SHOW_TOAST_FLAG");
const cp=require("child_process"),path=require("path"),fs=require("fs"),crypto=require("crypto"),{create}=require("../../extension/js/native-notifications");
const dir=path.resolve(__dirname,"../../extension/native");
const bridge=create({parentId:process.pid,sessionId:crypto.randomBytes(16).toString("hex"),executable:path.join(dir,"PvsNotifications.exe"),spawn:cp.spawn,soundEnabled:()=>process.argv.includes("--sound"),
 verify(){const lock=JSON.parse(fs.readFileSync(path.join(dir,"helper-lock.json")));if(crypto.createHash("sha256").update(fs.readFileSync(path.join(dir,"PvsNotifications.exe"))).digest("hex")!==lock.sha256)throw Error("HASH");},
 onStatus:value=>console.log(JSON.stringify({status:value})),onOpen:()=>console.log("SYNTHETIC_OPEN_NO_PROJECT_ACTION")});
bridge.publish({test:true,runId:"preview"},true,false);setTimeout(()=>bridge.stop(),45000);
