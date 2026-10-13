const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const {RunCore:C,dispatchCore}=require('../Huati/Core/run-core.js');
const resources=path.join(__dirname,'../Huati/Resources');
const map=JSON.parse(fs.readFileSync(path.join(resources,'campus-map.json')));
const graph=JSON.parse(fs.readFileSync(path.join(resources,'campus-roads.json')));
const points=C.referencePoints;
const preview={points,lat:points[0].lat,lng:points[0].lng,student_id:'fixture-account',captured_at:0};
const time=text=>Date.parse(text+'+08:00');

test('coordinate conversion round-trips all known checkpoints',()=>{
  for(const p of points){const w=C.wgs(p),g=C.gcj(w);assert(C.distance(p,g)<0.01);assert(C.contains(w,map.boundary));}
  assert.deepEqual(C.gcj({lat:51,lng:0}),{lat:51,lng:0});
});
test('random origins stay in the actual campus polygon',()=>{
  for(let i=0;i<100;i++){const p=C.origin(null,map.boundary,i);assert(C.contains(C.wgs(p),map.boundary));assert.match(p.source,/定位失败/);}
  const outside=C.origin({lat:31.2,lng:121.4},map.boundary,2);assert.match(outside.source,/校外/);
  const inside=C.wgs(points[0]);assert.match(C.origin(inside,map.boundary,1).source,/手机当前位置/);
});
test('invalid parameters fail before record creation',()=>{
  for(const args of [[1999,900000,2600],[30001,900000,2600],[2200,59999,2600],[2200,7200001,2600],[2200,900000,0]])assert.throws(()=>C.parameters(...args));
  C.parameters(2200,900000,2600);assert.throws(()=>C.coordinate(NaN,121));
  assert.throws(()=>C.points([points[0],points[0],points[2]]));
});
test('basic routes visit every checkpoint and do not truncate an automatic route',()=>{
  for(const requested of [2000,2100,2200,3000]){const route=C.basic(preview,requested,true);assert(route.distance>=Math.max(2100,requested));for(const p of points)assert(Math.min(...route.route_samples.map(s=>C.distance(s,p)))<0.01);}
  const far={points:[{lat:30,lng:121},{lat:30.1,lng:121},{lat:30.2,lng:121}],lat:30,lng:121};
  assert(C.basic(far,2200,true).distance>20000);assert.throws(()=>C.basic(far,2200,false));
});
for(let seed=1;seed<=24;seed++)test(`manual road route seed ${seed} satisfies checkpoints and bounds`,()=>{
  const route=C.road(preview,2200,false,graph,map.boundary,seed);
  assert(route.distance>=2100&&route.distance<=2700);
  assert.equal(route.route_samples[0].fraction,0);assert.equal(route.route_samples.at(-1).fraction,1);
  let previous=-1;for(const p of route.route_samples){assert(p.fraction>previous);previous=p.fraction;assert(C.contains(C.wgs(p),map.boundary));}
  for(const p of points)assert(Math.min(...route.route_samples.map(s=>C.distance(s,p)))<0.1);
});
test('automatic road routes have no manual upper-bound restriction',()=>{
  for(let seed=1;seed<=8;seed++){
    const route=C.road(preview,2200,true,graph,map.boundary,seed);assert(route.distance>=2100);
    for(const p of points)assert(Math.min(...route.route_samples.map(s=>C.distance(s,p)))<0.1);
  }
  // A connected campus road winds north and south before reaching the three checkpoints.
  const wgsNodes=[C.wgs(points[0]),{lat:30.837,lng:121.5015},C.wgs(points[1]),{lat:30.8371,lng:121.5016},C.wgs(points[2])];
  const expanded={nodes:wgsNodes.map(p=>[p.lat,p.lng]),edges:[[0,1],[1,2],[2,3],[3,4]],campus:'fengxian'};
  const requested=2000;
  const r=C.road(preview,requested,true,expanded,map.boundary,17);assert(r.distance>requested+500);
  assert.throws(()=>C.road(preview,requested,false,expanded,map.boundary,17));
});
test('pausing freezes progress across reopening and continuing preserves duration',()=>{
  const initial={status:'created',start_ms:100000,duration_ms:720123,distance:2200,points,lat:preview.lat,lng:preview.lng,pauses:[],auto_submit:true};
  const paused=C.pause(initial,200000);assert.equal(C.remaining(paused,500000),620123);
  const reopened=JSON.parse(JSON.stringify(paused));assert.equal(C.remaining(reopened,700000),620123);
  const resumed=C.resume(reopened,800000);assert.equal(resumed.duration_ms,720123);assert.equal(C.remaining(resumed,900000),520123);
  assert.equal(C.remaining(resumed,1420123),0);assert.equal(initial.status,'created');
  assert.throws(()=>C.resume(resumed,900000));
});
test('pause timestamps become stationary intervals in the uploaded track',()=>{
  let run={status:'created',start_ms:100000,duration_ms:900000,distance:2200,points,lat:preview.lat,lng:preview.lng,route_samples:C.basic(preview,2200,true).route_samples,pauses:[]};
  run=C.resume(C.pause(run,200000),400000);const track=C.path(run,1200000);
  assert.equal(track[0].timestamp,100000);assert.equal(track.at(-1).timestamp,1200000);
  const a=track.find(p=>p.timestamp===200000),b=track.find(p=>p.timestamp===400000);assert.equal(a.lat,b.lat);assert.equal(a.lng,b.lng);
  for(let i=1;i<track.length;i++)assert(track[i].timestamp>track[i-1].timestamp);
});
test('discard stops local work and blocks resume, including uncertain states',()=>{
  for(const status of ['created','paused','check_failed','create_unknown','finish_unknown']){
    const run={status,start_ms:100000,duration_ms:900000,record_id:99,pauses:status==='paused'?[{start_ms:200000}]:[]};
    const out=C.discard(run,300000);assert.equal(out.record_id,99);assert.equal(out.auto_submit,false);assert.equal(C.unresolved(out),false);assert.throws(()=>C.resume(out,400000));
  }
  for(const status of ['checking','finish_pending','record_updated','finished'])assert.throws(()=>C.discard({status},0));
});
test('random milliseconds strictly stay between 12 and 16 minutes',()=>{
  assert.equal(C.randomDuration(0),720001);assert.equal(C.randomDuration(1-Number.EPSILON),959999);
  for(let i=0;i<1000;i++){const d=C.randomDuration(i/1000);assert(Number.isInteger(d)&&d>720000&&d<960000);}
  assert.throws(()=>C.randomDuration(1));
});
test('schedule respects Beijing day independently of host timezone',()=>{
  const now=time('2026-10-13T05:58:00'),settings={hour:6,minute:0,enabled:true};
  assert.equal(C.target(settings,now),time('2026-10-13T06:00:00'));assert.equal(C.opening(C.target(settings,now)),time('2026-10-13T06:00:00'));
  assert.equal(C.day(time('2026-10-13T00:00:00')),'2026-10-13');assert.equal(C.date(now),'2026-10-13 05:58:00');
  assert(C.validTime(21,0));assert(!C.validTime(21,1));assert(!C.validTime(5,59));
});
test('dated time reservation prevents duplicates while allowing another time today',()=>{
  const now=time('2026-10-13T06:15:00'),settings={hour:6,minute:15,enabled:true};
  const reserved=C.reserve(settings,now,now);assert(C.reserved(reserved,now));assert.equal(C.next(reserved,now),time('2026-10-14T06:15:00'));
  const changed={...reserved,hour:7,minute:30};assert.equal(C.next(changed,now),time('2026-10-13T07:30:00'));
  const both=C.reserve(changed,time('2026-10-13T07:30:00'),time('2026-10-13T07:30:00'));
  assert(C.reserved(both,now));assert(C.reserved(both,time('2026-10-13T07:30:00')));assert(C.reserved(both,time('2026-10-12T06:15:00')));
});
test('preparation rejects yesterday, pre-opening, stale and other-account points',()=>{
  const at=time('2026-10-13T06:00:00');
  const settings={enabled:true,student_id:'fixture-account',prep_target_ms:at,prep_status:'ready',prepared_refresh_ms:at,prepared_preview:{...preview,captured_at:at}};
  assert(C.ready(settings,at+1,at));
  assert(!C.ready({...settings,prepared_refresh_ms:at-1},at+1,at));
  assert(!C.ready(settings,at+300000,at));
  assert(!C.ready({...settings,prepared_preview:{...preview,student_id:'different',captured_at:at}},at,at));
});
test('directory stays separate from active three checkpoints',()=>{
  const input={campus:'华东理工大学奉贤校区',coordinate_system:'GCJ02',complete:true,points};
  const imported=C.catalogImport(input,map.boundary,100);assert(imported.complete);assert.equal(imported.points.length,3);
  const p={...C.gcj({lat:30.834,lng:121.500}),point_name:'fixture'};
  const merged=C.catalogMerge(imported,[p],map.boundary,200);assert(!merged.complete);assert.equal(merged.points.length,4);assert.equal(preview.points.length,3);
  assert.throws(()=>C.catalogImport({...input,campus:'other'},map.boundary,100));
});
test('native bridge returns structured errors without crashes',()=>{
  const output=JSON.parse(dispatchCore('coordinate','[null,121]'));assert.equal(output.ok,false);
  assert.equal(JSON.parse(dispatchCore('day',`[${time('2026-10-13T06:00:00')}]`)).value,'2026-10-13');
});
test('protocol AES fixture has the expected IV:ciphertext format',()=>{
  const cipher=crypto.createCipheriv('aes-128-cbc',Buffer.from('A7fK92LmXyQw8vRp'),Buffer.alloc(16));
  const raw=Buffer.concat([cipher.update('{"fixture":1}','utf8'),cipher.final()]);
  assert.equal(raw.toString('base64'),'BGu00rSpvgFKuj16y9KktQ==');
});
