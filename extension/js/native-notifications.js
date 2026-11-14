(function(root,factory){var api=factory();if(typeof module==="object"&&module.exports)module.exports=api;if(root)root.PvsNativeNotifications=api;}(typeof window!=="undefined"?window:null,function(){
"use strict";
function create(deps){
  var child=null,ready=false,pending=[],buffer="",stopped=false,timer,active=null,serial=0,sessionId=deps.sessionId;
  function failure(){
    if(stopped)return;var item=active&&active.item;stopped=true;ready=false;pending=[];active=null;
    if(timer)clearTimeout(timer);if(child)try{child.kill();}catch(ignore){}
    deps.onStatus("unavailable",item);
  }
  function write(command){if(!child||!ready||stopped)return;try{child.stdin.write(JSON.stringify(command)+"\n","utf8");}catch(ignore){failure();}}
  function fresh(command){
    if(!active||command.incidentId!==active.incidentId||command.runId!==active.runId)return false;
    if(command.type==="incident"){
      if(active.item.seen)return false;
      if(deps.panelVisible)command.panelVisible=!!deps.panelVisible(active.item);
      command.playSound=command.toast&&active.allowSound&&!!(deps.soundEnabled&&deps.soundEnabled());
    }
    return true;
  }
  function start(){
    if(child||stopped)return;
    try{
      deps.verify();child=deps.spawn(deps.executable,["--pipe",String(deps.parentId),sessionId],{windowsHide:true,stdio:["pipe","pipe","pipe"]});
      timer=setTimeout(failure,7000);child.on("error",failure);child.on("exit",failure);child.stdin.on("error",failure);child.stderr.on("data",function(){});
      child.stdout.setEncoding("utf8");child.stdout.on("data",function(chunk){
        if(stopped)return;buffer+=chunk;if(buffer.length>65536){failure();return;}var index;
        while((index=buffer.indexOf("\n"))>=0){
          var line=buffer.slice(0,index);buffer=buffer.slice(index+1);var message;
          try{message=JSON.parse(line);}catch(ignore){failure();return;}
          if(!message||typeof message!=="object"||Array.isArray(message)||typeof message.type!=="string"||typeof message.sessionId!=="string"){failure();return;}
          if(message.sessionId!==sessionId)continue;
          if(message.type==="ready"){
            if(ready)continue;ready=true;clearTimeout(timer);deps.onStatus(message.toast==="available"?"available":"disabled",active&&active.item);
            pending.splice(0).forEach(function(command){if(fresh(command))write(command);});
          }else if(active&&message.incidentId===active.incidentId&&message.runId===active.runId){
            if(message.type==="open"&&!active.item.seen)deps.onOpen(active.item);
            else if(message.type==="observed"&&message.toast==="visible"&&deps.onObserved)deps.onObserved(active.item);
            else if(message.type==="delivery")deps.onStatus(message.toast==="submitted"?"submitted":message.toast==="unavailable"?"unavailable":"disabled",active.item);
          }
        }
      });
    }catch(ignore){failure();}
  }
  function send(command){command.sessionId=sessionId;if(stopped)return;start();if(ready)write(command);else if(!stopped){pending.push(command);if(pending.length>32)failure();}}
  function command(type){return {type:type,incidentId:active.incidentId,runId:active.runId};}
  return {
    publish:function(item,toast,panelVisible,allowSound){
      if(active&&active.item===item)return;
      pending=[];active={item:item,incidentId:"incident-"+(++serial),runId:String(item.runId||"panel"),allowSound:allowSound!==false};
      var kind=item.test?"test":item.choice?"approval":["failure","cancelled"].indexOf(item.kind)>=0?item.kind:item.tone==="error"?"failure":"completed";
      send(Object.assign(command("incident"),{kind:kind,workflow:["edit","captions"].indexOf(item.workflow)>=0?item.workflow:"other",hasWarnings:!!item.reviewRequired,toast:!!toast,playSound:!!toast&&active.allowSound&&!!(deps.soundEnabled&&deps.soundEnabled()),panelVisible:!!panelVisible}));
    },
    observe:function(item,visible){
      if(!active||active.item!==item)return;
      pending.forEach(function(cmd){if(cmd.type==="incident"){cmd.panelVisible=!!visible;if(item.seen)cmd.toast=false;}});
      if(ready)send(Object.assign(command("observe"),{panelVisible:!!visible}));
    },
    clear:function(item){
      if(!active||(item&&active.item!==item))return;
      pending=[];if(ready)send(command("clear"));active=null;
    },
    hideToast:function(){
      if(!active)return;pending.forEach(function(cmd){if(cmd.type==="incident"){cmd.toast=false;cmd.playSound=false;}});if(ready)send(command("hide-toast"));
    },
    stop:function(){stopped=true;active=null;pending=[];if(timer)clearTimeout(timer);if(child)try{child.stdin.end();}catch(ignore){}}
  };
}
return {create:create};
}));
