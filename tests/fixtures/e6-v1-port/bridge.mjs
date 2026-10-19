// Bind original direct-import assertions to the executed modules, not a copy.
import {readFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
const root = process.argv[2];
const engine = await import(pathToFileURL(root + '/04-validate-handoff/autobahn/lib/engine.mjs'));
const json = await import(pathToFileURL(root + '/04-validate-handoff/autobahn/lib/json.mjs'));
const {operation, args} = json.parse(readFileSync(0, 'utf8'));
function admission(bundle, selected, context, identity, files, worktree, subject) {
  return {identity, root: files ?? identity, selection: {bundle, selected, subject, entry: null}, context, worktree: worktree ?? null};
}
try {
  let result;
  switch (operation) {
    case 'coverage': { const gaps = []; engine.coverage(args[0], gaps, args[1]); result = gaps; break; }
    case 'add': { const gaps = []; engine.add(gaps, ...args); result = gaps; break; }
    case 'canonical': result = json.canonical(args[0]); break;
    case 'read': result = json.read(args[0]); break;
    case 'digest': result = json.digest(args[0]); break;
    case 'instruction_paths': result = [...engine.instructionPaths(...args)].sort(); break;
    case 'goal_revision': result = engine.goalRevision(...args); break;
    case 'gate_subject': {
      const [bundle, gate, sources, policy, execution_revision, worktree] = args;
      result = engine.gateSubject(admission(bundle, [], {sources, policy, execution_revision}, bundle.repository.root, null, worktree, ''), gate); break;
    }
    case 'policy_admit': {
      const [identity, bundle, selected, context, stage, subject, files, worktree] = args;
      const gaps = [], resolved = [];
      engine.collectGaps(admission(bundle, selected, context, identity, files, worktree, subject), stage, gaps, resolved);
      result = {gaps, resolved}; break;
    }
    case 'requirement_runtime': {
      const [identity, bundle, context] = args;
      const gate = bundle.goals[0].requirements[0];
      bundle.goals[0].requirements[0] = new Proxy(gate, {ownKeys() { Object.keys(null); return []; }});
      const gaps = [], resolved = [];
      engine.collectGaps(admission(bundle, ['G1'], context, identity, null, null, context.authority.subject_sha256), 'implementation', gaps, resolved);
      result = {gaps, resolved}; break;
    }
    case 'dependency_complete': {
      const [bundle, id, completed_goals, execution_revision, worktree] = args;
      result = engine.dependencyComplete(admission(bundle, [], {completed_goals, execution_revision}, bundle.repository.root, null, worktree, ''), id); break;
    }
    case 'typed_gate': {
      const [root, bundle, gate, context, files, worktree] = args;
      engine.typedGate(admission(bundle, [], context, root, files, worktree, ''), gate);
      result = null; break;
    }
    case 'worktree_observation': result = engine.worktreeObservation(...args); break;
    case 'worktree_binding': result = engine.worktreeBinding(...args); break;
    case 'worktree_inputs': result = engine.worktreeInputs(...args); break;
    case 'gate_dimensions': result = engine.gateDimensions(...args); break;
    case 'applies': result = engine.applies(...args); break;
    case 'git_read': result = engine.gitRead(...args); break;
    case 'verification': {
      const verification = await import(pathToFileURL(root + '/04-validate-handoff/autobahn/lib/verification.mjs'));
      result = verification.validate(...args).map(({command, argv, cwd}) => [command, argv, cwd]); break;
    }
    default: throw new Error('unsupported bridge operation: ' + operation);
  }
  process.stdout.write(json.dumps({result}, null, true) + '\n');
} catch (error) {
  process.stdout.write(json.dumps({error: error.message, type: error.name, code: error.code ?? null}, null, true) + '\n');
  process.exitCode = 1;
}
