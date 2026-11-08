import { NoteStore, COLORS, FONTS } from './core.js';
import { createCloudSync } from './cloud.js';

const paths = {
  plus:'M12 5v14M5 12h14', note:'M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h9l5-5V5a2 2 0 0 0-2-2h-4Zm1 18v-5h5M8 8h8M8 12h6',
  grid:'M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h6v6h-6z', list:'M8 6h12M8 12h12M8 18h12M4 6h.01M4 12h.01M4 18h.01',
  check:'m5 12 4 4L19 6', checklist:'M9 5h12M9 12h12M9 19h12m-19-14 1 1 2-2m-3 8 1 1 2-2m-3 8 1 1 2-2',
  search:'m21 21-4.4-4.4M19 10.5a8.5 8.5 0 1 1-17 0 8.5 8.5 0 0 1 17 0Z', pin:'m16 3 5 5-4 2-3 6-6-6 6-3 2-4ZM8 10l-3 3 6 6 3-3M8 16l-5 5',
  trash:'M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7M14 10v7', folder:'M3 7V5a2 2 0 0 1 2-2h4l2 3h8a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7Z',
  cloud:'M7 18a5 5 0 1 1 .5-9.9A6 6 0 0 1 19 10a4 4 0 0 1 0 8H7Z', chevron:'m9 5 7 7-7 7', down:'m6 9 6 6 6-6',
  settings:'M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8ZM9 3l-.7 2.3-2 .9-2.2-.5-2 3.5 1.5 1.8v2l-1.5 1.8 2 3.5 2.2-.5 2 .9L9 21h6l.7-2.3 2-.9 2.2.5 2-3.5-1.5-1.8v-2l1.5-1.8-2-3.5-2.2.5-2-.9L15 3H9Z',
  spark:'m12 2 2.4 7.6L22 12l-7.6 2.4L12 22l-2.4-7.6L2 12l7.6-2.4L12 2Z', menu:'M4 6h16M4 12h16M4 18h16', sort:'M8 4v16m-4-4 4 4 4-4M14 4h6M14 9h4M14 14h2',
  more:'M5 12h.01M12 12h.01M19 12h.01', close:'m6 6 12 12M6 18 18 6', palette:'M12 3a9 9 0 1 0 0 18h1a2 2 0 0 0 1.6-3.2 1.5 1.5 0 0 1 1.2-2.4H18A3 3 0 0 0 21 12a9 9 0 0 0-9-9ZM7 10h.01M10 6h.01M15 6h.01M18 10h.01',
  draw:'m4 17 1-5L16 1l6 6-11 11-5 1-2 2M14 3l6 6M7 13l4 4M4 21h17', history:'M3 11a9 9 0 1 1 2 6M3 4v7h7M12 7v5l3 2', lock:'M6 10h12v11H6zM8 10V7a4 4 0 0 1 8 0v3M12 14v3',
  unlock:'M6 10h12v11H6zM8 10V7a4 4 0 0 1 7.5-2M12 14v3', qr:'M3 3h6v6H3zM15 3h6v6h-6zM3 15h6v6H3zM15 15h2v2h-2zM21 15v3h-3v3M12 3v4M3 12h5M12 12h4M12 18v3M21 12h-2',
  copy:'M9 9h12v12H9zM5 15H3V3h12v2', share:'M12 16V3m-4 4 4-4 4 4M5 12v9h14v-9', restore:'M3 10a9 9 0 1 1 1 8M3 3v7h7M12 8v4l3 2', download:'M12 3v12m-5-5 5 5 5-5M4 16v5h16v-5',
  upload:'M12 16V3m-5 5 5-5 5 5M4 16v5h16v-5', bold:'M6 3h8a4 4 0 0 1 0 8H6V3Zm0 8h9a5 5 0 0 1 0 10H6V11Z', italic:'M10 3h10M4 21h10M16 3 8 21', underline:'M6 3v8a6 6 0 0 0 12 0V3M4 21h16',
  strike:'M18 5c-3-3-10-3-11 1-.5 2 1 3 3 4M6 18c3 3 10 3 11-1 .5-2-1-3-3-4M3 12h18', numbered:'M10 5h11M10 12h11M10 19h11M4 3h1v4M3 11c2-3 5 0 0 3h3M3 18h3l-2 2h2',
  undo:'M9 4 3 10l6 6M3 10h11a7 7 0 0 1 7 7', redo:'m15 4 6 6-6 6M21 10H10a7 7 0 0 0-7 7', eraser:'m16 3 5 5-11 13H6l-4-4L16 3ZM9 10l6 6M10 21h11',
  up:'m6 15 6-6 6 6', scan:'M8 3H3v5M16 3h5v5M21 16v5h-5M8 21H3v-5M7 7h10v10H7z', camera:'M14 4h-4L8 7H3v14h18V7h-5l-2-3ZM16 13a4 4 0 1 1-8 0 4 4 0 0 1 8 0Z',
  heart:'M20 4c-3-2-6 0-8 2-2-2-5-4-8-2-4 3-1 8 8 16 9-8 12-13 8-16Z', sun:'M16 12a4 4 0 1 1-8 0 4 4 0 0 1 8 0ZM12 2v2M12 20v2M2 12h2M20 12h2M5 5l1 1M18 18l1 1M5 19l1-1M18 6l1-1',
  arrow:'M5 12h14m-5-5 5 5-5 5', external:'M14 3h7v7m0-7L10 14M10 3H3v18h18v-7', link:'m9 15 6-6M8 16l-2 2a4 4 0 0 1-6-6l4-4a4 4 0 0 1 6 0M16 8l2-2a4 4 0 0 1 6 6l-4 4a4 4 0 0 1-6 0'
};
const icon = (name, size = 18) => `<svg width="${size}" height="${size}" viewBox="0 0 24 24" aria-hidden="true"><path d="${paths[name] || paths.note}"/></svg>`;
const $ = (selector, root = document) => root.querySelector(selector);
const escape = value => String(value ?? '').replace(/[&<>"']/g, ch => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));
const attr = escape;
const store = new NoteStore();
let filter = 'all', query = '', sort = 'updated', view = 'grid', editorID = null, drawingVisible = false, visibleLimit = 60;
let toastTimer, renderFrame, cloudMessage = 'Available with setup', modalCleanup = null;
let drawingColor = '30362B', drawingWidth = 3, erasing = false, drawingUndo = [];
const editor = $('#editor-dialog'), utility = $('#utility-dialog');
const cloud = createCloudSync({getArchive: async () => { await store.flush(); return store.exportArchive(); }, mergeArchive: value => store.mergeArchive(typeof value === 'string' ? value : JSON.stringify(value)), onStatus(message) { cloudMessage = message; renderSidebar(); const label = $('#cloud-status'); if (label) label.textContent = message; }});
const noteByID = id => store.notes.find(note => note.id === id);
const currentNote = () => noteByID(editorID);
const colorFor = note => COLORS.find(color => color.id === note.color) || COLORS[0];
const fontFor = note => FONTS.find(font => font.id === note.font) || FONTS[0];
const plainText = note => [note.content.title, note.content.text, ...(note.content.items || []).map(item => `${item.isCompleted ? '☑' : '☐'} ${item.text}`)].filter(Boolean).join('\n');
const noteTitle = note => note.content.title?.trim() || (store.isLocked(note.id) ? 'Locked note' : note.kind === 'checklist' ? 'Untitled checklist' : 'Untitled note');
const date = value => new Date(value).toLocaleDateString(undefined, {month: 'short', day: 'numeric'});
const timeAgo = value => { const minutes = Math.max(0, (Date.now() - new Date(value).getTime()) / 60000); return minutes < 1 ? 'Just now' : minutes < 60 ? `${Math.floor(minutes)}m ago` : minutes < 1440 ? `${Math.floor(minutes / 60)}h ago` : date(value); };

function toast(message) { clearTimeout(toastTimer); $('#toast').textContent = message; $('#toast').classList.add('visible'); toastTimer = setTimeout(() => $('#toast').classList.remove('visible'), 3600); }
function report(error) { toast(error?.message || String(error)); }
function scheduleRender() { if (editor.open) { renderStatus(); return; } if (renderFrame) return; renderFrame = requestAnimationFrame(() => { renderFrame = 0; renderSidebar(); renderBoard(); renderStatus(); }); }
store.addEventListener('change', () => { if (editor.open && editorID && store.isLocked(editorID) && !$('.locked-editor',editor)) { if(utility.open)utility.close();utility.innerHTML='';renderEditor(); } scheduleRender(); cloud.schedule(); });
store.addEventListener('merge', () => { if(editor.open)renderEditor(); });
store.addEventListener('status', renderStatus);
function renderStatus() { $('#save-indicator').innerHTML = `<span></span>${escape(store.saveStatus || 'Saved on this device')}`; }

function renderSidebar() {
  const active = store.notes.filter(note => !note.deletedAt);
  const nav = (key, label, glyph, count) => `<button class="nav-item ${filter === key ? 'active' : ''}" data-action="filter" data-filter="${attr(key)}">${icon(glyph,17)}<span>${label}</span><span class="count">${count}</span></button>`;
  $('#sidebar').innerHTML = `<div class="brand"><img src="./icon.svg" alt=""><span>StickeyNote<span class="brand-dot">.</span></span></div><div class="sidebar-label">Your space</div>
    ${nav('all','All notes','grid',active.length)}${nav('pinned','Pinned notes','pin',active.filter(note => note.isPinned).length)}${nav('checklists','Checklists','checklist',active.filter(note => note.kind === 'checklist').length)}
    <div class="nav-divider"></div><div class="group-heading"><div class="sidebar-label">Groups</div><button class="small-plus" data-action="add-group" aria-label="Add group">${icon('plus',14)}</button></div>
    ${store.groups.filter(group => !group.deletedAt).map((group,index) => `<div class="nav-item group-item ${filter === group.id ? 'active' : ''}" data-action="filter" data-filter="${attr(group.id)}" data-group="${attr(group.id)}" role="button" tabindex="0"><span class="group-dot" style="background:${['#a9bc7a','#b7a4ce','#d8b48a','#8ab7bb','#d4a2ab'][index%5]}"></span><span>${escape(group.name)}</span><span class="count">${active.filter(note => note.groupID === group.id).length}</span><button class="group-menu" data-action="group-menu" data-id="${attr(group.id)}" aria-label="Edit ${attr(group.name)} group">${icon('more',15)}</button></div>`).join('')}
    <button class="nav-item" data-action="add-group" style="color:#a2a991;font-size:11px">${icon('plus',15)}<span>New group</span></button><div class="nav-divider"></div>${nav('trash','Trash','trash',store.notes.filter(note => note.deletedAt).length)}
    <div class="sidebar-spacer"></div><div class="sidebar-tip"><div class="tip-icon">${icon('spark',21)}</div><strong>Catch a thought.</strong>Press <kbd>⌘ N</kbd> for a fresh note.<br>A little idea can go a long way.</div>
    <button class="sync-button" data-action="settings"><span class="sync-icon">${icon('cloud',18)}</span><span><strong>iCloud sync</strong><small>${escape(cloudMessage)}</small></span><span class="arrow">${icon('chevron',13)}</span></button>`;
}
function filteredNotes() {
  const result = store.notes.filter(note => {
    if (filter === 'trash' ? !note.deletedAt : note.deletedAt) return false;
    if (filter === 'pinned' && !note.isPinned || filter === 'checklists' && note.kind !== 'checklist') return false;
    if (!['all','pinned','checklists','trash'].includes(filter) && note.groupID !== filter) return false;
    if (query && (store.isLocked(note.id) || !plainText(note).toLowerCase().includes(query.toLowerCase()))) return false;
    return true;
  });
  return result.sort((a,b) => {
    if (filter !== 'trash' && a.isPinned !== b.isPinned) return a.isPinned ? -1 : 1;
    return sort === 'title' ? noteTitle(a).localeCompare(noteTitle(b)) : sort === 'color' ? a.color.localeCompare(b.color) : new Date(b[sort === 'created' ? 'createdAt' : 'updatedAt']) - new Date(a[sort === 'created' ? 'createdAt' : 'updatedAt']);
  });
}
function renderBoard() {
  const label = ({all:'All notes',pinned:'Pinned notes',checklists:'Checklists',trash:'Recently deleted'})[filter] || store.groups.find(group => group.id === filter)?.name || 'All notes';
  $('#page-title').innerHTML = `${escape(label)}<span class="title-dot">.</span>`;
  $('#breadcrumb-current').textContent = label;
  $('#page-subtitle').textContent = ({all:'A little space for everything on your mind.',pinned:'Keep the important things close.',checklists:'One small step at a time.',trash:'A second chance for a thought worth keeping.'})[filter] || 'A place for thoughts that belong together.';
  const notes = filteredNotes();
  $('#notes-board').className = `notes-board ${view === 'list' ? 'list' : ''}`;
  $('#active-filters').innerHTML = query ? `<span class="filter-chip">${notes.length} result${notes.length !== 1 ? 's' : ''} for “${escape(query)}” <button data-action="clear-search" aria-label="Clear search">${icon('close',11)}</button></span>` : '';
  $('#notes-board').innerHTML = notes.slice(0, visibleLimit).map(noteCard).join('') + (notes.length > visibleLimit ? `<button class="new-note-card" data-action="show-more"><span class="new-circle">${icon('down',20)}</span><strong>More little thoughts</strong><small>${notes.length-visibleLimit} more notes</small></button>` : ((!query && filter !== 'trash') ? `<button class="new-note-card" data-action="new-note"><span class="new-circle">${icon('plus',20)}</span><strong>A fresh little thought</strong><small>Click to make a note</small></button>` : ''));
  if (!notes.length && (query || filter === 'trash')) $('#notes-board').innerHTML = `<div class="empty-state"><div class="empty-icon">${icon(query ? 'search' : 'trash',30)}</div><h2>${query ? 'No thoughts found.' : 'Nothing left behind.'}</h2><p>${query ? 'Try a different word, or give your next idea a fresh note.' : 'Deleted notes appear here. You can bring them back whenever you like.'}</p>${query ? '<button class="button" data-action="clear-search">Clear search</button>' : ''}</div>`;
  $('#note-count').textContent = `${notes.length} note${notes.length !== 1 ? 's' : ''}${filter === 'all' ? ' in your space' : ''}`;
  $('#grid-button').classList.toggle('active', view === 'grid'); $('#list-button').classList.toggle('active', view === 'list');
}
function noteCard(note) {
  const locked = store.isLocked(note.id), color = colorFor(note), group = store.groups.find(group => group.id === note.groupID);
  const items = note.content.items || [], completed = items.filter(item => item.isCompleted).length;
  let preview = locked ? `<p class="note-preview">${icon('lock',22)}<br>This thought is just for you.<br>Unlock to take a look.</p>` : note.kind === 'checklist' ? `<ul class="card-checklist">${items.slice(0,4).map(item => `<li><button class="card-checkbox ${item.isCompleted ? 'done' : ''}" data-action="toggle-check" data-id="${note.id}" data-item="${item.id}" aria-label="${item.isCompleted ? 'Uncheck' : 'Check'} ${attr(item.text)}">${item.isCompleted ? icon('check',11) : ''}</button><span class="${item.isCompleted ? 'done-text' : ''}">${escape(item.text || 'An empty thought')}</span></li>`).join('')}${items.length > 4 ? `<li class="more-items">+ ${items.length-4} more</li>` : ''}</ul>` : `<p class="note-preview">${escape(note.content.text || 'A blank page, full of possibilities.')}</p>`;
  if (!locked && note.content.strokes?.length) preview += `<svg class="note-drawing" viewBox="0 0 300 65" aria-label="A sketch">${note.content.strokes.slice(-15).map(stroke => `<polyline points="${stroke.points.map(p => `${p.x*300},${p.y*65}`).join(' ')}" fill="none" stroke="#${/^[a-f\d]{6}$/i.test(stroke.color) ? stroke.color : '333333'}" stroke-width="${Math.min(7,Math.max(1,stroke.width))}"/>`).join('')}</svg>`;
  return `<article class="note-card" style="background:#${color.hex.replace('#','')}" role="button" tabindex="0" draggable="true" data-note="${note.id}" aria-label="Open ${attr(noteTitle(note))}"><div class="note-topline"><span class="note-group-tag">${escape(group?.name || (note.kind === 'checklist' ? 'Checklist' : 'Note'))}</span>${note.isPinned ? `<span class="pin-mark">${icon('pin',12)}</span>` : ''}</div><div class="note-actions"><button class="icon-button" data-action="pin" data-id="${note.id}" aria-label="${note.isPinned ? 'Unpin' : 'Pin'} note">${icon('pin',13)}</button><button class="icon-button" data-action="note-menu" data-id="${note.id}" aria-label="Note actions">${icon('more',17)}</button></div><h2 class="note-title">${escape(noteTitle(note))}</h2>${preview}<div class="note-bottom"><span class="note-bottom-left">${note.isPasswordProtected || note.encryptedContent ? icon('lock',11) : icon(note.kind === 'checklist' ? 'checklist' : 'note',11)}${escape(timeAgo(note.updatedAt))}</span>${note.kind === 'checklist' && !locked ? `<span style="display:flex;gap:6px;align-items:center">${completed}/${items.length}<span class="progress-bar"><i style="width:${items.length ? completed/items.length*100 : 0}%"></i></span></span>` : note.content.strokes?.length && !locked ? icon('draw',12) : ''}</div></article>`;
}

function sanitizeHTML(value) {
  const documentCopy = new DOMParser().parseFromString(value, 'text/html');
  const allowed = new Set(['P','DIV','BR','STRONG','B','EM','I','U','S','STRIKE','UL','OL','LI','SPAN','FONT','A','BLOCKQUOTE']);
  for (const element of [...documentCopy.body.querySelectorAll('*')]) {
    if (['SCRIPT','STYLE','IFRAME','OBJECT','EMBED','IMG','SVG','MATH'].includes(element.tagName)) { element.remove(); continue; }
    if (!allowed.has(element.tagName)) { element.replaceWith(...element.childNodes); continue; }
    const style = element.getAttribute('style') || '', href = element.getAttribute('href');
    for (const attribute of [...element.attributes]) element.removeAttribute(attribute.name);
    if (style) {
      const safe = style.split(';').filter(property => /^(font-weight|font-style|text-decoration|text-align)\s*:/i.test(property.trim()) && !/url|expression|[<>]/i.test(property)).join(';');
      if (safe) element.setAttribute('style',safe);
    }
    if (element.tagName === 'A' && href && /^https?:\/\//i.test(href)) { element.setAttribute('href',href); element.setAttribute('rel','noopener noreferrer'); element.setAttribute('target','_blank'); }
  }
  return documentCopy.body.innerHTML;
}
function openNote(id) { editorID = id; drawingVisible = false; drawingUndo = []; renderEditor(); if (!editor.open) editor.showModal(); requestAnimationFrame(() => { if ($('#drawing-preview')) drawStrokes($('#drawing-preview'), currentNote()?.content.strokes || []); }); $('#sidebar').classList.remove('open'); }
function renderEditor() {
  const note = currentNote(); if (!note) { editor.close(); return; }
  const locked = store.isLocked(note.id), color = colorFor(note);
  const tool = (action, glyph, label, extra='') => `<button class="icon-button ${extra}" data-action="${action}" data-id="${note.id}" title="${label}" aria-label="${label}">${icon(glyph,17)}</button>`;
  editor.style.background = `#${color.hex.replace('#','')}`;
  editor.innerHTML = `<div class="editor-shell"><div class="editor-topbar"><div class="editor-breadcrumb">${icon(note.kind === 'checklist' ? 'checklist' : 'note',16)}<span>${escape(store.groups.find(group => group.id === note.groupID)?.name || 'My notes')}</span></div><div class="editor-actions">${tool('pin','pin',note.isPinned ? 'Unpin note':'Pin note')}${tool('color','palette','Change color')}${tool('history','history','Version history','optional-action')}${tool('qr','qr','Show QR code','optional-action')}${tool('password',locked ? 'lock' : 'unlock',note.encryptedContent ? 'Password options' : 'Protect note')}${tool('note-menu','more','More actions')}${tool('close-editor','close','Close note')}</div></div>
    ${locked ? `<div class="locked-editor"><div class="lock-icon">${icon('lock',28)}</div><h2>A thought just for you.</h2><p>This note is encrypted with your password.<br>Unlock it to pick up where you left off.</p><button class="button primary" data-action="unlock" data-id="${note.id}">${icon('unlock',15)} Unlock note</button></div>` : `<div class="editor-body ${drawingVisible?'drawing-mode':''}"><input class="editor-title" id="note-title" aria-label="Note title" placeholder="Untitled ${note.kind === 'checklist' ? 'checklist' : 'note'}" value="${attr(note.content.title)}">
    ${note.kind === 'text' ? richToolbar(note) + `<div id="note-content" class="note-content" contenteditable="true" role="textbox" aria-multiline="true" aria-label="Note text" spellcheck="true" style="font-family:${attr(fontFor(note).family || 'inherit')};font-size:${note.fontSize}px">${note.content.richHTML ? sanitizeHTML(note.content.richHTML) : escape(note.content.text).replace(/\n/g,'<br>')}</div>` : `<div class="editor-list" id="editor-list">${checklistRows(note)}</div><button class="add-item" data-action="add-item">${icon('plus',17)} Add a little to-do</button>`}
    <div id="drawing-area">${drawingVisible ? drawingMarkup() : note.content.strokes?.length ? '<canvas id="drawing-preview" class="drawing-canvas" style="height:140px;border:0;margin-top:20px;cursor:pointer" aria-label="Note sketch — click to edit"></canvas>' : ''}</div></div>
    <div class="editor-footer"><span id="editor-stats">${note.encryptedContent ? 'Encrypted · ' : ''}${note.kind === 'checklist' ? `${note.content.items.filter(item=>item.isCompleted).length} of ${note.content.items.length} completed` : `${note.content.text.trim().split(/\s+/).filter(Boolean).length} words`} · Saved as you go</span><div class="footer-actions"><button data-action="draw">${icon('draw',14)} ${drawingVisible ? 'Done drawing' : 'Make a sketch'}</button><button class="icon-button" data-action="share" title="Export note" aria-label="Export note">${icon('share',15)}</button></div></div>`}</div>`;
  if (!locked && drawingVisible) setupDrawing();
  else if (!locked && note.content.strokes?.length) { drawStrokes($('#drawing-preview'), note.content.strokes); $('#drawing-preview').addEventListener('click',()=>{drawingVisible=true;renderEditor();}); }
}
function richToolbar(note) {
  return `<div class="rich-toolbar" role="toolbar" aria-label="Text formatting"><select id="font-select" aria-label="Font">${FONTS.map(font => `<option value="${font.id}" ${note.font===font.id?'selected':''}>${escape(font.name || font.displayName)}</option>`).join('')}</select><select id="font-size" aria-label="Font size">${[12,14,16,18,20,24,28,32,40].map(size=>`<option ${note.fontSize===size?'selected':''}>${size}</option>`).join('')}</select><span class="toolbar-separator"></span>${[['bold','bold'],['italic','italic'],['underline','underline'],['strikeThrough','strike'],['insertUnorderedList','list'],['insertOrderedList','numbered']].map(([command,glyph])=>`<button data-command="${command}" aria-label="${command}" title="${command}">${icon(glyph,15)}</button>`).join('')}<span class="toolbar-separator"></span><button data-command="undo" title="Undo" aria-label="Undo">${icon('undo',15)}</button><button data-command="redo" title="Redo" aria-label="Redo">${icon('redo',15)}</button></div>`;
}
function checklistRows(note) {
  return note.content.items.map((item,index)=>`<div class="checklist-row ${item.isCompleted?'completed':''}" data-item="${item.id}"><button class="check-toggle" data-action="editor-toggle" data-item="${item.id}" aria-label="${item.isCompleted?'Uncheck':'Check'} item">${item.isCompleted?icon('check',14):''}</button><input data-check-input="${item.id}" value="${attr(item.text)}" placeholder="Something to do…" aria-label="Checklist item ${index+1}"><div class="row-actions"><button data-action="item-up" data-item="${item.id}" aria-label="Move item up" ${index===0?'disabled':''}>${icon('up',13)}</button><button data-action="item-down" data-item="${item.id}" aria-label="Move item down" ${index===note.content.items.length-1?'disabled':''}>${icon('down',13)}</button><button data-action="item-delete" data-item="${item.id}" aria-label="Remove item">${icon('close',13)}</button></div></div>`).join('');
}
async function saveRichText() { const field=$('#note-content'); if (!field || !currentNote()) return; await store.updateNote(editorID,note=>{note.content.text=field.innerText;note.content.richHTML=sanitizeHTML(field.innerHTML);note.content.richText=null;});const stats=$('#editor-stats');if(stats)stats.textContent=`${currentNote().encryptedContent?'Encrypted · ':''}${currentNote().content.text.trim().split(/\s+/).filter(Boolean).length} words · Saved as you go`; }

function showModal(title, html, {submit, handler, cancel='Close', afterOpen}={}) {
  if (modalCleanup) { modalCleanup(); modalCleanup=null; }
  utility.innerHTML = `<form id="utility-form"><div class="utility-header"><h2>${escape(title)}</h2><button type="button" class="icon-button" data-action="close-utility" aria-label="Close">${icon('close',18)}</button></div><div class="utility-body">${html}</div><div class="utility-error" role="alert"></div><div class="utility-actions"><button type="button" class="button" data-action="close-utility">${escape(cancel)}</button>${submit?`<button class="button primary" type="submit">${escape(submit)}</button>`:''}</div></form>`;
  $('#utility-form').addEventListener('submit',async event=>{event.preventDefault();const button=$('button[type=submit]',utility);if(button)button.disabled=true;try {await handler(new FormData(event.currentTarget));utility.close();} catch(error){const errorLabel=$('.utility-error',utility);if(errorLabel)errorLabel.textContent=error.message||String(error);else report(error);if(button)button.disabled=false;}});
  if (!utility.open) utility.showModal();
  afterOpen?.();
}
utility.addEventListener('close',()=>{if(modalCleanup){modalCleanup();modalCleanup=null;}});
function field(label,name,value='',type='text',extra='') { return `<div class="field"><label for="field-${name}">${escape(label)}</label><input id="field-${name}" name="${name}" type="${type}" value="${attr(value)}" ${extra}></div>`; }
function addGroup() { showModal('A home for your thoughts',`<p>Give a group a name. You can move notes into it or drop them onto its sidebar label.</p>${field('Group name','name','','text','required maxlength="80" placeholder="e.g. Weekend plans"')}`,{submit:'Create group',handler:async data=>{filter=await store.addGroup(data.get('name'));scheduleRender();toast('A new little space, ready for ideas.');}}); }
function groupMenu(id) {
  const group=store.groups.find(group=>group.id===id);if(!group)return;
  showModal('Edit group',`${field('Group name','name',group.name,'text','required maxlength="80"')}<div class="settings-section"><p>Deleting a group keeps its notes in All notes.</p><button type="button" class="button danger" id="delete-group-button">${icon('trash',14)} Delete group</button></div>`,{submit:'Save name',handler:async data=>store.renameGroup(id,data.get('name')),afterOpen:()=>$('#delete-group-button').onclick=async()=>{await store.deleteGroup(id);if(filter===id)filter='all';utility.close();scheduleRender();toast('Group removed. Your notes are safe.');}});
}
function chooseColor(id=editorID) { const note=noteByID(id);if(!note)return;showModal('Change the mood',`<p>A little color goes a long way.</p><div class="color-grid">${COLORS.map(color=>`<button type="button" class="color-swatch ${note.color===color.id?'active':''}" data-color="${color.id}" style="background:#${color.hex.replace('#','')}" aria-label="${attr(color.name)}" title="${attr(color.name)}">${note.color===color.id?`<span class="swatch-check">${icon('check',18)}</span>`:''}</button>`).join('')}</div>`,{afterOpen:()=>{for(const button of utility.querySelectorAll('[data-color]'))button.onclick=async()=>{await store.updateNote(id,n=>n.color=button.dataset.color);utility.close();if(editor.open&&id===editorID)renderEditor();};}}); }
function passwordDialog(id,mode) {
  const note=noteByID(id);if(!note)return;
  const locked=store.isLocked(id);
  if(!mode&&note.encryptedContent&&!locked){showModal('A little privacy',`<p>Your note is encrypted on this device and in backups. Lock it when you’re done, or remove its password.</p><div class="context-actions"><button type="button" class="button" data-action="relock" data-id="${id}">${icon('lock',16)} Lock now</button><button type="button" class="button" data-action="remove-password" data-id="${id}">${icon('unlock',16)} Remove password</button></div>`);return;}
  mode=mode||(locked?'unlock':'protect');
  const title=mode==='protect'?'Keep this thought private':mode==='remove'?'Remove password':'Welcome back';
  showModal(title,`<p>${mode==='protect'?'Choose a password with at least 8 characters. Keep it somewhere safe: encrypted notes cannot be recovered without it.':mode==='remove'?'Enter the password to remove encryption from this note.':'Enter your password to unlock this note. It stays encrypted in storage, even while you edit.'}</p>${field('Password','password','','password',`required autocomplete="${mode==='protect'?'new-password':'current-password'}" ${mode==='protect'?'minlength="8"':''}`)}${mode==='protect'?field('Confirm password','confirm','','password','required minlength="8" autocomplete="new-password"'):''}`,{submit:mode==='protect'?'Protect note':mode==='remove'?'Remove password':'Unlock note',handler:async data=>{const password=data.get('password');if(mode==='protect'){if(password!==data.get('confirm'))throw Error('The passwords don’t match.');await store.lockNote(id,password);}else if(mode==='remove')await store.removePassword(id,password);else await store.unlockNote(id,password);if(editor.open&&editorID===id)renderEditor();toast(mode==='protect'?'Note protected.':mode==='remove'?'Password removed.':'Your thought, unlocked.');}});
}
function historyDialog(id=editorID) {
  const note=noteByID(id);if(!note)return;if(store.isLocked(id)){passwordDialog(id,'unlock');return;}
  const history=[...(note.history||[])].reverse();
  showModal('A little time travel',`<p>Revisit an earlier version. Restoring keeps the current version in your history too.</p><div class="history-list">${history.length?history.map(snapshot=>`<div class="history-item"><small>${escape(new Date(snapshot.date).toLocaleString())}</small><h3>${escape(snapshot.content.title||'Untitled note')}</h3><p>${escape(snapshot.content.text||(snapshot.content.items||[]).map(item=>item.text).join('\n'))}</p><button type="button" data-snapshot="${snapshot.id}">${icon('restore',12)} Restore this version</button></div>`).join(''):'<p>Your earlier thoughts will appear here as you edit. Each editing session keeps a snapshot automatically.</p>'}</div>`,{afterOpen:()=>{for(const button of utility.querySelectorAll('[data-snapshot]'))button.onclick=async()=>{await store.restoreSnapshot(id,button.dataset.snapshot);utility.close();if(editor.open)renderEditor();toast('Earlier version restored.');};}});
}
function noteMenu(id=editorID) {
  const note=noteByID(id);if(!note)return;
  const action=(name,glyph,label)=>`<button type="button" class="button" data-action="${name}" data-id="${id}">${icon(glyph,16)} ${label}</button>`;
  showModal('A little more',`<div class="context-actions">${note.deletedAt?action('restore-note','restore','Bring this note back'):action('pin','pin',note.isPinned?'Unpin note':'Pin this note')+action('move-group','folder','Move to a group')+action('duplicate','copy','Make a copy')+action('qr','qr','Show as a QR code')+action('history','history','Browse version history')+action('share','download','Export this note')+action('delete-note','trash','Move to recently deleted')}</div>`);
}
function moveGroup(id) { const note=noteByID(id);showModal('A place to belong',`<div class="field"><label for="group-destination">Move note to</label><select name="group" id="group-destination"><option value="">Ungrouped</option>${store.groups.map(group=>`<option value="${group.id}" ${group.id===note.groupID?'selected':''}>${escape(group.name)}</option>`).join('')}</select></div>`,{submit:'Move note',handler:async data=>{await store.updateNote(id,n=>n.groupID=data.get('group')||null);if(editor.open)renderEditor();toast('Note moved.');}}); }
function download(data,name,type='text/plain') { const url=URL.createObjectURL(new Blob([data],{type}));const link=document.createElement('a');link.href=url;link.download=name;link.click();setTimeout(()=>URL.revokeObjectURL(url),1000); }
function exportNote(id=editorID) { const note=noteByID(id);if(store.isLocked(id)){passwordDialog(id,'unlock');return;}download(plainText(note),`${noteTitle(note).replace(/[^\p{L}\p{N} ._-]/gu,'').slice(0,70)||'note'}.txt`);toast('Your thought, ready to take with you.'); }
function showQR(id=editorID) {
  const note=noteByID(id);if(!note)return;if(store.isLocked(id)){passwordDialog(id,'unlock');return;}
  const text=plainText(note);if(!text.trim()){toast('Write a little something before making a QR code.');return;}
  try {
    window.qrcode.stringToBytes=window.qrcode.stringToBytesFuncs['UTF-8'];
    const qr=window.qrcode(0,'M');qr.addData(text);qr.make();
    const svg=qr.createSvgTag({cellSize:5,margin:20,scalable:true});
    showModal('Show. Scan. Go.',`<p>A little bridge from one screen to another. Anyone who scans this code can read the note.</p><div class="qr-wrap">${svg}</div><div class="settings-actions"><button type="button" class="button small" id="save-qr">${icon('download',14)} Save QR image</button><button type="button" class="button small" id="copy-note">${icon('copy',14)} Copy text</button></div>`,{afterOpen:()=>{$('#save-qr').onclick=()=>download(svg,'stickeynote-qr.svg','image/svg+xml');$('#copy-note').onclick=()=>navigator.clipboard.writeText(text).then(()=>toast('Copied.')).catch(()=>toast('Clipboard access isn’t available in this browser.'));}});
  }catch{toast('This note is too long for a QR code. Try exporting it as text.');}
}
function settingsDialog() {
  showModal('Your little workspace',`<div class="settings-section" style="margin-top:0;border:0"><h3>iCloud, everywhere you think.</h3><p>Connect the same Apple account on Mac, iPhone and the web to keep your notes together.</p><div class="cloud-state">${icon('cloud',17)}<span id="cloud-status">${escape(cloudMessage)}</span></div><div id="apple-sign-in-button"></div><div id="apple-sign-out-button"></div><div class="settings-actions"><button type="button" class="button small" id="connect-cloud">${icon('cloud',14)} Connect iCloud</button><button type="button" class="button small" id="sync-now">${icon('restore',14)} Sync now</button></div><p class="token-note">${window.STICKEY_CLOUD_CONFIG?'Uses your private CloudKit database.':'This build saves on this device. To enable iCloud, configure the Apple container and public web token in config.js.'}</p></div><div class="settings-section"><h3>A copy, just in case.</h3><p>Export a full backup, including groups and history. Password-protected notes stay encrypted.</p><div class="settings-actions"><button type="button" class="button small" data-action="export-backup">${icon('download',14)} Export backup</button><button type="button" class="button small" data-action="import-backup">${icon('upload',14)} Import backup</button></div></div><div class="settings-section"><h3>From a code to a thought.</h3><p>Scan a QR code or barcode from an image. Images are processed right here on your device.</p><button type="button" class="button small" data-action="scan">${icon('scan',14)} Scan an image</button></div><div class="settings-section"><h3>Small shortcuts, big help.</h3><p>⌘ / Ctrl N &nbsp; New note<br>⌘ / Ctrl T &nbsp; New checklist<br>⌘ / Ctrl K &nbsp; Search<br>Escape &nbsp; Close a note</p></div>`,{afterOpen:()=>{$('#connect-cloud').onclick=async()=>{await cloud.connect();};$('#sync-now').onclick=async()=>{try{await cloud.sync();}catch(error){report(error);}};if(cloud.state.configured)cloud.connect();}});
}

function drawingMarkup() { return `<div class="drawing-tools" role="toolbar" aria-label="Drawing tools">${['30362B','376CC8','D65555'].map(color=>`<button class="pen-color ${drawingColor===color&&!erasing?'active':''}" style="--pen:#${color}" data-pen="${color}" aria-label="${color==='30362B'?'Black':color==='376CC8'?'Blue':'Red'} pen"></button>`).join('')}<input type="range" min="1" max="12" value="${drawingWidth}" id="pen-width" aria-label="Stroke width"><span class="tools-spacer"></span><button class="icon-button" id="eraser" title="Eraser" aria-label="Eraser" style="${erasing?'background:#ffffff80':''}">${icon('eraser',17)}</button><button class="icon-button" id="undo-drawing" title="Undo stroke" aria-label="Undo stroke">${icon('undo',17)}</button><button class="icon-button" id="export-drawing" title="Export sketch" aria-label="Export sketch">${icon('download',17)}</button><button class="icon-button" id="clear-drawing" title="Clear sketch" aria-label="Clear sketch">${icon('trash',16)}</button></div><canvas id="drawing-canvas" class="drawing-canvas" aria-label="Draw on your note"></canvas><p class="drawing-label">A thought doesn’t have to be made of words.</p>`; }
function drawStrokes(canvas, strokes, current) {
  if(!canvas)return;const rect=canvas.getBoundingClientRect();const scale=window.devicePixelRatio||1;canvas.width=Math.round(rect.width*scale);canvas.height=Math.round(rect.height*scale);const context=canvas.getContext('2d');context.scale(scale,scale);context.lineCap='round';context.lineJoin='round';
  if(canvas.id==='drawing-canvas'&&currentNote()){
    const note=currentNote(),text=note.kind==='checklist'?note.content.items.map(item=>`${item.isCompleted?'☑':'☐'} ${item.text}`).join('\n'):note.content.text;
    const size=Math.min(24,note.fontSize);context.font=`${size}px ${fontFor(note).family||'sans-serif'}`;context.fillStyle='#39432e';context.globalAlpha=.85;
    let y=26;for(const paragraph of text.split('\n')){let line='';for(const word of paragraph.split(' ')){const next=line?`${line} ${word}`:word;if(context.measureText(next).width>rect.width-36&&line){context.fillText(line,18,y);y+=size*1.6;line=word;}else line=next;}context.fillText(line,18,y);y+=size*1.6;}context.globalAlpha=1;
  }
  for(const stroke of [...strokes,...(current?[current]:[])]){if(!stroke.points.length)continue;context.beginPath();context.strokeStyle=`#${stroke.color.replace('#','')}`;context.lineWidth=stroke.width;stroke.points.forEach((point,index)=>context[index?'lineTo':'moveTo'](point.x*rect.width,point.y*rect.height));if(stroke.points.length===1){context.lineTo(stroke.points[0].x*rect.width+.1,stroke.points[0].y*rect.height+.1);}context.stroke();}
}
function setupDrawing() {
  const canvas=$('#drawing-canvas');let current=null,previous=null,drawFrame=0;
  const redraw=()=>{cancelAnimationFrame(drawFrame);drawFrame=requestAnimationFrame(()=>drawStrokes(canvas,currentNote()?.content.strokes||[],current?.points?current:null));};
  const point=event=>{const rect=canvas.getBoundingClientRect();return{x:Math.max(0,Math.min(1,(event.clientX-rect.left)/rect.width)),y:Math.max(0,Math.min(1,(event.clientY-rect.top)/rect.height))};};
  const eraseAt=async p=>{const rect=canvas.getBoundingClientRect();await store.updateNote(editorID,n=>n.content.strokes=n.content.strokes.filter(stroke=>!stroke.points.some(q=>Math.hypot((q.x-p.x)*rect.width,(q.y-p.y)*rect.height)<18)));redraw();};
  canvas.onpointerdown=event=>{event.preventDefault();canvas.setPointerCapture(event.pointerId);previous=structuredClone(currentNote().content.strokes||[]);const p=point(event);if(erasing){current={erase:true};eraseAt(p);}else current={id:crypto.randomUUID().toUpperCase(),points:[p],color:drawingColor,width:drawingWidth};redraw();};
  canvas.onpointermove=event=>{if(!current)return;const p=point(event);if(current.erase){eraseAt(p);return;}const last=current.points.at(-1);if(Math.hypot(p.x-last.x,p.y-last.y)>.002){current.points.push(p);redraw();}};
  const finish=async()=>{if(!current)return;const complete=current;current=null;drawingUndo.push(previous);if(drawingUndo.length>30)drawingUndo.shift();if(!complete.erase)try{await store.updateNote(editorID,n=>n.content.strokes.push(complete));}catch(error){report(error);}redraw();};
  canvas.onpointerup=finish;canvas.onpointercancel=finish;
  for(const button of document.querySelectorAll('[data-pen]'))button.onclick=()=>{drawingColor=button.dataset.pen;erasing=false;renderEditor();};
  $('#pen-width').oninput=event=>{drawingWidth=Number(event.target.value);};
  $('#eraser').onclick=()=>{erasing=!erasing;renderEditor();};
  $('#undo-drawing').onclick=async()=>{const snapshot=drawingUndo.pop();if(snapshot){await store.updateNote(editorID,n=>n.content.strokes=snapshot);redraw();}else toast('No strokes to undo yet.');};
  $('#clear-drawing').onclick=async()=>{drawingUndo.push(structuredClone(currentNote().content.strokes));await store.updateNote(editorID,n=>n.content.strokes=[]);redraw();};
  $('#export-drawing').onclick=()=>{const result=document.createElement('canvas');result.width=canvas.width;result.height=canvas.height;const ctx=result.getContext('2d');ctx.fillStyle=`#${colorFor(currentNote()).hex.replace('#','')}`;ctx.fillRect(0,0,result.width,result.height);ctx.drawImage(canvas,0,0);result.toBlob(blob=>{const url=URL.createObjectURL(blob);const link=document.createElement('a');link.href=url;link.download='a-little-sketch.png';link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);});};
  redraw();
}

async function scanImage(file) {
  if(!file)return;if(file.size>30*1024*1024){toast('Choose an image smaller than 30 MB.');return;}toast('Taking a closer look…');
  try {const bitmap=await createImageBitmap(file);let values=[];
    if('BarcodeDetector'in window){const detector=new BarcodeDetector();try{values=(await detector.detect(bitmap)).map(code=>({text:code.rawValue,format:code.format}));}catch{}}
    if(!values.length){if(!window.jsQR)await new Promise((resolve,reject)=>{const script=document.createElement('script');script.src='./vendor/jsqr.js';script.onload=resolve;script.onerror=reject;document.head.append(script);});const scale=Math.min(1,1800/Math.max(bitmap.width,bitmap.height));const canvas=document.createElement('canvas');canvas.width=Math.round(bitmap.width*scale);canvas.height=Math.round(bitmap.height*scale);const ctx=canvas.getContext('2d',{willReadFrequently:true});ctx.drawImage(bitmap,0,0,canvas.width,canvas.height);const pixels=ctx.getImageData(0,0,canvas.width,canvas.height);const result=window.jsQR(pixels.data,pixels.width,pixels.height);if(result)values=[{text:result.data,format:'qr_code'}];}
    bitmap.close();if(!values.length){showModal('A little closer?',`<p>No readable code was found. Try a sharper photo with the full code in view. QR codes work in every supported browser; other barcodes need a browser with BarcodeDetector support.</p>`);return;}
    const result=values[0];let link='';try{const url=new URL(result.text);if(['http:','https:'].includes(url.protocol))link=url.href;}catch{}
    showModal('Found a little something',`<p>${escape(result.format.replaceAll('_',' '))}</p><div class="scanner-result">${escape(result.text)}</div><div class="settings-actions" style="margin-top:16px"><button type="button" class="button small" id="scan-to-note">${icon('note',14)} Save as a note</button>${link?`<a class="button small" href="${attr(link)}" target="_blank" rel="noopener noreferrer">${icon('external',14)} Open link</a>`:`<a class="button small" href="https://www.google.com/search?q=${encodeURIComponent(result.text)}" target="_blank" rel="noopener noreferrer">${icon('search',14)} Look up online</a>`}</div>`,{afterOpen:()=>$('#scan-to-note').onclick=async()=>{const id=store.createNote();await store.updateNote(id,n=>{n.content.title=result.format==='qr_code'?'A scanned thought':'Barcode';n.content.text=result.text;});utility.close();openNote(id);}});
  }catch(error){report(new Error('That image couldn’t be scanned. Try a PNG or JPEG image.'));}
}

document.addEventListener('click',async event=>{
  const command=event.target.closest('[data-command]');if(command){event.preventDefault();$('#note-content')?.focus();document.execCommand(command.dataset.command,false,null);await saveRichText();return;}
  const target=event.target.closest('[data-action]');
  if(!target){const card=event.target.closest('[data-note]');if(card)openNote(card.dataset.note);return;}
  const action=target.dataset.action,id=target.dataset.id||editorID,item=target.dataset.item;
  try{switch(action){
    case 'filter':filter=target.dataset.filter;visibleLimit=60;scheduleRender();$('#sidebar').classList.remove('open');break;
    case 'new-note':case 'new-checklist':{const group=!['all','pinned','checklists','trash'].includes(filter)?filter:null;const created=store.createNote(action==='new-checklist'?'checklist':'text',group);openNote(created);requestAnimationFrame(()=>$('#note-title')?.focus());break;}
    case 'toggle-sidebar':$('#sidebar').classList.toggle('open');break;
    case 'settings':settingsDialog();break;
    case 'add-group':addGroup();break;
    case 'group-menu':event.stopPropagation();groupMenu(id);break;
    case 'clear-search':query='';$('#search').value='';scheduleRender();break;
    case 'view-grid':view='grid';scheduleRender();break;
    case 'view-list':view='list';scheduleRender();break;
    case 'show-more':visibleLimit+=60;scheduleRender();break;
    case 'close-editor':editor.close();break;
    case 'close-utility':utility.close();break;
    case 'pin':await store.updateNote(id,n=>n.isPinned=!n.isPinned);if(utility.open)utility.close();if(editor.open)renderEditor();break;
    case 'color':chooseColor(id);break;
    case 'note-menu':noteMenu(id);break;
    case 'move-group':moveGroup(id);break;
    case 'duplicate':{if(store.isLocked(id)){passwordDialog(id,'unlock');break;}const copied=await store.duplicateNote(id);utility.close();if(copied)openNote(copied);break;}
    case 'delete-note':await store.deleteNote(id);utility.close();if(editor.open)editor.close();toast('Moved to Recently deleted. You can bring it back.');break;
    case 'restore-note':await store.restoreNote(id);utility.close();toast('A thought worth keeping. Restored.');break;
    case 'toggle-check':await store.updateNote(id,n=>{const row=n.content.items.find(row=>row.id===item);if(row)row.isCompleted=!row.isCompleted;});break;
    case 'editor-toggle':await store.updateNote(editorID,n=>{const row=n.content.items.find(row=>row.id===item);if(row)row.isCompleted=!row.isCompleted;});renderEditor();break;
    case 'add-item':{const itemID=crypto.randomUUID().toUpperCase();await store.updateNote(editorID,n=>n.content.items.push({id:itemID,text:'',isCompleted:false}));renderEditor();$(`[data-check-input="${itemID}"]`)?.focus();break;}
    case 'item-up':case 'item-down':await store.updateNote(editorID,n=>{const index=n.content.items.findIndex(row=>row.id===item),next=index+(action==='item-up'?-1:1);if(next>=0&&next<n.content.items.length)[n.content.items[index],n.content.items[next]]=[n.content.items[next],n.content.items[index]];});renderEditor();break;
    case 'item-delete':await store.updateNote(editorID,n=>n.content.items=n.content.items.filter(row=>row.id!==item));renderEditor();break;
    case 'password':passwordDialog(id);break;
    case 'unlock':passwordDialog(id,'unlock');break;
    case 'remove-password':passwordDialog(id,'remove');break;
    case 'relock':store.relockNote?store.relockNote(id):store.relockAll();utility.close();if(editor.open)renderEditor();break;
    case 'history':historyDialog(id);break;
    case 'qr':showQR(id);break;
    case 'share':exportNote(id);break;
    case 'draw':drawingVisible=!drawingVisible;renderEditor();break;
    case 'export-backup':await store.flush();download(store.exportArchive(),`StickeyNote-${new Date().toISOString().slice(0,10)}.json`,'application/json');toast('Backup saved.');break;
    case 'import-backup':$('#import-input').click();break;
    case 'scan':$('#scan-input').click();break;
  }}catch(error){report(error);}
});
document.addEventListener('pointerdown',event=>{if(event.target.closest('[data-command]'))event.preventDefault();});
document.addEventListener('input',async event=>{try{if(event.target.id==='note-title')await store.updateNote(editorID,n=>n.content.title=event.target.value);else if(event.target.id==='note-content')await saveRichText();else if(event.target.dataset.checkInput){const item=event.target.dataset.checkInput,value=event.target.value;await store.updateNote(editorID,n=>{const row=n.content.items.find(row=>row.id===item);if(row)row.text=value;});}}catch(error){report(error);}});
document.addEventListener('change',async event=>{try{if(event.target.id==='font-select'){await store.updateNote(editorID,n=>n.font=event.target.value);$('#note-content').style.fontFamily=fontFor(currentNote()).family||'inherit';}else if(event.target.id==='font-size'){await store.updateNote(editorID,n=>n.fontSize=Number(event.target.value));$('#note-content').style.fontSize=`${event.target.value}px`;}}catch(error){report(error);}});
$('#search').addEventListener('input',event=>{query=event.target.value;visibleLimit=60;scheduleRender();});
$('#sort').addEventListener('change',event=>{sort=event.target.value;scheduleRender();});
$('#import-input').onchange=async event=>{const file=event.target.files[0];if(!file)return;try{if(file.size>100000000)throw Error('Choose a backup smaller than 100 MB.');await store.importArchive(await file.text());await store.flush();utility.close();toast('Your notes are back. Backup merged successfully.');}catch(error){report(error);}event.target.value='';};
$('#scan-input').onchange=event=>{scanImage(event.target.files[0]);event.target.value='';};
document.addEventListener('paste',event=>{if(event.target.closest('#note-content')){event.preventDefault();document.execCommand('insertText',false,event.clipboardData.getData('text/plain'));saveRichText();}});
document.addEventListener('keydown',event=>{
  const mod=event.metaKey||event.ctrlKey;
  if(mod&&['n','t','k','f'].includes(event.key.toLowerCase())){event.preventDefault();if(utility.open)return;if(event.key.toLowerCase()==='n'||event.key.toLowerCase()==='t')openNote(store.createNote(event.key.toLowerCase()==='t'?'checklist':'text'));else{editor.close();$('#search').focus();}}
  if(event.target.matches('[data-note],[data-filter]')&&(event.key==='Enter'||event.key===' ')){event.preventDefault();event.target.click();}
  if(event.target.dataset.checkInput){const item=event.target.dataset.checkInput;if(event.key==='Enter'&&!mod){event.preventDefault();$('[data-action="add-item"]').click();}if(mod&&event.key==='Enter'){event.preventDefault();$(`[data-action="editor-toggle"][data-item="${item}"]`).click();}if(mod&&(event.key==='ArrowUp'||event.key==='ArrowDown')){event.preventDefault();$(`[data-action="${event.key==='ArrowUp'?'item-up':'item-down'}"][data-item="${item}"]`).click();}}
});
document.addEventListener('dragstart',event=>{const card=event.target.closest('[data-note]');if(card)event.dataTransfer.setData('text/x-stickey-note',card.dataset.note);});
document.addEventListener('dragover',event=>{const group=event.target.closest('[data-group]');if(group){event.preventDefault();group.classList.add('drop-target');}});
document.addEventListener('dragleave',event=>event.target.closest('[data-group]')?.classList.remove('drop-target'));
document.addEventListener('drop',async event=>{const group=event.target.closest('[data-group]');if(!group)return;event.preventDefault();group.classList.remove('drop-target');const id=event.dataTransfer.getData('text/x-stickey-note');if(noteByID(id)){await store.updateNote(id,n=>n.groupID=group.dataset.group);toast('Note moved.');}});
editor.addEventListener('close',()=>{editorID=null;drawingVisible=false;store.flush().catch(report);scheduleRender();});
document.addEventListener('visibilitychange',()=>{if(document.hidden){if(utility.open)utility.close();utility.innerHTML='';store.relockAll();store.flush().catch(report);if(editor.open)renderEditor();}});
window.addEventListener('pagehide',()=>{store.relockAll();store.flush().catch(report);});
window.addEventListener('resize',()=>{if(drawingVisible&&$('#drawing-canvas'))drawStrokes($('#drawing-canvas'),currentNote()?.content.strokes||[]);});
$('#date-label').textContent=new Date().toLocaleDateString(undefined,{weekday:'long',month:'long',day:'numeric'});
$('#new-note-button').innerHTML=`${icon('plus',16)} New note`;
$('#new-checklist-button').innerHTML=`${icon('checklist',16)} <span>Checklist</span>`;
$('#settings-button').innerHTML=icon('settings',17);$('#mobile-toggle').innerHTML=icon('menu',19);
$('#search-wrap').insertAdjacentHTML('afterbegin',icon('search',16));$('#sort-icon').innerHTML=icon('sort',14);
$('#grid-button').innerHTML=icon('grid',14);$('#list-button').innerHTML=icon('list',16);
renderSidebar();renderBoard();renderStatus();
if(store.errorMessage)toast(store.errorMessage);
if('serviceWorker'in navigator&&location.protocol!=='file:')navigator.serviceWorker.register('./service-worker.js').catch(()=>{});
