import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';

const source = readFileSync(new URL('./theme.js', import.meta.url), 'utf8');
function browser({saved=null, dark=false, blocked=false}={}) {
  const storage = {getItem:()=>saved, setItem:(_,value)=>{if(blocked)throw new Error('Storage unavailable');saved=value;}};
  const window = new EventTarget(), system = new EventTarget();
  system.matches = dark;
  window.matchMedia = () => system;
  Object.defineProperty(window,'localStorage',{get(){if(blocked)throw new Error('Storage unavailable');return storage;}});
  const root = {dataset:{}}, meta = {setAttribute(_,value){this.content=value;}};
  runInNewContext(source,{window,document:{documentElement:root,querySelector:()=>meta},Event});
  return {window,root,meta,get saved(){return saved;},
    systemDark(value){system.matches=value;system.dispatchEvent(new Event('change'));},
    storageChange(value,key='stickeynote.theme',storageArea=storage){saved=value;const event=new Event('storage');Object.assign(event,{key,newValue:value,storageArea});window.dispatchEvent(event);}
  };
}

test('Auto applies device appearance on startup and follows changes',()=>{
  const app=browser({dark:true});
  assert.equal(app.window.StickeyTheme.preference,'auto');
  assert.equal(app.root.dataset.theme,'dark');
  assert.equal(app.meta.content,'#20221d');
  app.systemDark(false);
  assert.equal(app.root.dataset.theme,'light');
  assert.equal(app.meta.content,'#fafaf7');
});

test('explicit themes persist across reloads and override device changes',()=>{
  const app=browser({dark:true});
  assert.equal(app.window.StickeyTheme.setPreference('light'),true);
  assert.equal(app.saved,'light');
  app.systemDark(false);app.systemDark(true);
  assert.equal(app.root.dataset.theme,'light');
  assert.equal(browser({saved:app.saved,dark:true}).root.dataset.theme,'light');
  app.window.StickeyTheme.setPreference('dark');app.systemDark(false);
  assert.equal(app.root.dataset.theme,'dark');
  app.window.StickeyTheme.setPreference('auto');
  assert.equal(app.root.dataset.theme,'light');
  assert.equal(app.saved,'auto');
});

test('invalid preferences fall back to Auto',()=>{
  const app=browser({saved:'unknown',dark:true});
  assert.equal(app.window.StickeyTheme.preference,'auto');
  assert.equal(app.root.dataset.theme,'dark');
});

test('storage changes from another tab apply and clearing restores Auto',()=>{
  const app=browser({dark:true});
  let updates=0;app.window.addEventListener('themechange',()=>updates++);
  app.storageChange('light');assert.equal(app.root.dataset.theme,'light');
  app.storageChange('dark','another-key');assert.equal(app.root.dataset.theme,'light');
  app.storageChange('dark','stickeynote.theme',{});assert.equal(app.root.dataset.theme,'light');
  app.storageChange(null,null);assert.equal(app.root.dataset.theme,'dark');
  assert.equal(app.window.StickeyTheme.preference,'auto');assert.equal(updates,2);
});

test('unavailable storage still supports an in-memory theme',()=>{
  const app=browser({blocked:true,dark:true});
  assert.equal(app.root.dataset.theme,'dark');
  assert.equal(app.window.StickeyTheme.setPreference('light'),false);
  assert.equal(app.root.dataset.theme,'light');
});
