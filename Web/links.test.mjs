import test from 'node:test';
import assert from 'node:assert/strict';
import {findLinks,linkedTextHTML,safeLinkURL} from './links.js';

test('detects full URLs, bare domains, www addresses, and email',()=>{
  const links=findLinks('Read https://example.com/path?q=a&b=2#part and www.example.org, example.net/docs or hello@example.com.');
  assert.deepEqual(links.map(link=>link.href),[
    'https://example.com/path?q=a&b=2#part','https://www.example.org/','https://example.net/docs','mailto:hello@example.com'
  ]);
  for(const link of links)assert.equal(link.text,'Read https://example.com/path?q=a&b=2#part and www.example.org, example.net/docs or hello@example.com.'.slice(link.start,link.end));
});

test('excludes surrounding punctuation and keeps balanced URL parentheses',()=>{
  assert.deepEqual(findLinks('(https://example.com/a_(b)). https://example.org/x?foo=1!').map(link=>link.text),[
    'https://example.com/a_(b)','https://example.org/x?foo=1'
  ]);
  assert.equal(findLinks('“https://example.com.”')[0].text,'https://example.com');
  assert.equal(findLinks('Visit https://[::1]:8080/path.')[0].href,'https://[::1]:8080/path');
});

test('supports unicode URLs and explicit email actions',()=>{
  const links=findLinks('🙂 https://例子.测试/你好 mailto:hello@example.com?subject=Hello');
  assert.equal(links[0].start,3);
  assert.equal(links[0].href,'https://xn--fsqu00a.xn--0zwm56d/%E4%BD%A0%E5%A5%BD');
  assert.equal(links[1].href,'mailto:hello@example.com?subject=Hello');
});

test('an at sign in a web path or query does not turn it into an email link',()=>{
  assert.deepEqual(findLinks('example.com/@user example.com/?email=a@b.com hello@example.com').map(link=>link.href),[
    'https://example.com/@user','https://example.com/?email=a@b.com','mailto:hello@example.com'
  ]);
});

test('only permits supported external link protocols',()=>{
  for(const href of ['javascript:alert(1)','data:text/html,hello','file:///tmp/note','/settings','https://','https://exa mple.com','https:\n//example.com','mailto:invalid'])assert.equal(safeLinkURL(href),null,href);
  assert.equal(safeLinkURL('HTTP://example.com'),'http://example.com/');
  assert.deepEqual(findLinks('ftp://example.com and /tmp/example.com and plain text'),[]);
});

test('preview rendering escapes text and link attributes',()=>{
  const html=linkedTextHTML('<img onerror="alert(1)"> https://example.com/?a=1&b=2');
  assert.match(html,/&lt;img onerror=&quot;alert\(1\)&quot;&gt;/);
  assert.match(html,/href="https:\/\/example.com\/\?a=1&amp;b=2"/);
  assert.match(html,/target="_blank" rel="noopener noreferrer" data-auto-link="true"/);
  assert.ok(!html.includes('<img'));
  assert.equal(linkedTextHTML('No links & no markup'),'No links &amp; no markup');
});
