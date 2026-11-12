import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const html = readFileSync(new URL('./galmuri-prototype.html', import.meta.url), 'utf8');
const core = html.match(/<script id="flow-core">([\s\S]*?)<\/script>/)[1];
function run(source) {
  return vm.runInNewContext(`${core}\n${source}`);
}

test('동일 URL 두 항목을 유지하고 프로필별로 변경을 분리한다', () => {
  const result = run(`const s=createDemo();s.view='duplicates';const ids=visibleItems(s).map(x=>x.id);s.profile='personal';[ids,changesFor(s).length]`);
  assert.deepEqual(JSON.parse(JSON.stringify(result)), [['s1', 's5'], 0]);
});

test('삭제·이동·이름 충돌의 미해결 선택은 최종 검토 진입을 막는다', () => {
  assert.equal(run(`const s=createDemo();beginReview(s);next(s);unresolved(s)`), 3);
  assert.throws(() => run(`const s=createDemo();beginReview(s);next(s);next(s)`), /충돌/);
  assert.equal(run(`const s=createDemo();beginReview(s);next(s);s.review.conflicts.forEach(c=>choose(s,c.id,'ours'));next(s);s.step`), 'review');
});

test('승인 전 반영을 막고 선택한 결과를 시연 이력에 남긴다', () => {
  assert.throws(() => run(`const s=createDemo();beginReview(s);next(s);s.review.conflicts.forEach(c=>choose(s,c.id,'ours'));next(s);next(s)`), /확인/);
  const result = run(`const s=createDemo();beginReview(s);next(s);s.review.conflicts.forEach(c=>choose(s,c.id,'theirs'));next(s);s.review.ack=true;next(s);[s.step,s.history[0].profile,s.history[0].choices.s8]`);
  assert.deepEqual(Array.from(result), ['complete', 'studio', 'theirs']);
});

test('원본 변경 상황은 이전 선택과 승인을 무효화하고 재검토로 돌아간다', () => {
  const result = run(`const s=createDemo();beginReview(s);next(s);s.review.conflicts.forEach(c=>choose(s,c.id,'ours'));next(s);s.review.ack=true;s.review.changed=true;next(s);[s.step,s.review.ack,unresolved(s),s.history.length]`);
  assert.deepEqual(Array.from(result), ['merge', false, 3, 0]);
});

test('이름 편집 후 폴더 이동을 되돌려도 이전 편집은 유지한다', () => {
  const result = run(`const s=createDemo();stage(s,'s4',{kind:'edit',name:'새 이름',url:s.items[3].url});stage(s,'s4',{kind:'move',folder:'읽을거리'});undo(s);[s.changes.s4.name,s.changes.s4.folder,s.changes.s4.kind]`);
  assert.deepEqual(Array.from(result), ['새 이름', undefined, 'edit']);
});

test('추가 항목을 검토 목록에 남기고 되돌리기는 실제 시안 항목도 제거한다', () => {
  const result = run(`const s=createDemo();s.profile='personal';addItem(s,{id:'new',profile:'personal',name:'추가',url:'https://example.net/new',folder:'읽을거리'});beginReview(s);const count=s.review.additions.length;undo(s);[count,s.items.some(x=>x.id==='new'),changesFor(s).length]`);
  assert.deepEqual(Array.from(result), [1, false, 0]);
});

test('새 프로필에 변경이 없으면 저장 흐름을 시작하지 않는다', () => {
  assert.throws(() => run(`const s=createDemo();s.profile='personal';beginReview(s)`), /변경 없음/);
});

test('시안에서 이름과 URL을 함께 바꾸면 두 값 모두 검토에 표시한다', () => {
  const result = run(`const s=createDemo();stage(s,'s4',{kind:'edit',name:'새 이름',url:'https://example.net/new'});beginReview(s);s.review.conflicts.find(x=>x.id==='s4').ours`);
  assert.match(result, /새 이름/);
  assert.match(result, /https:\/\/example.net\/new/);
});
