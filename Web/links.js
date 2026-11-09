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
    const href = safeLinkURL(explicit ? label : `${label.includes('@') ? 'mailto:' : 'https://'}${label}`);
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

function setLinkAttributes(anchor,href) {
  anchor.setAttribute('href',href);
  anchor.setAttribute('target','_blank');
  anchor.setAttribute('rel','noopener noreferrer');
  anchor.setAttribute('tabindex','0');
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
    if (automatic && !wholeURL) {
      anchor.replaceWith(...anchor.childNodes); changed = true;
    } else if (automatic) {
      anchor.dataset.autoLink = 'true'; setLinkAttributes(anchor,link.href);
    } else {
      const href = safeLinkURL(anchor.getAttribute('href'));
      if (href) setLinkAttributes(anchor,href);
      else { anchor.replaceWith(...anchor.childNodes); changed = true; }
    }
  }

  // Treat adjacent inline formatting as one text run, without matching across
  // paragraphs, line breaks, or existing explicit links.
  const runs = [];
  let run = {text:'',nodes:[]};
  function flush() { if (run.text) runs.push(run); run = {text:'',nodes:[]}; }
  function visit(node) {
    if (node.nodeType === 3) {
      run.nodes.push({node,start:run.text.length,end:run.text.length+node.length});
      run.text += node.data; return;
    }
    if (node.nodeType !== 1) return;
    if (node.tagName === 'A' || node.tagName === 'BR') { flush(); return; }
    const block = blocks.has(node.tagName);
    if (block) flush();
    for (const child of node.childNodes) visit(child);
    if (block) flush();
  }
  for (const child of root.childNodes) visit(child);
  flush();
  for (const run of runs.reverse()) {
    for (const link of findLinks(run.text).reverse()) {
      const start = run.nodes.find(value => value.start <= link.start && value.end > link.start);
      const end = run.nodes.find(value => value.start < link.end && value.end >= link.end);
      if (!start || !end) continue;
      const range = document.createRange();
      range.setStart(start.node,link.start-start.start); range.setEnd(end.node,link.end-end.start);
      const anchor = document.createElement('a');
      anchor.dataset.autoLink = 'true'; setLinkAttributes(anchor,link.href);
      anchor.append(range.extractContents()); range.insertNode(anchor); changed = true;
    }
  }
  if (changed && bookmark && bookmark.anchor !== undefined && bookmark.focus !== undefined) {
    const index = selectionIndex(root), anchor = index.point(bookmark.anchor), focus = index.point(bookmark.focus);
    selection.setBaseAndExtent(anchor.node,anchor.offset,focus.node,focus.offset);
  }
}
