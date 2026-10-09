import test from 'node:test';
import assert from 'node:assert/strict';
import { Spring, RiceMotion, poses } from './motion.mjs';
test('spring retargets without a jump or lost momentum', () => {
  const spring = new Spring(0); spring.to(20); spring.step(.02);
  const before = [spring.value, spring.velocity]; spring.to(-10);
  assert.deepEqual([spring.value,spring.velocity],before);
  for(let i=0;i<400;i++) spring.step(1/60);
  assert.ok(Math.abs(spring.value+10)<.001);
});
test('every state and fast interruptions remain finite and converge', () => {
  const motion=new RiceMotion();
  for(let i=0;i<100;i++) {motion.select(Object.keys(poses)[i%7]); motion.frame(1/60);}
  for(const state of Object.keys(poses)) {
    assert.equal(motion.select(state),true);
    for(let i=0;i<300;i++) for(const value of Object.values(motion.frame(1/60))) assert.ok(Number.isFinite(value));
    for(const [k,v] of Object.entries(poses[state])) assert.ok(Math.abs(motion.springs[k].value-v)<.001,k);
  }
  assert.equal(motion.select('unknown'),false);
});

test('cursor bounds and independent channels converge through a state change', () => {
  const motion=new RiceMotion();
  motion.setCursor(20,-12);motion.setPressed(true);motion.select('working');
  assert.equal(motion.cursorX.target,3);assert.equal(motion.cursorY.target,-2);
  assert.equal(motion.press.target,.97);
  for(let i=0;i<500;i++) motion.frame(1/60);
  const values=motion.frame(0);
  assert.ok(Math.abs(values.cursorX-3)<.001);
  assert.ok(Math.abs(values.cursorY+2)<.001);
  assert.ok(Math.abs(values.press-.97)<.001);
  assert.ok(Math.abs(values.x-poses.working.x)<.001);
  motion.clearCursor();motion.setPressed(false);
  for(let i=0;i<500;i++) motion.frame(1/60);
  assert.ok(Math.abs(motion.cursorX.value)<.001);
  assert.ok(Math.abs(motion.cursorY.value)<.001);
  assert.ok(Math.abs(motion.press.value-1)<.001);
});

test('100 rapid gaze and press reversals preserve position and velocity on retarget', () => {
  const motion=new RiceMotion();
  const states=Object.keys(poses);
  for(let i=0;i<100;i++) {
    motion.setCursor(i%2?3:-3,i%2?-2:2);
    motion.setPressed(i%2===0);
    motion.frame(1/60);
    const cursorBefore=[motion.cursorX.value,motion.cursorX.velocity,motion.cursorY.value,motion.cursorY.velocity];
    const pressBefore=[motion.press.value,motion.press.velocity];
    motion.setCursor(i%2?-3:3,i%2?2:-2);
    motion.setPressed(i%2!==0);
    assert.deepEqual([motion.cursorX.value,motion.cursorX.velocity,motion.cursorY.value,motion.cursorY.velocity],cursorBefore);
    assert.deepEqual([motion.press.value,motion.press.velocity],pressBefore);
    motion.select(states[i%states.length]);
    assert.deepEqual([motion.cursorX.value,motion.cursorX.velocity,motion.cursorY.value,motion.cursorY.velocity],cursorBefore);
    assert.deepEqual([motion.press.value,motion.press.velocity],pressBefore);
    for(const value of Object.values(motion.frame(1/60))) assert.ok(Number.isFinite(value));
  }
  motion.setCursor(0,0);motion.setPressed(false);motion.select('done');
  for(let i=0;i<500;i++) motion.frame(1/60);
  for(const [key,value] of Object.entries(poses.done)) assert.ok(Math.abs(motion.springs[key].value-value)<.001,key);
  assert.ok(Math.abs(motion.cursorX.value)<.001);
  assert.ok(Math.abs(motion.cursorY.value)<.001);
  assert.ok(Math.abs(motion.press.value-1)<.001);
});

test('reduced motion snaps cursor and press while preserving the selected pose', () => {
  const motion=new RiceMotion();motion.select('sending');
  motion.setCursor(-9,8);motion.setPressed(true);
  const values=motion.frame(1,true);
  for(const [key,value] of Object.entries(poses.sending)) assert.equal(values[key],value,key);
  assert.equal(values.cursorX,-3);assert.equal(values.cursorY,2);assert.equal(values.press,.97);
  assert.equal(motion.cursorX.velocity,0);assert.equal(motion.cursorY.velocity,0);assert.equal(motion.press.velocity,0);
});

test('paused physics freezes pose, gaze, press and elapsed time; resume is bounded', () => {
  const motion=new RiceMotion();motion.select('sending');
  motion.setCursor(3,-2);motion.setPressed(true);
  for(let i=0;i<8;i++) motion.frame(1/60);
  const lastRendered=motion.frame(1/60);
  const before=motion.elapsed;
  const a=motion.frame(0,false,true);
  const springState=Object.fromEntries(Object.entries({...motion.springs,cursorX:motion.cursorX,cursorY:motion.cursorY,press:motion.press}).map(([k,s])=>[k,[s.value,s.velocity]]));
  const b=motion.frame(100,false,true);
  assert.deepEqual(a,lastRendered);assert.deepEqual(a,b);assert.equal(motion.elapsed,before);
  assert.deepEqual(Object.fromEntries(Object.entries({...motion.springs,cursorX:motion.cursorX,cursorY:motion.cursorY,press:motion.press}).map(([k,s])=>[k,[s.value,s.velocity]])),springState);
  motion.setCursor(-3,2);motion.setPressed(false);
  const afterInput=motion.frame(1/60,false,true);
  assert.deepEqual(afterInput,a);
  assert.equal(motion.cursorX.target,-3);assert.equal(motion.cursorY.target,2);assert.equal(motion.press.target,1);
  motion.select('idle');const v=motion.frame(100);
  assert.ok(Object.values(v).every(Number.isFinite));assert.ok(Math.abs(motion.elapsed-before-.05)<1e-12);
});
