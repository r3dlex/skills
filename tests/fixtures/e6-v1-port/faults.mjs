// Fault seams mirror the original unittest mocks; fixture writes only.
import fs from 'node:fs';
import cp from 'node:child_process';
import {syncBuiltinESMExports} from 'node:module';
const fault = JSON.parse(process.env.E6_V1_FAULT ?? '{}');
const write = fs.writeFileSync, rename = fs.renameSync;
const realpath = fs.realpathSync;
const lstat = fs.lstatSync;
const read = fs.readFileSync;
if (fault.candidate_read) {
  let reads = 0;
  fs.readFileSync = function(path, ...args) {
    const value = read(path, ...args);
    if (String(path) === fault.candidate_read && ++reads === 2) mutate();
    return value;
  };
}
function mutate() {
  if (fault.mutation) write(fault.mutation.path, fault.mutation.value);
}
function fail(point) {
  if (fault.boundary === point) throw Object.assign(new Error('injected ' + point), {code: 'EIO'});
}
fs.writeFileSync = function(path, ...args) {
  fail('write-before');
  const result = write(path, ...args);
  if (String(path).endsWith('/goals.json') && fault.moment !== 'graph') mutate();
  return result;
};
fs.renameSync = function(path, target) {
  const destination = String(target);
  const kind = destination.endsWith('/northstar-readiness-v1.json') ? 'register' : destination.endsWith('/.ai/traceability/graph.json') ? 'graph' : 'rename';
  fail(kind + '-before');
  const result = rename(path, target);
  if (kind === 'graph' && fault.moment === 'graph') mutate();
  fail(kind + '-after');
  return result;
};
if (fault.race) {
  let changed = false;
  const race = () => {
    changed = true;
    rename(fault.race.path, fault.race.saved);
    fs.symlinkSync(fault.race.outside, fault.race.path, fault.race.directory ? 'dir' : 'file');
  };
  fs.realpathSync = function(path, ...args) {
    const hit = !changed && String(path) === fault.race.path;
    if (hit && fault.race.when === 'before') race();
    const result = realpath(path, ...args);
    if (hit && fault.race.when === 'after') race();
    return result;
  };
}
if (fault.lstat_race) {
  let armed = false, changed = false;
  fs.realpathSync = function(path, ...args) {
    const result = realpath(path, ...args);
    if (String(path) === fault.lstat_race.path) armed = true;
    return result;
  };
  fs.lstatSync = function(path, ...args) {
    if (armed && !changed && String(path) === fault.lstat_race.path) {
      changed = true;
      rename(fault.lstat_race.path, fault.lstat_race.saved);
      fs.symlinkSync(fault.lstat_race.outside, fault.lstat_race.path);
    }
    return lstat(path, ...args);
  };
}
if (fault.gitFailure) {
  cp.spawnSync = function(command, argv) {
    write(fault.gitFailure, JSON.stringify([command, ...argv]));
    return {status: 129, stdout: '', stderr: 'unknown option'};
  };
}
syncBuiltinESMExports();
