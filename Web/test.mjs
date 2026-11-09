import test from 'node:test';
import assert from 'node:assert/strict';
import {NoteStore,COLORS,FONTS,STORAGE_KEY,validateArchive,newID,emptyContent} from './core.js';

class MemoryStorage {
  values = new Map();
  getItem(key) { return this.values.get(key) ?? null; }
  setItem(key,value) { this.values.set(key,String(value)); }
  removeItem(key) { this.values.delete(key); }
}
const makeStore = (options={}) => new NoteStore({storage:new MemoryStorage(),seed:false,listen:false,...options});
class FakeClock {
  time=0; nextID=1; timers=new Map();
  now=()=>this.time;
  setTimeout=(run,delay)=>{const id=this.nextID++;this.timers.set(id,{run,at:this.time+delay});return id;};
  clearTimeout=id=>this.timers.delete(id);
  advance(milliseconds) {
    const end=this.time+milliseconds;
    while(true){const next=[...this.timers].filter(([,timer])=>timer.at<=end).sort((a,b)=>a[1].at-b[1].at)[0];if(!next)break;this.time=next[1].at;this.timers.delete(next[0]);next[1].run();}
    this.time=end;
  }
}
const nativeFixture = {"modifiedAt":1700000000000,"groups":[],"version":1,"notes":[{"content":{"items":[],"title":"","text":"","strokes":[]},"font":"system","updatedAt":1700000000000,"id":"F3F182B5-6384-4132-86D4-D6F5D9B2A281","kind":"text","history":[],"color":"butter","encryptedContent":{"iterations":600000,"sealedData":"QjdCwByHnyUU8ggYNZkWBkJ2Kgd\/BQpI9NCD826E3cpxVU1E50oJby751G9ESHBmdaGwP4gD9+kxT6w0L8ZiZ5Fl6sjpyKJ505N84EAG6tvX6bjd4hPPxOCC86gz7QXKNzUfc+Rx2YEuO6YZokKIox5FLCcamlYFwwGOCl76OC7tS4b8HaYjMIPgYVj++AqSLJc\/WRkI10fGUCq2zMhFphWN+p2DAHDVQ+hTBNdOXWjWvF1oJBc422km03+pBNf8VxbIz7V+UWboMXMdg\/8spdiDOljwdk7T4YtdvgRkG4\/1G1DIrN1C15HSmj46EjqZpHnj4uBq5Oxu9gJH4VQs+\/9IhWdCeFs\/CBPG18MIZu5qgHPVzd8woFU86d9ohn74pGAT4AmGYhh1OOj1+F7HTFbKo1+w0YPFc1JHSpsQUsu9Nzg7z3b41YJll5M1ERW+fxB3Q1oPBpd2o0Eg8+cMKrvxb8bM2diCUAm9\/0rOA9IYk2ct5nttE6scE38Ii0tw6DyJbkpxDbx9hB6FnuNBdwReo1hbgyIE2l0j7SkBrg==","salt":"AAECAwQFBgcICQoLDA0ODw=="},"createdAt":1700000000000,"fontSize":18,"isPinned":false}]};

test('palette, fonts and seed data match native capabilities',async()=>{
  const store=makeStore({seed:true});
  assert.equal(COLORS.length,25);assert.equal(FONTS.length,16);assert.equal(store.notes.length,6);assert.equal(store.groups.length,3);
  assert.equal(new Set(COLORS.map(x=>x.id)).size,25);
  await store.flush();assert.equal(validateArchive(store.exportArchive()).notes.length,6);store.dispose();
});

test('offline create, edit, checklist and reload persist',async()=>{
  const storage=new MemoryStorage(),store=makeStore({storage});
  const group=store.addGroup('Work','briefcase'),id=store.createNote('checklist',group);
  await store.updateNote(id,note=>{note.content.title='Ship it';note.content.items[0].text='Finish tests';note.content.items[0].isCompleted=true;note.font='serif';note.color='mint';});
  await store.flush();const restored=makeStore({storage});
  assert.equal(restored.notes[0].content.title,'Ship it');assert.equal(restored.notes[0].content.items[0].isCompleted,true);assert.equal(restored.notes[0].font,'serif');assert.equal(restored.groups[0].id,group);
  store.dispose();restored.dispose();
});

test('trash is recoverable and group deletion preserves notes',async()=>{
  const store=makeStore(),group=store.addGroup('Personal'),id=store.createNote('text',group);
  await store.updateNote(id,n=>n.content.text='Keep this');await store.deleteNote(id);
  assert.ok(store.notes[0].deletedAt);await store.restoreNote(id);assert.equal(store.notes[0].deletedAt,null);
  store.deleteGroup(group);assert.equal(store.groups.length,0);assert.equal(store.notes[0].groupID,null);
  const archive=JSON.parse(store.exportArchive());assert.ok(archive.groups[0].deletedAt);assert.equal(archive.notes[0].content.text,'Keep this');store.dispose();
});

test('history captures old text and restoration is itself recoverable',async()=>{
  const store=makeStore(),id=store.createNote();await store.updateNote(id,n=>n.content.text='First');await store.updateNote(id,n=>n.content.text='Second');
  const first=store.notes[0].history.find(x=>x.content.text==='First');assert.ok(first);
  await store.restoreSnapshot(id,first.id);assert.equal(store.notes[0].content.text,'First');assert.ok(store.notes[0].history.some(x=>x.content.text==='Second'));
  for(let i=0;i<55;i++){if(store.notes[0].history.length)store.notes[0].history.at(-1).date=Date.now()-31_000;await store.updateNote(id,n=>n.content.text=`Version ${i}`);}
  assert.equal(store.notes[0].history.length,50);store.dispose();
});

test('password protection scrubs plaintext from archive and both browser copies',async()=>{
  const storage=new MemoryStorage(),store=makeStore({storage}),id=store.createNote();
  await store.updateNote(id,n=>{n.content.title='Sensitive title';n.content.text='Secret body';n.content.richHTML='<b>Secret body</b>';});await store.flush();
  await store.updateNote(id,n=>n.content.text='Secret revision');await store.flush();
  await store.lockNote(id,'correct-password');assert.equal(store.isLocked(id),true);
  for(const raw of [...storage.values.values(),store.exportArchive()]){assert.ok(!raw.includes('Sensitive title'));assert.ok(!raw.includes('Secret body'));assert.ok(!raw.includes('Secret revision'));}
  await assert.rejects(()=>store.unlockNote(id,'wrong-password'),/password/i);
  await store.unlockNote(id,'correct-password');assert.equal(store.notes[0].content.text,'Secret revision');assert.ok(store.notes[0].history.some(x=>x.content.text==='Secret body'));
  assert.ok(!store.exportArchive().includes('Secret revision'));store.relockAll();assert.equal(store.notes[0].content.text,'');store.dispose();
});

test('rapid protected edits and immediate relock retain the latest ciphertext',async()=>{
  const store=makeStore(),id=store.createNote();await store.updateNote(id,n=>n.content.text='Initial');await store.lockNote(id,'password-123');await store.unlockNote(id,'password-123');
  const edits=[];for(let i=0;i<30;i++)edits.push(store.updateNote(id,n=>n.content.text=`Latest ${i}`));
  store.relockAll();assert.equal(store.notes[0].content.text,'');await Promise.all(edits);await store.flush();
  await store.unlockNote(id,'password-123');assert.equal(store.notes[0].content.text,'Latest 29');store.dispose();
});

test('metadata edits during password derivation do not discard decrypted content',async()=>{
  const store=makeStore(),id=store.createNote();await store.updateNote(id,n=>n.content.text='Keep decrypted content');await store.lockNote(id,'password-123');
  const pending=store.unlockNote(id,'password-123');await new Promise(resolve=>setTimeout(resolve,10));await store.updateNote(id,n=>n.isPinned=true);await pending;
  assert.equal(store.notes[0].isPinned,true);assert.equal(store.notes[0].content.text,'Keep decrypted content');store.dispose();
});

test('encrypted duplicate uses the new UUID as authenticated data',async()=>{
  const store=makeStore(),id=store.createNote();await store.updateNote(id,n=>{n.content.title='Original';n.content.text='Private';});await store.lockNote(id,'password-123');await store.unlockNote(id,'password-123');
  const duplicate=await store.duplicateNote(id);assert.notEqual(duplicate,id);store.relockAll();await store.unlockNote(duplicate,'password-123');assert.equal(store.notes.find(n=>n.id===duplicate).content.title,'Original copy');store.dispose();
});

test('background relock cancels an in-flight unlock',async()=>{
  const store=makeStore(),id=store.createNote();await store.updateNote(id,n=>n.content.text='Never reveal after relock');await store.lockNote(id,'password-123');
  const unlock=store.unlockNote(id,'password-123');await new Promise(resolve=>setTimeout(resolve,10));store.relockAll();await assert.rejects(()=>unlock,/changed/);assert.equal(store.isLocked(id),true);assert.equal(store.notes[0].content.text,'');store.dispose();
});

test('background relock also protects a duplicate still being encrypted',async()=>{
  const store=makeStore(),id=store.createNote();await store.updateNote(id,n=>n.content.text='Private duplicate');await store.lockNote(id,'password-123');await store.unlockNote(id,'password-123');
  const duplicate=store.duplicateNote(id);store.relockAll();const copied=await duplicate;assert.equal(store.isLocked(copied),true);assert.equal(store.notes.find(n=>n.id===copied).content.text,'');await store.unlockNote(copied,'password-123');assert.equal(store.notes.find(n=>n.id===copied).content.text,'Private duplicate');store.dispose();
});

test('swapping an encrypted payload onto another note is rejected',async()=>{
  const store=makeStore(),id=store.createNote();await store.updateNote(id,n=>n.content.text='Bound to UUID');await store.lockNote(id,'password-123');
  const archive=JSON.parse(store.exportArchive());archive.notes[0].id=newID();const other=makeStore();await other.importArchive(JSON.stringify(archive));
  await assert.rejects(()=>other.unlockNote(archive.notes[0].id,'password-123'),/password/i);store.dispose();other.dispose();
});

test('removing protection requires the password and preserves content',async()=>{
  const store=makeStore(),id=store.createNote();await store.updateNote(id,n=>n.content.text='Unlock for good');await store.lockNote(id,'password-123');
  await assert.rejects(()=>store.removePassword(id,'wrong-password'));await store.removePassword(id,'password-123');assert.equal(store.notes[0].encryptedContent,null);assert.equal(store.notes[0].content.text,'Unlock for good');store.dispose();
});

test('native Swift AES-GCM fixture decrypts with content and history intact',async()=>{
  const store=makeStore();await store.importArchive(JSON.stringify(nativeFixture));const id=store.notes[0].id;
  await store.unlockNote(id,'native-password-123');assert.equal(store.notes[0].content.title,'Native fixture');assert.equal(store.notes[0].content.text,'Hello from Swift — café ☀️');assert.equal(store.notes[0].history[0].content.title,'History secret');assert.equal(store.notes[0].content.items[0].isCompleted,true);store.dispose();
});

test('merge keeps newer local edits and imports deletion tombstones',async()=>{
  const local=makeStore(),group=local.addGroup('Work'),id=local.createNote('text',group);await local.updateNote(id,n=>n.content.text='Version one');
  const remote=makeStore();await remote.importArchive(local.exportArchive());await remote.deleteNote(id);remote.deleteGroup(group);await local.mergeArchive(remote.exportArchive());
  assert.ok(local.notes[0].deletedAt);assert.equal(local.groups.length,0);
  const stale=JSON.parse(remote.exportArchive());stale.notes[0].updatedAt=1;stale.notes[0].deletedAt=null;await local.mergeArchive(stale);assert.ok(local.notes[0].deletedAt);local.dispose();remote.dispose();
});

test('equal-timestamp note and group edits converge by revision UUID in either merge order',async()=>{
  const seed=makeStore(),group=seed.addGroup('Original group'),id=seed.createNote('text',group);
  const low=JSON.parse(seed.exportArchive()),high=structuredClone(low);
  low.notes[0].revisionID='00000000-0000-4000-8000-000000000001';high.notes[0].revisionID='00000000-0000-4000-8000-000000000002';
  low.groups[0].revisionID=low.notes[0].revisionID;high.groups[0].revisionID=high.notes[0].revisionID;
  low.notes[0].content.text='Losing revision';high.notes[0].content.text='Winning revision';low.groups[0].name='Losing group';high.groups[0].name='Winning group';
  const a=makeStore(),b=makeStore();await a.importArchive(low);await b.importArchive(high);await a.mergeArchive(high);await b.mergeArchive(low);
  assert.equal(a.notes[0].content.text,'Winning revision');assert.equal(b.notes[0].content.text,'Winning revision');assert.equal(a.groups[0].name,'Winning group');assert.equal(b.groups[0].name,'Winning group');
  const revision=a.notes[0].revisionID;await a.updateNote(id,n=>n.color='mint');assert.notEqual(a.notes[0].revisionID,revision);seed.dispose();a.dispose();b.dispose();
});

test('legacy archives without revision UUIDs remain importable',()=>{
  const decoded=validateArchive(nativeFixture);assert.equal(decoded.notes[0].revisionID,null);
});

test('merging a protected remote revision clears a locally unlocked note',async()=>{
  const local=makeStore(),id=local.createNote();await local.updateNote(id,n=>n.content.text='Private');await local.lockNote(id,'password-123');await local.unlockNote(id,'password-123');
  const remote=makeStore();await remote.importArchive(local.exportArchive());await remote.unlockNote(id,'password-123');await remote.updateNote(id,n=>n.content.text='Changed elsewhere');await remote.flush();await local.mergeArchive(remote.exportArchive());
  assert.equal(local.isLocked(id),true);assert.equal(local.notes[0].content.text,'');await local.unlockNote(id,'password-123');assert.equal(local.notes[0].content.text,'Changed elsewhere');local.dispose();remote.dispose();
});

test('invalid import is atomic and duplicate identities are rejected',async()=>{
  const store=makeStore(),id=store.createNote();await store.updateNote(id,n=>n.content.text='Untouched');const before=store.exportArchive();
  await assert.rejects(()=>store.importArchive('{broken'));assert.equal(store.exportArchive(),before);
  const duplicate=JSON.parse(before);duplicate.notes.push(structuredClone(duplicate.notes[0]));assert.throws(()=>validateArchive(duplicate));
  duplicate.notes.pop();duplicate.notes[0].fontSize=1e300;assert.throws(()=>validateArchive(duplicate));store.dispose();
});

test('malformed saved data is preserved and valid backup is recovered',async()=>{
  const storage=new MemoryStorage();storage.setItem(STORAGE_KEY,'broken');const readonly=makeStore({storage,seed:true});assert.equal(readonly.notes.length,0);assert.equal(readonly.saveStatus,'Recovery needed');await readonly.flush();assert.equal(storage.getItem(STORAGE_KEY),'broken');
  const good=makeStore();const id=good.createNote();await good.updateNote(id,n=>n.content.title='Recovered');storage.setItem(STORAGE_KEY+'.backup',good.exportArchive());
  const recovered=makeStore({storage});assert.equal(recovered.notes[0].content.title,'Recovered');assert.match(recovered.errorMessage,/recovered/);assert.equal(storage.getItem(STORAGE_KEY),'broken');readonly.dispose();good.dispose();recovered.dispose();
});

test('storage failures are surfaced instead of claiming a successful save',async()=>{
  const storage=new MemoryStorage();storage.setItem=()=>{throw new DOMException('Full','QuotaExceededError');};const store=makeStore({storage});store.createNote();await assert.rejects(()=>store.flush());assert.equal(store.saveStatus,'Couldn’t save');assert.match(store.errorMessage,/full/);store.dispose();
});

test('import sanitizes stray cleartext attached to encrypted notes',()=>{
  const archive=structuredClone(nativeFixture);archive.notes[0].content={...emptyContent(),title:'Leaked plaintext'};archive.notes[0].history=[{id:newID(),date:Date.now(),content:{...emptyContent(),text:'Leaked history'}}];
  const cleaned=validateArchive(archive);assert.equal(cleaned.notes[0].content.title,'');assert.deepEqual(cleaned.notes[0].history,[]);
});

test('late offline plaintext metadata cannot remove protection in either merge order',async()=>{
  const secure=makeStore(),id=secure.createNote();await secure.updateNote(id,n=>n.content.text='Never restore this plaintext');
  const stale=JSON.parse(secure.exportArchive());await secure.lockNote(id,'protection-password');const protectedArchive=secure.exportArchive();
  stale.notes[0].updatedAt=Date.now()+3_600_000;stale.notes[0].revisionID='FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF';stale.notes[0].isPinned=true;stale.notes[0].color='rose';
  await secure.mergeArchive(stale);assert.equal(secure.isLocked(id),true);assert.equal(secure.notes[0].content.text,'');assert.ok(!secure.exportArchive().includes('Never restore this plaintext'));
  const offline=makeStore();await offline.importArchive(stale);await offline.mergeArchive(protectedArchive);assert.equal(offline.isLocked(id),true);assert.deepEqual(offline.notes[0].encryptedContent,secure.notes[0].encryptedContent);secure.dispose();offline.dispose();
});

test('explicit removal wins over late encrypted metadata and new lock wins over old password',async()=>{
  const store=makeStore(),id=store.createNote();await store.updateNote(id,n=>n.content.text='Deliberately removed password');await store.lockNote(id,'first-password');
  const old=JSON.parse(store.exportArchive()),lockEpoch=old.notes[0].protectionUpdatedAt;await store.removePassword(id,'first-password');const removalEpoch=store.notes[0].protectionUpdatedAt;assert.ok(removalEpoch>lockEpoch);
  old.notes[0].updatedAt=Date.now()+3_600_000;old.notes[0].isPinned=true;await store.mergeArchive(old);assert.equal(store.notes[0].encryptedContent,null);assert.equal(store.notes[0].content.text,'Deliberately removed password');
  const other=makeStore();await other.importArchive(old);await other.mergeArchive(store.exportArchive());assert.equal(other.notes[0].encryptedContent,null);assert.equal(other.notes[0].protectionRevisionID,store.notes[0].protectionRevisionID);
  await store.lockNote(id,'second-password');assert.ok(store.notes[0].protectionUpdatedAt>removalEpoch);await store.mergeArchive(old);await store.unlockNote(id,'second-password');assert.equal(store.notes[0].content.text,'Deliberately removed password');store.dispose();other.dispose();
});

test('legacy encrypted records outrank epoch-less plaintext and explicit removal advances legacy epoch',async()=>{
  const store=makeStore();await store.importArchive(nativeFixture);const id=store.notes[0].id;
  const plaintext=structuredClone(nativeFixture);plaintext.notes[0].encryptedContent=null;plaintext.notes[0].updatedAt=Date.now()+3_600_000;plaintext.notes[0].content={...emptyContent(),text:'Stale unprotected copy'};
  await store.mergeArchive(plaintext);assert.equal(store.isLocked(id),true);await store.removePassword(id,'native-password-123');assert.ok(store.notes[0].protectionUpdatedAt>nativeFixture.notes[0].updatedAt);
  await store.mergeArchive(nativeFixture);assert.equal(store.notes[0].encryptedContent,null);assert.equal(store.notes[0].content.title,'Native fixture');store.dispose();
});

test('ordinary edits cannot forge or clear the protection transition version',async()=>{
  const store=makeStore(),id=store.createNote();await store.updateNote(id,n=>{n.protectionUpdatedAt=Date.now()+10_000;n.protectionRevisionID=newID();});assert.equal(store.notes[0].protectionUpdatedAt,null);
  await store.lockNote(id,'version-password');const epoch=store.notes[0].protectionUpdatedAt,revision=store.notes[0].protectionRevisionID;
  await store.updateNote(id,n=>{n.isPinned=true;n.protectionUpdatedAt=null;n.protectionRevisionID=null;});assert.equal(store.notes[0].protectionUpdatedAt,epoch);assert.equal(store.notes[0].protectionRevisionID,revision);store.dispose();
});

test('PIN locking validates digits and keeps PIN-encrypted content private',async()=>{
  const store=makeStore(),id=store.createNote();await store.updateNote(id,n=>n.content.text='A private PIN note');
  for(const pin of ['123','1234567890123','12ab','１２３４'])await assert.rejects(()=>store.lockNote(id,pin,{credentialType:'pin'}),/4 to 12 digits/);
  await assert.rejects(()=>store.lockNote(id,'1234'),/8 characters/);
  await store.lockNote(id,'0042',{credentialType:'pin'});assert.equal(store.isLocked(id),true);
  await assert.rejects(()=>store.unlockNote(id,'0043'));assert.equal(store.isLocked(id),true);
  await store.unlockNote(id,'0042');assert.equal(store.notes[0].content.text,'A private PIN note');
  assert.ok(!store.exportArchive().includes('A private PIN note'));store.dispose();
});

test('protected notes auto-lock exactly two minutes after unlock even while edited',async()=>{
  const clock=new FakeClock(),store=makeStore({clock}),id=store.createNote();
  await store.updateNote(id,n=>{n.content.title='Private title';n.content.text='Earlier private text';});await store.updateNote(id,n=>n.content.text='Current private text');
  await store.lockNote(id,'0420',{credentialType:'pin'});await store.unlockNote(id,'0420');assert.equal(store.autoLockSeconds,120);
  clock.advance(119_000);await store.updateNote(id,n=>n.content.text='Last edit');clock.advance(999);assert.equal(store.isLocked(id),false);
  clock.advance(1);assert.equal(store.isLocked(id),true);assert.deepEqual(store.notes[0].content,emptyContent());assert.deepEqual(store.notes[0].history,[]);
  await store.flush();await store.unlockNote(id,'0420');assert.equal(store.notes[0].content.text,'Last edit');assert.ok(store.notes[0].history.length);
  clock.advance(119_999);assert.equal(store.isLocked(id),false);clock.advance(1);assert.equal(store.isLocked(id),true);store.dispose();assert.equal(clock.timers.size,0);
});

test('auto-lock settings persist locally and changes apply from the original unlock time',async()=>{
  const storage=new MemoryStorage(),clock=new FakeClock(),store=makeStore({storage,clock}),id=store.createNote();
  await store.lockNote(id,'1234',{credentialType:'pin'});await store.unlockNote(id,'1234');clock.advance(40_000);
  store.autoLockSeconds=300;clock.advance(80_000);assert.equal(store.isLocked(id),false);
  store.autoLockSeconds=60;assert.equal(store.isLocked(id),true);
  assert.throws(()=>store.autoLockSeconds=0,/auto-lock/);assert.equal(store.autoLockSeconds,60);
  const reloaded=makeStore({storage});assert.equal(reloaded.autoLockSeconds,60);assert.equal(reloaded.isLocked(id),true);
  const imported=makeStore();await imported.importArchive(store.exportArchive());assert.equal(imported.autoLockSeconds,120);
  store.dispose();reloaded.dispose();imported.dispose();
});

test('protected duplicates inherit the original auto-lock deadline',async()=>{
  const clock=new FakeClock(),store=makeStore({clock}),id=store.createNote();await store.updateNote(id,n=>n.content.text='Duplicated secret');
  await store.lockNote(id,'6789',{credentialType:'pin'});await store.unlockNote(id,'6789');clock.advance(90_000);
  const duplicate=await store.duplicateNote(id);assert.equal(store.isLocked(duplicate),false);
  clock.advance(30_000);assert.equal(store.isLocked(id),true);assert.equal(store.isLocked(duplicate),true);assert.equal(clock.timers.size,0);
  await store.unlockNote(duplicate,'6789');assert.equal(store.notes.find(n=>n.id===duplicate).content.text,'Duplicated secret');store.dispose();
});

test('manual relock cancels its timer and removing protection leaves content editable',async()=>{
  const clock=new FakeClock(),store=makeStore({clock}),id=store.createNote();await store.updateNote(id,n=>n.content.text='Keep after removal');
  await store.lockNote(id,'9876',{credentialType:'pin'});await store.unlockNote(id,'9876');clock.advance(60_000);store.relockAll();assert.equal(clock.timers.size,0);
  await store.unlockNote(id,'9876');clock.advance(60_000);assert.equal(store.isLocked(id),false);
  await store.removePassword(id,'9876');assert.equal(clock.timers.size,0);clock.advance(600_000);assert.equal(store.notes[0].content.text,'Keep after removal');assert.equal(store.notes[0].encryptedContent,null);store.dispose();
});

test('expired notes lock on resume even if the browser delayed the timer',async()=>{
  const clock=new FakeClock(),store=makeStore({clock}),id=store.createNote();await store.lockNote(id,'1111',{credentialType:'pin'});await store.unlockNote(id,'1111');
  clock.time=180_000;store.lockExpiredNotes();assert.equal(store.isLocked(id),true);assert.equal(clock.timers.size,0);store.dispose();
});

test('immediate background lock cancels unlock before pending saves settle',async()=>{
  const store=makeStore(),id=store.createNote();await store.lockNote(id,'2222',{credentialType:'pin'});
  const unlock=store.unlockNote(id,'2222');store.relockAll();await assert.rejects(()=>unlock,/changed/);assert.equal(store.isLocked(id),true);store.dispose();
});

test('lengthening the timeout cannot revive an expired session when timers are delayed',async()=>{
  for(const crossTab of [false,true]){
    const clock=new FakeClock(),store=makeStore({clock}),id=store.createNote();await store.lockNote(id,'3333',{credentialType:'pin'});await store.unlockNote(id,'3333');
    clock.time=121_000;
    if(crossTab)store._storageListener({key:STORAGE_KEY+'.autoLockSeconds',newValue:'300'});else store.autoLockSeconds=300;
    assert.equal(store.isLocked(id),true);assert.equal(store.autoLockSeconds,300);assert.equal(clock.timers.size,0);store.dispose();
  }
});

test('overdue content edits, duplication, and history restore require fresh authentication',async()=>{
  const clock=new FakeClock(),store=makeStore({clock}),id=store.createNote();
  await store.updateNote(id,n=>n.content.text='Earlier secret');await store.updateNote(id,n=>n.content.text='Current secret');const snapshot=store.notes[0].history[0].id;
  await store.lockNote(id,'4444',{credentialType:'pin'});
  for(const operation of [()=>store.updateNote(id,n=>n.content.text='Should not save'),()=>store.duplicateNote(id),()=>store.restoreSnapshot(id,snapshot)]){
    await store.unlockNote(id,'4444');clock.time+=121_000;
    await assert.rejects(operation,/Unlock/);assert.equal(store.isLocked(id),true);assert.equal(store.notes[0].content.text,'');
  }
  await store.unlockNote(id,'4444');assert.equal(store.notes[0].content.text,'Current secret');store.dispose();
});

test('fresh authentication after an overdue session receives a new complete timeout',async()=>{
  const clock=new FakeClock(),store=makeStore({clock}),id=store.createNote();await store.lockNote(id,'5555',{credentialType:'pin'});await store.unlockNote(id,'5555');
  clock.time=121_000;await store.unlockNote(id,'5555');assert.equal(store.isLocked(id),false);
  clock.advance(119_999);assert.equal(store.isLocked(id),false);clock.advance(1);assert.equal(store.isLocked(id),true);store.dispose();
});

test('system clock rollback cannot extend access and sleep still expires a session',async t=>{
  let wall=1_700_000_000_000,steady=0;
  t.mock.method(Date,'now',()=>wall);t.mock.method(performance,'now',()=>steady);
  const store=makeStore(),id=store.createNote();await store.lockNote(id,'6666',{credentialType:'pin'});await store.unlockNote(id,'6666');
  wall-=3_600_000;steady+=120_000;store.lockExpiredNotes();assert.equal(store.isLocked(id),true);
  await store.unlockNote(id,'6666');wall+=120_000;store.lockExpiredNotes();assert.equal(store.isLocked(id),true);store.dispose();
});

test('Apple authentication metadata survives browser import, edits, backup, reload, and merge',async()=>{
  const archive=structuredClone(nativeFixture),credentialID=newID(),id=archive.notes[0].id;
  Object.assign(archive.notes[0].encryptedContent,{credentialKind:'apple',credentialID:credentialID.toLowerCase()});
  const storage=new MemoryStorage(),store=makeStore({storage});await store.importArchive(archive);
  await store.updateNote(id,n=>{n.isPinned=true;n.color='rose';});await store.flush();
  const exported=JSON.parse(store.exportArchive()).notes[0];
  assert.equal(exported.encryptedContent.credentialKind,'apple');assert.equal(exported.encryptedContent.credentialID,credentialID);
  assert.equal(exported.encryptedContent.sealedData,archive.notes[0].encryptedContent.sealedData);
  assert.deepEqual(exported.content,emptyContent());assert.deepEqual(exported.history,[]);
  const reloaded=makeStore({storage});assert.equal(reloaded.notes[0].encryptedContent.credentialID,credentialID);assert.equal(reloaded.isLocked(id),true);
  const other=makeStore();await other.mergeArchive(store.exportArchive());assert.deepEqual(other.notes[0].encryptedContent,exported.encryptedContent);
  store.dispose();reloaded.dispose();other.dispose();
});

test('Apple-authenticated notes cannot be unlocked or unprotected with browser password entry',async()=>{
  const archive=structuredClone(nativeFixture),id=archive.notes[0].id;
  Object.assign(archive.notes[0].encryptedContent,{credentialKind:'apple',credentialID:newID()});
  const store=makeStore();await store.importArchive(archive);
  // Even the fixture's actual decryption credential must not be offered as a web fallback.
  await assert.rejects(()=>store.unlockNote(id,'native-password-123'),/Apple device/);
  await assert.rejects(()=>store.removePassword(id,'native-password-123'),/Apple device/);
  assert.equal(store.isLocked(id),true);assert.equal(store.notes[0].encryptedContent.credentialKind,'apple');
  assert.deepEqual(store.notes[0].content,emptyContent());store.dispose();
});

test('invalid and incomplete Apple credential metadata is rejected without reclassifying it',()=>{
  for(const metadata of [{credentialKind:'apple'},{credentialID:newID()},{credentialKind:'apple',credentialID:'broken'},
    {credentialKind:'other',credentialID:newID()}]){
    const archive=structuredClone(nativeFixture);Object.assign(archive.notes[0].encryptedContent,metadata);
    assert.throws(()=>validateArchive(archive),/valid StickeyNote backup/);
  }
  const legacy=validateArchive(nativeFixture).notes[0].encryptedContent;
  assert.equal(legacy.credentialKind,undefined);assert.equal(legacy.credentialID,undefined);
});
