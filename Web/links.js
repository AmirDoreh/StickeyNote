const escapeHTML = value => String(value ?? '').replace(/[&<>"']/g, character => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[character]));
const blocks = new Set(['P','DIV','LI','UL','OL','BLOCKQUOTE']);

export function safeLinkURL(value) {
  if (typeof value !== 'string' || /[\s\u0000-\u001f\u007f]/u.test(value)) return null;
  if (!/^(https?:\/\/|mailto:)/i.test(value)) return null;
  try {
    const url = new URL(value);
    if (url.protocol === 'mailto:') return url.pathname.includes('@') ? url.href : null;
    return ['http:','https:'].includes(url.protocol) && url.hostname ? url.href : null;
  } catch { return null; }
}

export function findLinks(text) {
  const candidates = /(?:https?:\/\/|mailto:)[^\s<>"'`]+|(?:[\p{L}\p{N}._%+-]+@)?(?:[\p{L}\p{N}](?:[\p{L}\p{N}-]*[\p{L}\p{N}])?\.)+(?:[\p{L}]{2,63}|xn--[a-z0-9-]+)(?::\d{1,5})?(?:[/?#][^\s<>"'`]*)?/giu;
  const links = [];
  for (const match of String(text).matchAll(candidates)) {
    if (match.index && /[\p{L}\p{N}_@/.-]/u.test(text[match.index-1])) continue;
    let label = match[0].replace(/[.,!?:;\u2019\u201d]+$/u, '');
    for (const [open,close] of [['(',')'],['[',']'],['{','}']]) {
      while (label.endsWith(close) && label.split(close).length > label.split(open).length) label = label.slice(0,-1);
    }
    // Punctuation can follow a closing parenthesis, or sit just inside it.
    label = label.replace(/[.,!?:;\u2019\u201d]+$/u, '');
    const explicit = /^(https?:\/\/|mailto:)/i.test(label);
    const href = safeLinkURL(explicit ? label : `${/^[^/?#]+@/.test(label) ? 'mailto:' : 'https://'}${label}`);
    if (href) links.push({start:match.index,end:match.index+label.length,text:label,href});
  }
  return links;
}

export function linkedTextHTML(text) {
  text = String(text ?? '');
  let html = '', offset = 0;
  for (const link of findLinks(text)) {
    html += escapeHTML(text.slice(offset,link.start));
    html += `<a href="${escapeHTML(link.href)}" target="_blank" rel="noopener noreferrer" data-auto-link="true">${escapeHTML(link.text)}</a>`;
    offset = link.end;
  }
  return html + escapeHTML(text.slice(offset));
}

// Index text and line boundaries, so wrapping a URL preserves forward/backward
// selections as well as the caret on otherwise empty lines.
function selectionIndex(root) {
  const positions = new Map(), texts = [], boundaries = [];
  let offset = 0;
  function visit(node) {
    if (node.nodeType === 3) {
      positions.set(node,offset); texts.push({node,start:offset,end:offset+node.length}); offset += node.length;
      return;
    }
    if (node.nodeType !== 1) return;
    if (node.tagName === 'BR') { offset++; return; }
    const block = node !== root && blocks.has(node.tagName);
    if (block) offset++;
    const children = [offset];
    boundaries.push({node,offset:0,position:offset});
    for (const child of node.childNodes) {
      visit(child); children.push(offset);
      boundaries.push({node,offset:children.length-1,position:offset});
    }
    positions.set(node,children);
    if (block) offset++;
  }
  visit(root);
  return {
    offset(node, index) { const value = positions.get(node); return typeof value === 'number' ? value+index : value?.[index]; },
    point(position) {
      const text = texts.find(value => value.start <= position && value.end >= position);
      if (text) return {node:text.node,offset:position-text.start};
      return boundaries.find(value => value.position === position) || {node:root,offset:root.childNodes.length};
    }
  };
}

export function captureTextSelection(root) {
  const selection = root.ownerDocument.getSelection();
  if (!root.contains(selection?.anchorNode) || !root.contains(selection?.focusNode)) return null;
  const index = selectionIndex(root);
  return {anchor:index.offset(selection.anchorNode,selection.anchorOffset),focus:index.offset(selection.focusNode,selection.focusOffset)};
}

export function restoreTextSelection(root,selection) {
  if (!selection) return;
  const index = selectionIndex(root), anchor = index.point(selection.anchor), focus = index.point(selection.focus);
  root.focus(); root.ownerDocument.getSelection().setBaseAndExtent(anchor.node,anchor.offset,focus.node,focus.offset);
}

function setLinkAttributes(anchor,href) {
  anchor.setAttribute('href',href);
  anchor.setAttribute('target','_blank');
  anchor.setAttribute('rel','noopener noreferrer');
  anchor.setAttribute('tabindex','0');
}

function liftInsertionPoint(range,ancestor) {
  if (ancestor.nodeType === 3) return;
  while (range.startContainer !== ancestor) {
    const node = range.startContainer, offset = range.startOffset;
    const length = node.nodeType === 3 ? node.length : node.childNodes.length;
    if (offset === 0) range.setStartBefore(node);
    else if (offset === length) range.setStartAfter(node);
    else if (node.nodeType === 3) range.setStartBefore(node.splitText(offset));
    else {
      const suffix = node.cloneNode(false);
      while (node.childNodes[offset]) suffix.append(node.childNodes[offset]);
      node.after(suffix); range.setStartBefore(suffix);
    }
    range.collapse(true);
  }
}

function captureEditor(root) {
  const selection = root.ownerDocument.getSelection(), index = selectionIndex(root);
  return {
    html:root.innerHTML,
    anchor:index.offset(selection?.anchorNode,selection?.anchorOffset),
    focus:index.offset(selection?.focusNode,selection?.focusOffset)
  };
}

// Native contenteditable undo stores references to text nodes. Splitting those
// nodes to recognize links invalidates its edits, so keep bounded editor-local
// snapshots covering text, formatting, and selection together.
export function createRichTextHistory(root) {
  let undo = [], redo = [], current = captureEditor(root), pending = null, previousEdit = null;
  function trim(stack) {
    while (stack.length > 30 || (stack.length > 1 && stack.reduce((size,state)=>size+state.html.length,0) > 2_000_000)) stack.shift();
  }
  function restore(state) {
    root.innerHTML = state.html; root.focus();
    const index = selectionIndex(root), anchor = index.point(state.anchor), focus = index.point(state.focus);
    root.ownerDocument.getSelection().setBaseAndExtent(anchor.node,anchor.offset,focus.node,focus.offset);
    current = captureEditor(root); pending = null; previousEdit = null;
  }
  return {
    begin(kind) { pending = {state:captureEditor(root),kind}; },
    commit() {
      const next = captureEditor(root), before = pending?.state || current, kind = pending?.kind;
      pending = null;
      if (before.html === next.html) { current = next; return; }
      const now = Date.now();
      const continuesTyping = kind === 'insertText' && previousEdit?.kind === kind && now-previousEdit.time < 1000 &&
        before.anchor === before.focus && before.anchor === previousEdit.focus;
      if (!continuesTyping) { undo.push(before); trim(undo); }
      redo = []; current = next; previousEdit = {kind,time:now,focus:next.focus};
    },
    undo() { if (!undo.length) return false; redo.push(captureEditor(root)); trim(redo); restore(undo.pop()); return true; },
    redo() { if (!redo.length) return false; undo.push(captureEditor(root)); trim(undo); restore(redo.pop()); return true; },
    clear() { undo = []; redo = []; current = null; pending = null; previousEdit = null; }
  };
}

export function updateAutomaticLinks(root) {
  if (!root) return;
  const document = root.ownerDocument, selection = document.getSelection();
  let bookmark;
  if (selection?.anchorNode && root.contains(selection.anchorNode) && root.contains(selection.focusNode)) {
    const index = selectionIndex(root);
    bookmark = {anchor:index.offset(selection.anchorNode,selection.anchorOffset),focus:index.offset(selection.focusNode,selection.focusOffset)};
  }
  let changed = false;
  for (const anchor of [...root.querySelectorAll('a')]) {
    const text = anchor.textContent, links = findLinks(text), link = links[0];
    const wholeURL = links.length === 1 && link.start === 0 && link.end === text.length;
    const automatic = anchor.dataset.autoLink === 'true' || (wholeURL && safeLinkURL(anchor.getAttribute('href')) === link.href);
    if (automatic) {
      anchor.dataset.autoLink = 'true';
      if (anchor.querySelector('br,p,div,li,ul,ol,blockquote')) {
        anchor.replaceWith(...anchor.childNodes); changed = true;
      }
    } else {
      const href = safeLinkURL(anchor.getAttribute('href'));
      if (href) setLinkAttributes(anchor,href);
      else { anchor.replaceWith(...anchor.childNodes); changed = true; }
    }
  }

  // Treat adjacent inline formatting as one text run, without matching across
  // paragraphs, line breaks, or existing explicit links.
  const runs = [];
  let run = {text:'',nodes:[],anchors:[]};
  function flush() { if (run.text || run.anchors.length) runs.push(run); run = {text:'',nodes:[],anchors:[]}; }
  function visit(node) {
    if (node.nodeType === 3) {
      run.nodes.push({node,start:run.text.length,end:run.text.length+node.length});
      run.text += node.data; return;
    }
    if (node.nodeType !== 1) return;
    if (node.tagName === 'A' && node.dataset.autoLink === 'true') {
      const start = run.text.length;
      for (const child of node.childNodes) visit(child);
      run.anchors.push({node,start,end:run.text.length}); return;
    }
    if (node.tagName === 'A' || node.tagName === 'BR') { flush(); return; }
    const block = blocks.has(node.tagName);
    if (block) flush();
    for (const child of node.childNodes) visit(child);
    if (block) flush();
  }
  for (const child of root.childNodes) visit(child);
  flush();
  for (const run of runs.reverse()) {
    const links = findLinks(run.text), kept = new Set();
    for (const anchor of run.anchors) {
      const link = links.find(value => value.start === anchor.start && value.end === anchor.end);
      if (link) { setLinkAttributes(anchor.node,link.href); kept.add(link); }
      else { anchor.node.replaceWith(...anchor.node.childNodes); changed = true; }
    }
    for (const link of links.reverse()) {
      if (kept.has(link)) continue;
      const start = run.nodes.find(value => value.start <= link.start && value.end > link.start);
      const end = run.nodes.find(value => value.start < link.end && value.end >= link.end);
      if (!start || !end) continue;
      const range = document.createRange();
      range.setStart(start.node,link.start-start.start); range.setEnd(end.node,link.end-end.start);
      const ancestor = range.commonAncestorContainer;
      const anchor = document.createElement('a');
      anchor.dataset.autoLink = 'true'; setLinkAttributes(anchor,link.href);
      anchor.append(range.extractContents());
      // Insert beside partial formatting wrappers, rather than making the
      // entire URL inherit the style of its first character.
      liftInsertionPoint(range,ancestor); range.insertNode(anchor); changed = true;
    }
  }
  if (changed && bookmark && bookmark.anchor !== undefined && bookmark.focus !== undefined) {
    const index = selectionIndex(root), anchor = index.point(bookmark.anchor), focus = index.point(bookmark.focus);
    selection.setBaseAndExtent(anchor.node,anchor.offset,focus.node,focus.offset);
  }
}
