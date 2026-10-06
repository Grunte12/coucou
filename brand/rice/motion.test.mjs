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
test('reduced motion is static; paused physics is untouched; resume is bounded', () => {
  const motion=new RiceMotion();motion.select('sending');
  assert.deepEqual(motion.frame(1,true),poses.sending);
  const before=motion.elapsed; const a=motion.frame(0,false,true); const b=motion.frame(100,false,true);
  assert.deepEqual(a,b);assert.equal(motion.elapsed,before);
  motion.select('idle');const v=motion.frame(100);
  assert.ok(Object.values(v).every(Number.isFinite));assert.equal(motion.elapsed-before,.05);
});
