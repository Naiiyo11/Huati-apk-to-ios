/* Local, deterministic protocol math. Native Swift owns networking and encrypted persistence. */
'use strict';
const RunCore = (() => {
  const fail = message => { throw new Error(message); };
  const check = (condition, message) => { if (!condition) fail(message); };
  const clone = value => JSON.parse(JSON.stringify(value));
  const orders = [[0,1,2],[0,2,1],[1,0,2],[1,2,0],[2,0,1],[2,1,0]];
  const referencePoints = [
    {point_name:'单双杠练习场',lat:30.832999,lng:121.509337},
    {point_name:'考核点 38',lat:30.827536,lng:121.503933},
    {point_name:'体育馆主馆',lat:30.829844,lng:121.507996}
  ];
  function coordinate(lat,lng) { check(Number.isFinite(lat)&&Number.isFinite(lng)&&Math.abs(lat)<=90&&Math.abs(lng)<=180,'坐标无效'); }
  function distance(a,b) {
    const r=Math.PI/180,dl=(b.lat-a.lat)*r,dg=(b.lng-a.lng)*r;
    const h=Math.sin(dl/2)**2+Math.cos(a.lat*r)*Math.cos(b.lat*r)*Math.sin(dg/2)**2;
    return 12742000*Math.asin(Math.min(1,Math.sqrt(h)));
  }
  function gcj(p) {
    coordinate(p.lat,p.lng);
    const {lat,lng}=p;
    if(lng<72.004||lng>137.8347||lat<0.8293||lat>55.8271)return {lat,lng};
    const x=lng-105,y=lat-35,pi=Math.PI;
    let a=-100+2*x+3*y+0.2*y*y+0.1*x*y+0.2*Math.sqrt(Math.abs(x));
    a+=(20*Math.sin(6*x*pi)+20*Math.sin(2*x*pi))*2/3+(20*Math.sin(y*pi)+40*Math.sin(y/3*pi))*2/3+(160*Math.sin(y/12*pi)+320*Math.sin(y*pi/30))*2/3;
    let b=300+x+2*y+0.1*x*x+0.1*x*y+0.1*Math.sqrt(Math.abs(x));
    b+=(20*Math.sin(6*x*pi)+20*Math.sin(2*x*pi))*2/3+(20*Math.sin(x*pi)+40*Math.sin(x/3*pi))*2/3+(150*Math.sin(x/12*pi)+300*Math.sin(x/30*pi))*2/3;
    const rad=lat*pi/180,magic=1-0.00669342162296594323*Math.sin(rad)**2,sqrt=Math.sqrt(magic);
    return {lat:lat+a*180/(6378245*(1-0.00669342162296594323)/(magic*sqrt)*pi),lng:lng+b*180/(6378245/sqrt*Math.cos(rad)*pi)};
  }
  function wgs(p) {let out={lat:p.lat,lng:p.lng};for(let i=0;i<5;i++){const g=gcj(out);out.lat-=g.lat-p.lat;out.lng-=g.lng-p.lng;}return out;}
  function contains(p,boundary) {
    if(!Number.isFinite(p.lat)||!Number.isFinite(p.lng))return false;
    let inside=false;
    for(let i=0,j=boundary.length-1;i<boundary.length;j=i++){
      const [y1,x1]=boundary[i],[y2,x2]=boundary[j];
      const cross=(p.lng-x1)*(y2-y1)-(p.lat-y1)*(x2-x1);
      if(Math.abs(cross)<1e-12&&p.lng>=Math.min(x1,x2)&&p.lng<=Math.max(x1,x2)&&p.lat>=Math.min(y1,y2)&&p.lat<=Math.max(y1,y2))return true;
      if((y1>p.lat)!=(y2>p.lat)&&p.lng<(x2-x1)*(p.lat-y1)/(y2-y1)+x1)inside=!inside;
    }
    return inside;
  }
  function origin(fix,boundary,index) {
    if(fix&&contains(fix,boundary))return {...gcj(fix),source:'手机当前位置（奉贤校区内）'};
    const p=referencePoints[index%referencePoints.length];
    check(contains(wgs(p),boundary),'随机起点超出校园边界');
    return {...p,source:fix?'校内随机模拟起点（当前位置在校外）':'校内随机模拟起点（定位失败）'};
  }
  function parameters(metres,duration,steps) {
    check(Number.isInteger(metres)&&metres>=2000&&metres<=30000&&Number.isInteger(duration)&&duration>=60000&&duration<=7200000&&Number.isInteger(steps)&&steps>0&&steps<=100000,'里程需为 2–30 公里，时长 1–120 分钟，请检查步数');
  }
  function points(input) {
    check(Array.isArray(input)&&input.length===3,'需要三个考核点');
    input.forEach((p,i)=>{coordinate(p.lat,p.lng);for(let j=0;j<i;j++)check(distance(p,input[j])>=0.1,'三个考核点必须不同');});
  }
  const interpolate = (a,b,ratio) => ({lat:a.lat+(b.lat-a.lat)*ratio,lng:a.lng+(b.lng-a.lng)*ratio});
  const length = line => line.slice(1).reduce((sum,p,i)=>sum+distance(line[i],p),0);
  function basic(preview,requested,scheduled) {
    points(preview.points);coordinate(preview.lat,preview.lng);
    const start={lat:preview.lat,lng:preview.lng},stops=[start,...preview.points,start];
    const mandatory=length(stops.slice(0,4));
    const metres=scheduled?Math.max(2100,requested,Math.ceil(mandatory)+2):requested;
    check(metres>=mandatory-20,'指定里程不足以经过本次三点，请增加里程');
    const samples=[{...start,fraction:0}];let travelled=0,current=start,index=1,cycles=0;
    while(travelled<metres){
      check(++cycles<10000,'路线无法补足里程');
      const target=stops[index],segment=distance(current,target);
      if(segment>0){
        const use=Math.min(segment,metres-travelled),count=Math.max(1,Math.ceil(use/8));
        for(let k=1;k<=count;k++){const part=use*k/count;samples.push({...interpolate(current,target,part/segment),fraction:(travelled+part)/metres});}
        travelled+=use;
      }
      current=target;index=index%4+1;
    }
    for(const p of preview.points)check(Math.min(...samples.map(s=>distance(s,p)))<=20,'指定里程不足以经过本次三点');
    return {distance:metres,requested_distance:requested,road_mode:false,scheduled_route:scheduled,route_samples:samples};
  }
  function road(preview,requested,scheduled,graph,boundary,seed) {
    points(preview.points);coordinate(preview.lat,preview.lng);
    let state=(seed>>>0)||1;
    const random=()=>{state^=state<<13;state^=state>>>17;state^=state<<5;return (state>>>0)/4294967296;};
    const nodes=graph.nodes.map(p=>gcj({lat:p[0],lng:p[1]})),adj=nodes.map(()=>[]);
    graph.edges.forEach(([a,b])=>{check(nodes[a]&&nodes[b]&&a!==b,'道路图无效');adj[a].push(b);adj[b].push(a);});
    const key=(a,b)=>Math.min(a,b)+':'+Math.max(a,b);
    function nearest(p){
      check(contains(wgs(p),boundary),'起点或考核点不在奉贤校区内');
      let best=-1,min=Infinity;nodes.forEach((n,i)=>{const d=distance(p,n);if(d<min){min=d;best=i;}});
      check(min<=120,'点位距已知道路超过 120 米，请更换起点或关闭道路路线');return best;
    }
    function shortest(from,to,used,penalty){
      const costs=nodes.map(()=>Infinity),parent=nodes.map(()=>-1),done=new Set();costs[from]=0;
      for(let n=0;n<nodes.length;n++){
        let a=-1,min=Infinity;costs.forEach((v,i)=>{if(!done.has(i)&&v<min){min=v;a=i;}});
        if(a<0)break;if(a===to)break;done.add(a);
        for(const b of adj[a]){const v=min+distance(nodes[a],nodes[b])*(used.has(key(a,b))?penalty:1);if(v<costs[b]){costs[b]=v;parent[b]=a;}}
      }
      check(Number.isFinite(costs[to]),'校园道路未连通');const out=[];for(let a=to;a>=0;a=parent[a]){out.unshift(a);if(a===from)break;}return out;
    }
    const append=(line,p)=>{if(!line.length||distance(line[line.length-1],p)>0.02)line.push({lat:p.lat,lng:p.lng});};
    const start={lat:preview.lat,lng:preview.lng},snapped=preview.points.map(nearest),begin=nearest(start);
    const lower=scheduled?2100:Math.max(2100,requested-500),upper=scheduled?Infinity:requested+500;
    let best=null,usedBest=null,last=begin,score=Infinity;
    for(const order of orders){
      const line=[],used=new Set();append(line,start);append(line,nodes[begin]);let at=begin;
      for(const i of order){
        const ids=shortest(at,snapped[i],used,1);
        ids.forEach((id,j)=>{append(line,nodes[id]);if(j)used.add(key(ids[j-1],id));});
        append(line,preview.points[i]);append(line,nodes[snapped[i]]);at=snapped[i];
      }
      const metres=length(line);if(Math.ceil(metres)>upper)continue;
      const cost=(scheduled?metres:Math.abs(metres-requested)+(metres>requested?200:0))+random()*30;
      if(cost<score){best=line;usedBest=used;last=at;score=cost;}
    }
    check(best,'经过三点的道路路线超过目标 +0.5 公里，请增加里程');
    const desired=Math.max(length(best),Math.max(lower+2,Math.min(upper-2,requested+random()*200-100)));
    for(let cycle=0;length(best)<desired-0.01;cycle++){
      check(cycle<100,'无法补足道路里程，请重新预览');
      const destination=Math.floor(random()*nodes.length);if(distance(nodes[last],nodes[destination])<120)continue;
      const ids=shortest(last,destination,usedBest,2.2);
      for(let i=1;i<ids.length;i++){
        const remaining=desired-length(best),a=best[best.length-1],b=nodes[ids[i]],segment=distance(a,b);
        if(segment<=remaining){append(best,b);usedBest.add(key(ids[i-1],ids[i]));last=ids[i];}
        else{append(best,interpolate(a,b,remaining/segment));break;}
      }
    }
    const samples=[];append(samples,best[0]);
    for(let i=1;i<best.length;i++){const a=best[i-1],b=best[i],count=Math.max(1,Math.ceil(distance(a,b)/8));for(let k=1;k<=count;k++)append(samples,interpolate(a,b,k/count));}
    samples.forEach(p=>check(contains(wgs(p),boundary),'本次道路路线越过校园边界，请重新预览'));
    const metres=length(samples),actual=Math.ceil(metres);check(metres>=lower&&actual<=upper,'道路路线不符合里程范围');
    const phase=random()*Math.PI*2;let total=0,travelled=0;samples[0].fraction=0;
    for(let i=1;i<samples.length;i++){const segment=distance(samples[i-1],samples[i]);travelled+=segment;total+=segment/(1+0.08*Math.sin(travelled/90+phase)+0.04*Math.cos(travelled/210+phase));samples[i].fraction=total;}
    samples.forEach(p=>p.fraction/=total);
    return {distance:actual,measured_metres:metres,requested_distance:requested,road_mode:true,scheduled_route:scheduled,route_samples:samples};
  }
  function unresolved(run){return !!run&&!['finished','discarded'].includes(run.status);}
  function moving(run,now){
    if(!run)return 0;const end=run.status==='discarded'?run.discarded_at:(run.end_ms??now);
    const paused=(run.pauses||[]).reduce((sum,p)=>sum+Math.max(0,Math.min(end,p.end_ms??end)-Math.max(run.start_ms,p.start_ms)),0);
    return Math.max(0,end-run.start_ms-paused);
  }
  const duration=run=>run.duration_ms??run.duration*1000;
  const remaining=(run,now)=>Math.max(0,duration(run)-moving(run,now));
  function pause(run,now){check(run&&run.status==='created','当前记录不能暂停');const out=clone(run);out.pauses=out.pauses||[];out.pauses.push({start_ms:now});out.status='paused';out.auto_submit=false;return out;}
  function resume(run,now){check(run&&run.status==='paused','当前记录不是暂停状态');const out=clone(run),last=out.pauses[out.pauses.length-1];check(!last.end_ms&&now>=last.start_ms,'暂停时间无效');last.end_ms=now;out.status='created';out.auto_submit=true;delete out.error;return out;}
  function discard(run,now){
    check(run&&['created','paused','check_failed','create_unknown','finish_unknown'].includes(run.status),'正在提交或已经处理，不能舍弃');
    const out=clone(run);if(out.status==='paused'){const last=out.pauses[out.pauses.length-1];check(now>=last.start_ms,'手机时间发生变化');last.end_ms=now;}
    out.discarded_from=out.status;out.status='discarded';out.discarded_at=now;out.auto_submit=false;out.error='已舍弃本地任务，服务器已创建记录仍保留。';return out;
  }
  function path(run,end){
    const active=moving(run,end);check(active>0,'模拟时长无效');
    const samples=run.route_samples||basic({points:run.points,lat:run.lat,lng:run.lng},run.distance,false).route_samples;
    const pauses=run.pauses||[],out=new Map();
    samples.forEach(p=>{
      const activeOffset=Math.round(p.fraction*active);let offset=0;
      for(const pause of pauses){check(Number.isFinite(pause.end_ms)&&pause.end_ms>=pause.start_ms&&pause.start_ms>=run.start_ms&&pause.end_ms<=end,'暂停区间无效');if(pause.start_ms-run.start_ms-offset<=activeOffset)offset+=pause.end_ms-pause.start_ms;else break;}
      const timestamp=run.start_ms+activeOffset+offset;out.set(timestamp,{name:'',lat:p.lat,lng:p.lng,timestamp,accuracy:5});
    });
    let offset=0;
    for(const pause of pauses){
      const fraction=(pause.start_ms-run.start_ms-offset)/active;
      let p=samples[0];
      for(let i=1;i<samples.length;i++){if(samples[i].fraction>=fraction){const a=samples[i-1],b=samples[i];p=interpolate(a,b,(fraction-a.fraction)/(b.fraction-a.fraction));break;}p=samples[i];}
      for(const timestamp of [pause.start_ms,pause.end_ms])out.set(timestamp,{name:'',...p,timestamp,accuracy:5});
      offset+=pause.end_ms-pause.start_ms;
    }
    return Array.from(out.values()).sort((a,b)=>a.timestamp-b.timestamp);
  }
  const local=ms=>new Date(ms+28800000);
  const day=ms=>local(ms).toISOString().slice(0,10);
  const slot=ms=>local(ms).toISOString().slice(11,16);
  const date=ms=>local(ms).toISOString().slice(0,19).replace('T',' ');
  function target(settings,now){check(validTime(settings.hour,settings.minute),'自动时间需在北京时间 06:00–21:00');const d=local(now);d.setUTCHours(settings.hour,settings.minute,0,0);return d.getTime()-28800000;}
  const opening=at=>{const d=local(at);d.setUTCHours(6,0,0,0);return d.getTime()-28800000;};
  const validTime=(hour,minute)=>Number.isInteger(hour)&&Number.isInteger(minute)&&hour>=6&&hour<=21&&minute>=0&&minute<60&&(hour<21||minute===0);
  function reserved(settings,at){return !!settings.attempt_day&&(day(at)<settings.attempt_day||(day(at)===settings.attempt_day&&(settings.attempted_times||[]).includes(slot(at))));}
  function reserve(settings,at,now){const out=clone(settings);if(out.attempt_day!==day(at))out.attempted_times=[];if(!out.attempted_times.includes(slot(at)))out.attempted_times.push(slot(at));out.attempt_day=day(at);out.last_attempt_ms=now;out.last_target_ms=at;return out;}
  function next(settings,now){let at=target(settings,now);if(at<=now||reserved(settings,at))at+=86400000;const saved=settings.last_attempt_ms||0;while(at<saved||reserved(settings,at))at+=86400000;return at;}
  function ready(settings,now,at){
    const p=settings.prepared_preview,fresh=Math.max(at-120000,opening(at));
    return !!(settings.enabled&&settings.prep_target_ms===at&&settings.prep_status==='ready'&&day(now)===day(at)&&p&&p.student_id===settings.student_id&&settings.prepared_refresh_ms>=fresh&&settings.prepared_refresh_ms<=p.captured_at&&p.captured_at>=fresh&&p.captured_at<=now&&now-p.captured_at<300000&&p.points.length===3);
  }
  function randomDuration(unit){check(unit>=0&&unit<1,'随机值无效');return 720001+Math.floor(unit*239999);}
  function normalPoint(p,system,boundary){
    coordinate(p.lat,p.lng);const raw={lat:p.lat,lng:p.lng},w=system==='WGS84'?raw:wgs(raw);check(contains(w,boundary),'点位不在奉贤校区内');
    const mapped=system==='WGS84'?gcj(raw):raw,name=String(p.point_name||p.name||'考核点').trim();check(name.length>0&&name.length<=80,'点位名称需为 1–80 字');return {...mapped,point_name:name,...(p.id?{id:String(p.id)}:{})};
  }
  function catalogImport(input,boundary,now){
    check(input.campus==='华东理工大学奉贤校区'&&['GCJ02','WGS84'].includes(input.coordinate_system),'点位表校区或坐标系无效');
    check(Array.isArray(input.points)&&input.points.length>0&&input.points.length<=600,'点位表需包含 1–600 个点位');
    return {campus:input.campus,coordinate_system:'GCJ02',complete:!!input.complete,imported:true,source:String(input.source||'用户导入点位表').slice(0,200),updated_at:now,points:input.points.map(p=>normalPoint(p,input.coordinate_system,boundary))};
  }
  function catalogMerge(previous,input,boundary,now){
    const out=clone(previous||{complete:false,points:referencePoints,source:'公开参考与历次服务器点位'});
    for(const raw of input){const p=normalPoint(raw,'GCJ02',boundary),i=out.points.findIndex(old=>(p.id&&p.id===old.id)||(distance(p,old)<10&&(!p.id||!old.id||p.id===old.id)));
      if(i<0){out.points.push(p);out.complete=false;}else{out.points[i]={...out.points[i],...p};}}
    check(out.points.length<=600,'点位目录超过 600 项');out.updated_at=now;return out;
  }
  function mapPoints(input){return input.map(p=>({...p,...wgs(p)}));}
  return {coordinate,distance,gcj,wgs,contains,origin,parameters,points,basic,road,unresolved,moving,duration,remaining,pause,resume,discard,path,day,slot,date,target,opening,validTime,reserved,reserve,next,ready,randomDuration,catalogImport,catalogMerge,mapPoints,referencePoints};
})();
function dispatchCore(name,argsJSON){try{if(typeof RunCore[name]!=='function')throw new Error('未知本地操作');return JSON.stringify({ok:true,value:RunCore[name](...JSON.parse(argsJSON))});}catch(error){return JSON.stringify({ok:false,error:error.message});}}
if(typeof module!=='undefined')module.exports={RunCore,dispatchCore};
