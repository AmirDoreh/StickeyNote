// Shared, dependency-free document model. Its version-1 JSON is also understood
// by the Swift app; all dates are milliseconds since the Unix epoch.
export const STORAGE_KEY = 'stickeynote.archive.v1';
export const COLORS = [
  ['butter','F7E999'],['lemon','F9E35B'],['gold','F5CB63'],['peach','F8D0AD'],['apricot','F7B879'],
  ['coral','F49D8F'],['rose','ECA6AA'],['blush','F6D5D7'],['pink','F0BBDC'],['mauve','D8B3C9'],
  ['lavender','D9C9F0'],['lilac','C9B4E4'],['periwinkle','BFCAEF'],['sky','C2DFF2'],['blue','A7C8EA'],
  ['teal','A8D5D2'],['mint','C8E5D0'],['sage','D1DEC1'],['green','ADD0A5'],['olive','D2D6A4'],
  ['cream','F3EDDD'],['sand','E7D7BC'],['clay','D5BBA7'],['silver','DFE3E7'],['graphite','B4BBC7']
].map(([id,hex]) => ({id,name:id[0].toUpperCase()+id.slice(1),hex}));
export const FONTS = [
  ['system','System','-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif'],
  ['rounded','Rounded','ui-rounded, "SF Pro Rounded", -apple-system, sans-serif'],
  ['serif','Serif','ui-serif, Georgia, serif'],['mono','Monospaced','ui-monospace, Menlo, monospace'],
  ['avenir','Avenir','Avenir, "Segoe UI", sans-serif'],['helvetica','Helvetica Neue','"Helvetica Neue", Helvetica, sans-serif'],
  ['georgia','Georgia','Georgia, serif'],['palatino','Palatino','Palatino, "Palatino Linotype", serif'],
  ['times','Times New Roman','"Times New Roman", Times, serif'],['courier','Courier','Courier, monospace'],
  ['menlo','Menlo','Menlo, Consolas, monospace'],['baskerville','Baskerville','Baskerville, Georgia, serif'],
  ['didot','Didot','Didot, "Times New Roman", serif'],['futura','Futura','Futura, "Century Gothic", sans-serif'],
  ['chalkboard','Chalkboard','"Chalkboard SE", "Comic Sans MS", cursive'],
  ['noteworthy','Noteworthy','Noteworthy, "Segoe Print", cursive']
].map(([id,name,family]) => ({id,name,family}));

const enc = new TextEncoder();
const dec = new TextDecoder();
const copy = value => structuredClone(value);
const same = (a,b) => JSON.stringify(a) === JSON.stringify(b);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const invalid = () => new Error('This file is not a valid StickeyNote backup.');
const validString = (value, max = 2_000_000) => typeof value === 'string' && value.length <= max;
const validDate = value => Number.isFinite(value) && Math.abs(value) <= 8_640_000_000_000_000;
const normalizeID = value => { if (!UUID.test(value)) throw invalid(); return value.toUpperCase(); };
const optionalID = value => value == null ? null : normalizeID(value);
const optionalDate = value => { if (value == null) return null; if (!validDate(value)) throw invalid(); return value; };

export function newID() {
  if (globalThis.crypto?.randomUUID) return crypto.randomUUID().toUpperCase();
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  bytes[6] = (bytes[6] & 15) | 64; bytes[8] = (bytes[8] & 63) | 128;
  const hex = Array.from(bytes, b => b.toString(16).padStart(2,'0')).join('');
  return `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20)}`.toUpperCase();
}
export function emptyContent() { return {title:'',text:'',richText:null,richHTML:null,items:[],strokes:[]}; }
export function plainText(note) {
  const content = note.content ?? note;
  return [content.title,content.text,...content.items.map(item => `${item.isCompleted ? '☑':'☐'} ${item.text}`)].filter(Boolean).join('\n');
}
export function createNote(kind = 'text', groupID = null, now = Date.now()) {
  return {id:newID(),kind,content:{...emptyContent(),items:kind === 'checklist' ? [{id:newID(),text:'',isCompleted:false}] : []},
    color:'butter',font:'system',fontSize:18,groupID,isPinned:false,createdAt:now,updatedAt:now,revisionID:newID(),protectionUpdatedAt:null,protectionRevisionID:null,deletedAt:null,history:[],encryptedContent:null};
}

function contentValue(value) {
  if (!value || !validString(value.title) || !validString(value.text) || !Array.isArray(value.items) || !Array.isArray(value.strokes)) throw invalid();
  if (value.items.length > 100_000 || value.strokes.length > 100_000) throw invalid();
  if (value.richText != null && !validString(value.richText, 20_000_000)) throw invalid();
  if (value.richHTML != null && !validString(value.richHTML)) throw invalid();
  const items = value.items.map(item => {
    if (!validString(item.text) || typeof item.isCompleted !== 'boolean') throw invalid();
    return {id:normalizeID(item.id),text:item.text,isCompleted:item.isCompleted};
  });
  const strokes = value.strokes.map(stroke => {
    if (!Array.isArray(stroke.points) || stroke.points.length > 500_000 || !/^#?[0-9a-f]{6}$/i.test(stroke.color) || !Number.isFinite(stroke.width) || stroke.width <= 0 || stroke.width > 100) throw invalid();
    return {id:normalizeID(stroke.id),color:stroke.color.replace('#',''),width:stroke.width,points:stroke.points.map(point => {
      if (!Number.isFinite(point.x) || !Number.isFinite(point.y) || point.x < 0 || point.x > 1 || point.y < 0 || point.y > 1) throw invalid();
      return {x:point.x,y:point.y};
    })};
  });
  if (new Set(items.map(x=>x.id)).size !== items.length || new Set(strokes.map(x=>x.id)).size !== strokes.length) throw invalid();
  return {title:value.title,text:value.text,richText:value.richText ?? null,richHTML:value.richHTML ?? null,items,strokes};
}
function historyValue(values) {
  if (!Array.isArray(values) || values.length > 1000) throw invalid();
  return values.slice(-50).map(value => {
    if (!validDate(value.date)) throw invalid();
    return {id:normalizeID(value.id),date:value.date,content:contentValue(value.content)};
  });
}
function payloadValue(value) {
  if (value == null) return null;
  if (!Number.isInteger(value.iterations) || value.iterations < 100_000 || value.iterations > 2_000_000 || typeof value.salt !== 'string' || typeof value.sealedData !== 'string') throw invalid();
  if (fromBase64(value.salt).length !== 16 || fromBase64(value.sealedData).length < 28) throw invalid();
  return {salt:value.salt,iterations:value.iterations,sealedData:value.sealedData};
}
function noteValue(value) {
  if (!value || !['text','checklist'].includes(value.kind) || !COLORS.some(x=>x.id === value.color) || !FONTS.some(x=>x.id === value.font) || !Number.isFinite(value.fontSize) || value.fontSize < 8 || value.fontSize > 96 || typeof value.isPinned !== 'boolean' || !validDate(value.createdAt) || !validDate(value.updatedAt)) throw invalid();
  const encryptedContent = payloadValue(value.encryptedContent);
  // Discard any cleartext accidentally supplied alongside an encrypted envelope.
  return {id:normalizeID(value.id),kind:value.kind,content:encryptedContent ? emptyContent() : contentValue(value.content),color:value.color,font:value.font,fontSize:value.fontSize,
    groupID:optionalID(value.groupID),isPinned:value.isPinned,createdAt:value.createdAt,updatedAt:value.updatedAt,revisionID:optionalID(value.revisionID),
    protectionUpdatedAt:optionalDate(value.protectionUpdatedAt),protectionRevisionID:optionalID(value.protectionRevisionID),deletedAt:optionalDate(value.deletedAt),
    history:encryptedContent ? [] : historyValue(value.history),encryptedContent};
}
export function validateArchive(source) {
  let value;
  try {
    if (typeof source === 'string') { if (source.length > 100_000_000) throw invalid(); value = JSON.parse(source); }
    else value = source;
    if (!value || value.version !== 1) throw new Error('This backup needs a different version of StickeyNote.');
    if (!Array.isArray(value.notes) || !Array.isArray(value.groups) || value.notes.length > 100_000 || value.groups.length > 10_000 || !validDate(value.modifiedAt)) throw invalid();
    const notes = value.notes.map(noteValue);
    const groups = value.groups.map(group => {
      if (!validString(group.name,1000) || !validString(group.symbol,100) || !validDate(group.updatedAt)) throw invalid();
      return {id:normalizeID(group.id),name:group.name,symbol:group.symbol,updatedAt:group.updatedAt,revisionID:optionalID(group.revisionID),deletedAt:optionalDate(group.deletedAt)};
    });
    if (new Set(notes.map(x=>x.id)).size !== notes.length || new Set(groups.map(x=>x.id)).size !== groups.length) throw invalid();
    return {version:1,notes,groups,modifiedAt:value.modifiedAt};
  } catch (error) { if (error instanceof SyntaxError || error instanceof TypeError || error instanceof DOMException) throw invalid(); throw error; }
}

function toBase64(bytes) {
  let binary = '';
  for (let i=0;i<bytes.length;i+=32768) binary += String.fromCharCode(...bytes.subarray(i,i+32768));
  return btoa(binary);
}
function fromBase64(value) {
  if (!validString(value,100_000_000) || !/^[A-Za-z0-9+/]*={0,2}$/.test(value) || value.length % 4 !== 0) throw invalid();
  const binary = atob(value);
  return Uint8Array.from(binary, char => char.charCodeAt(0));
}
async function deriveKey(password,salt,iterations) {
  if (!globalThis.crypto?.subtle) throw new Error('Password protection needs HTTPS or localhost in this browser.');
  const material = await crypto.subtle.importKey('raw',enc.encode(password),'PBKDF2',false,['deriveKey']);
  return crypto.subtle.deriveKey({name:'PBKDF2',salt,iterations,hash:'SHA-256'},material,{name:'AES-GCM',length:256},false,['encrypt','decrypt']);
}
async function seal(note,key,salt,iterations) {
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const plaintext = enc.encode(JSON.stringify({content:note.content,history:note.history}));
  try {
    const encrypted = new Uint8Array(await crypto.subtle.encrypt({name:'AES-GCM',iv:nonce,additionalData:enc.encode(note.id.toUpperCase()),tagLength:128},key,plaintext));
    const combined = new Uint8Array(nonce.length+encrypted.length); combined.set(nonce); combined.set(encrypted,nonce.length);
    return {salt:toBase64(salt),iterations,sealedData:toBase64(combined)};
  } finally { plaintext.fill(0); }
}
async function openEnvelope(note,key) {
  const bytes = fromBase64(note.encryptedContent.sealedData);
  let clear;
  try {
    clear = new Uint8Array(await crypto.subtle.decrypt({name:'AES-GCM',iv:bytes.subarray(0,12),additionalData:enc.encode(note.id.toUpperCase()),tagLength:128},key,bytes.subarray(12)));
    const value = JSON.parse(dec.decode(clear));
    return {content:contentValue(value.content),history:historyValue(value.history)};
  } catch { throw new Error('That password didn’t unlock this note.'); }
  finally { clear?.fill(0); }
}
function persisted(note) {
  const result = copy(note);
  if (result.encryptedContent) { result.content = emptyContent(); result.history = []; }
  return result;
}
function localWins(local,incoming) {
  return local && (local.updatedAt>incoming.updatedAt || (local.updatedAt===incoming.updatedAt && (local.revisionID??'')>=(incoming.revisionID??'')));
}
export function protectionVersionDate(note) { return note.protectionUpdatedAt ?? (note.encryptedContent ? note.updatedAt : null); }
export function noteWinsMerge(candidate,other) {
  if(!other)return true;
  const mineDate=protectionVersionDate(candidate),theirDate=protectionVersionDate(other);
  const mine=mineDate===null?null:Math.round(mineDate),theirs=theirDate===null?null:Math.round(theirDate);
  if(mine!==theirs)return mine!==null && (theirs===null || mine>theirs);
  const mineRevision=candidate.protectionRevisionID??'',theirRevision=other.protectionRevisionID??'';
  if(mineRevision!==theirRevision)return mineRevision>theirRevision;
  if(Boolean(candidate.encryptedContent)!==Boolean(other.encryptedContent))return Boolean(candidate.encryptedContent);
  return localWins(candidate,other);
}

export class NoteStore extends EventTarget {
  constructor(options = {}) {
    super();
    this.notes = []; this.groups = []; this.saveStatus = 'Saved on this device'; this.errorMessage = null;
    this._deletedGroups = []; this._keys = new Map(); this._generations = new Map(); this._revisions = new Map();
    this._pending = new Set(); this._modifiedAt = Date.now(); this._revision = 0; this._savedRevision = 0;
    this._readOnly = false; this._replaceBackup = false; this._timer = null; this._key = options.key ?? STORAGE_KEY;
    try { this._storage = options.storage ?? globalThis.localStorage; }
    catch { this._storage = null; this.errorMessage = 'Browser storage is unavailable. Export a backup before closing.'; }
    let raw = null;
    try { raw = this._storage?.getItem(this._key); }
    catch { this.errorMessage = 'Browser storage could not be read. Export a backup before closing.'; this._readOnly = true; }
    if (raw) {
      try { this._load(validateArchive(raw)); }
      catch {
        let recovered = false;
        try { const backup = this._storage?.getItem(this._key+'.backup'); if (backup) { this._load(validateArchive(backup)); recovered = true; } } catch {}
        if (recovered) this.errorMessage = 'Your last saved backup was recovered. The damaged copy is preserved until you save.';
        else { this._readOnly = true; this.errorMessage = 'Your saved notes could not be opened. They have not been overwritten. Import a valid backup to recover.'; this.saveStatus = 'Recovery needed'; }
      }
    } else if (options.seed !== false && !this._readOnly) { this._load(sampleArchive()); this._changed(); }
    this._storageListener = event => {
      if (event.key === this._key && event.newValue) this.mergeArchive(event.newValue).catch(error=>this._fail(error));
    };
    if (options.listen !== false) globalThis.addEventListener?.('storage',this._storageListener);
  }
  _load(archive) { this.notes = archive.notes; this.groups = archive.groups.filter(x=>!x.deletedAt); this._deletedGroups = archive.groups.filter(x=>x.deletedAt); this._modifiedAt = archive.modifiedAt; }
  _note(id) { return this.notes.find(note=>note.id === id); }
  _generation(id) { return this._generations.get(id) ?? 0; }
  _invalidate(id) { this._generations.set(id,this._generation(id)+1); this._keys.delete(id); }
  _replace(note) { const index=this.notes.findIndex(x=>x.id === note.id); if(index>=0) this.notes[index]=note; }
  _emit(type='change') { this.dispatchEvent(new Event(type)); }
  _changed() {
    this._revision++; this._modifiedAt = Date.now(); this._emit();
    if (this._readOnly) return;
    this.saveStatus = 'Saving…'; this._emit('status'); clearTimeout(this._timer);
    this._timer = setTimeout(()=>this.flush().catch(error=>this._fail(error)),300);
    this._timer?.unref?.();
  }
  _fail(error) { this.errorMessage = error.message ?? String(error); this.saveStatus = 'Couldn’t save'; this._emit('status'); }
  _track(task) { this._pending.add(task); task.finally(()=>this._pending.delete(task)).catch(()=>{}); return task; }
  createNote(kind='text',groupID=null) {
    if (!['text','checklist'].includes(kind)) throw new Error('Unknown note type.');
    const note = createNote(kind,groupID); this.notes.unshift(note); this._changed(); return note.id;
  }
  async updateNote(id,mutator) {
    const old = this._note(id); if (!old) return;
    const next = copy(old); mutator(next);
    next.id = old.id; next.createdAt = old.createdAt; next.encryptedContent = old.encryptedContent;
    next.protectionUpdatedAt=old.protectionUpdatedAt??null;next.protectionRevisionID=old.protectionRevisionID??null;
    next.fontSize = Math.min(96,Math.max(8,Number.isFinite(next.fontSize) ? next.fontSize : 18));
    if (same(next,old)) return;
    if (!same(next.content,old.content)) {
      if (this.isLocked(id)) throw new Error('Unlock the note before editing it.');
      if (same(next.history,old.history) && !same(old.content,emptyContent()) && (!old.history.length || Date.now()-old.history.at(-1).date >= 30_000)) next.history.push({id:newID(),date:Date.now(),content:copy(old.content)});
      next.history = next.history.slice(-50);
    }
    next.updatedAt = Math.max(Date.now(),old.updatedAt+1);
    next.revisionID = newID();
    this._replace(next); this._changed();
    if (next.encryptedContent && this._keys.has(id)) await this._encryptCurrent(id);
  }
  async _encryptCurrent(id) {
    const note=this._note(id), key=this._keys.get(id); if(!note?.encryptedContent || !key) return;
    const snapshot=copy(note), generation=this._generation(id), revision=(this._revisions.get(id)??0)+1;
    this._revisions.set(id,revision);
    const task=seal(snapshot,key,fromBase64(note.encryptedContent.salt),note.encryptedContent.iterations).then(payload=>{
      const current=this._note(id);
      // Locking clears visible plaintext immediately; this last ciphertext still saves.
      if(current && this._revisions.get(id)===revision && (this._generation(id)===generation || this.isLocked(id))) {
        current.encryptedContent=payload;
      }
    }).catch(error=>{this._fail(error); throw error;});
    await this._track(task);
  }
  async deleteNote(id) { await this.updateNote(id,note=>note.deletedAt=Date.now()); }
  async restoreNote(id) { await this.updateNote(id,note=>note.deletedAt=null); }
  async duplicateNote(id) {
    const source=this._note(id); if(!source) return null;
    if(this.isLocked(id)) throw new Error('Unlock the note before duplicating it.');
    const note=copy(source); note.id=newID(); note.createdAt=Date.now(); note.updatedAt=note.createdAt; note.revisionID=newID();note.deletedAt=null; note.history=[]; note.isPinned=false;
    note.content.title=(note.content.title.trim() || (note.kind==='checklist'?'Untitled checklist':'Untitled note'))+' copy';
    if(note.encryptedContent) {
      const key=this._keys.get(id),generation=this._generation(id);
      note.encryptedContent=await seal(note,key,fromBase64(note.encryptedContent.salt),note.encryptedContent.iterations);
      if(this._generation(id)===generation)this._keys.set(note.id,key);
      else{note.content=emptyContent();note.history=[];}
    }
    this.notes.unshift(note); this._changed(); return note.id;
  }
  addGroup(name,symbol='folder') {
    const group={id:newID(),name:name.trim()||'New group',symbol,updatedAt:Date.now(),revisionID:newID(),deletedAt:null};
    this.groups.push(group); this._changed(); return group.id;
  }
  renameGroup(id,name) { const group=this.groups.find(x=>x.id===id); if(group && name.trim()){group.name=name.trim();group.updatedAt=Math.max(Date.now(),group.updatedAt+1);group.revisionID=newID();this._changed();} }
  deleteGroup(id) {
    const group=this.groups.find(x=>x.id===id); if(!group)return;
    this._deletedGroups.push({...group,deletedAt:Date.now(),updatedAt:Math.max(Date.now(),group.updatedAt+1),revisionID:newID()});this.groups=this.groups.filter(x=>x.id!==id);
    for(const note of this.notes) if(note.groupID===id){note.groupID=null;note.updatedAt=Math.max(Date.now(),note.updatedAt+1);note.revisionID=newID();}
    this._changed();
  }
  async restoreSnapshot(noteID,snapshotID) {
    const note=this._note(noteID); if(!note || this.isLocked(noteID))throw new Error('Unlock the note before restoring history.');
    const snapshot=note.history.find(x=>x.id===snapshotID);if(!snapshot)return;
    const current=copy(note.content);await this.updateNote(noteID,next=>{next.content=copy(snapshot.content);next.history.push({id:newID(),date:Date.now(),content:current});});
  }
  isLocked(id) { return Boolean(this._note(id)?.encryptedContent && !this._keys.has(id)); }
  async lockNote(id,password) {
    if([...password].length<8)throw new Error('Use a password with at least 8 characters.');
    const note=this._note(id);if(!note)return;
    if(note.encryptedContent)throw new Error('This note already has a password.');
    const generation=this._generation(id),salt=crypto.getRandomValues(new Uint8Array(16));
    const key=await deriveKey(password,salt,600_000);
    const current=this._note(id);if(!current || this._generation(id)!==generation)return;
    const snapshot=copy(current); const payload=await seal(snapshot,key,salt,600_000);
    if(this._note(id)!==current)throw new Error('The note changed while protecting it. Please try again.');
    current.protectionUpdatedAt=Math.max(Date.now(),(protectionVersionDate(current)??0)+1);current.protectionRevisionID=newID();
    current.encryptedContent=payload;current.content=emptyContent();current.history=[];current.updatedAt=Math.max(Date.now(),current.updatedAt+1);current.revisionID=newID();
    this._invalidate(id);this._replaceBackup=true;this._changed();await this.flush();
  }
  async unlockNote(id,password) {
    await this._settle();
    const note=this._note(id);if(!note?.encryptedContent)return;
    const generation=this._generation(id), payload=note.encryptedContent;
    const key=await deriveKey(password,fromBase64(payload.salt),payload.iterations);
    const body=await openEnvelope(note,key);
    if(this._generation(id)!==generation || this._note(id)?.encryptedContent!==payload)throw new Error('This note changed. Please unlock it again.');
    const current=this._note(id);
    this._keys.set(id,key);current.content=body.content;current.history=body.history;this._emit();
  }
  relockNote(id) {
    const note=this._note(id);this._invalidate(id);
    if(note?.encryptedContent){note.content=emptyContent();note.history=[];this._emit();}
  }
  relockAll() { for(const id of this.notes.filter(x=>x.encryptedContent).map(x=>x.id))this.relockNote(id); }
  async removePassword(id,password) {
    await this.unlockNote(id,password);const note=this._note(id);if(!note)return;
    if(!note.encryptedContent)return;
    note.protectionUpdatedAt=Math.max(Date.now(),(protectionVersionDate(note)??note.updatedAt)+1);note.protectionRevisionID=newID();
    note.encryptedContent=null;note.updatedAt=Math.max(Date.now(),note.updatedAt+1);note.revisionID=newID();this._invalidate(id);this._changed();await this.flush();
  }
  exportArchive() { return JSON.stringify({version:1,notes:this.notes.map(persisted),groups:[...this.groups,...this._deletedGroups],modifiedAt:this._modifiedAt}); }
  async importArchive(source) {
    const archive=validateArchive(source);await this.mergeArchive(archive);
    if(this._readOnly){this._readOnly=false;this._replaceBackup=true;this._changed();}
    await this.flush();
  }
  async mergeArchive(source) {
    const archive=validateArchive(source);await this._settle();
    const notes=new Map(this.notes.map(x=>[x.id,x]));let changed=false;
    for(const incoming of archive.notes){const local=notes.get(incoming.id);if(local && noteWinsMerge(local,incoming))continue;notes.set(incoming.id,incoming);this._invalidate(incoming.id);this._revisions.set(incoming.id,(this._revisions.get(incoming.id)??0)+1);if(incoming.encryptedContent)this._replaceBackup=true;changed=true;}
    const groups=new Map([...this.groups,...this._deletedGroups].map(x=>[x.id,x]));
    for(const incoming of archive.groups){const local=groups.get(incoming.id);if(localWins(local,incoming))continue;groups.set(incoming.id,incoming);changed=true;}
    if(changed){this.notes=[...notes.values()].sort((a,b)=>b.createdAt-a.createdAt);this.groups=[...groups.values()].filter(x=>!x.deletedAt);this._deletedGroups=[...groups.values()].filter(x=>x.deletedAt);this._changed();this._emit('merge');}
  }
  async _settle() { while(this._pending.size)await Promise.all([...this._pending]); }
  async flush() {
    clearTimeout(this._timer);this._timer=null;await this._settle();
    if(this._readOnly || this._savedRevision===this._revision)return;
    if(!this._storage){const error=new Error('Browser storage is unavailable. Export a backup before closing.');this._fail(error);throw error;}
    const revision=this._revision,raw=this.exportArchive();
    try {
      const previous=this._storage.getItem(this._key);
      if(this._replaceBackup)this._storage.removeItem(this._key+'.backup');
      else if(previous){try{validateArchive(previous);this._storage.setItem(this._key+'.backup',previous);}catch(error){if(error.name==='QuotaExceededError')throw error;}}
      this._storage.setItem(this._key,raw);
      if(this._replaceBackup || !this._storage.getItem(this._key+'.backup'))this._storage.setItem(this._key+'.backup',raw);
      this._savedRevision=revision;this._replaceBackup=false;this.saveStatus='Saved on this device';this.errorMessage=null;this._emit('status');
    } catch(error){this._fail(new Error(error.name==='QuotaExceededError'?'Browser storage is full. Export a backup, then remove unused data.':`Your changes could not be saved: ${error.message}`));throw error;}
  }
  dispose() { clearTimeout(this._timer);globalThis.removeEventListener?.('storage',this._storageListener);this.relockAll(); }
}

function sampleArchive() {
  const now=Date.now();
  const groups=[{id:newID(),name:'Personal',symbol:'sun.max',updatedAt:now,revisionID:newID(),deletedAt:null},{id:newID(),name:'Work',symbol:'briefcase',updatedAt:now,revisionID:newID(),deletedAt:null},{id:newID(),name:'Ideas',symbol:'lightbulb',updatedAt:now,revisionID:newID(),deletedAt:null}];
  const make=(title,text,color,group,index)=>({...createNote('text',group?.id??null,now-index*100_000),content:{...emptyContent(),title,text},color,updatedAt:now-index*60_000});
  const checklist=(title,rows,color,index)=>({...make(title,'',color,groups[0],index),kind:'checklist',content:{...emptyContent(),title,items:rows.map((text,i)=>({id:newID(),text,isCompleted:index===1&&i===0}))}});
  const notes=[make('A little space for big ideas.','A thought. A plan. Something you don’t want to forget.\n\nMake a note, pick a color, and make room for what matters. Everything saves as you go.','butter',groups[0],0),
    checklist('A good kind of day',['Make a fresh cup of coffee','Make space for a little focus','Take a walk outside','Write down one good idea'],'mint',1),
    make('Less, but better.','For the next thing we make:\n\n• Start with what people need.\n• Keep the useful parts simple.\n• Leave a little room for delight.\n\nClarity is a feature.','lavender',groups[1],2),
    checklist('Weekend, loosely planned',['Visit the farmers’ market','Find a new book','Cook something slow','Leave the afternoon open'],'peach',3),
    make('What if…','The best ideas rarely arrive at your desk.\n\nKeep this little corner for the ones that find you along the way.','sky',groups[2],4),
    make('Small shortcuts, big help','⌘ N  A fresh note\n⌘ T  A new checklist\n⌘ F  Find a thought\n\nUse the palette to change a color. Pin your favorites. Browse history to bring an earlier idea back.','blush',null,5)];
  notes[0].isPinned=true;
  notes[4].content.strokes=[{id:newID(),points:[{x:.12,y:.78},{x:.24,y:.75},{x:.38,y:.79},{x:.52,y:.76},{x:.68,y:.78}],color:'486960',width:2.5}];
  return {version:1,notes,groups,modifiedAt:now};
}
