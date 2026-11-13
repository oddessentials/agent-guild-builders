import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const workflow = fs.readFileSync(new URL('../.github/workflows/pages.yml', import.meta.url), 'utf8').replaceAll('\r\n', '\n');
const deploy = workflow.split('\n  deploy:\n')[1];
assert.ok(deploy, 'the deployment job exists');
const steps = deploy.split(/^      - /m).slice(1);
const guardIndex = steps.findIndex((step) => step.includes('id: latest_release\n'));
assert.ok(guardIndex >= 0, 'the latest-release guard exists');
const guard = steps[guardIndex];
assert.match(guard, /shell: bash\n/);
assert.match(guard, /GH_TOKEN: \$\{\{ github.token \}\}/);
assert.match(guard, /GH_REPO: \$\{\{ github.repository \}\}/);
assert.match(guard, /RELEASE_TAG: build-\$\{\{ github.event.workflow_run.run_number \}\}/);
const condition = "if: steps.latest_release.outputs.deploy == 'true'";
assert.ok(steps[guardIndex + 1].includes('uses: actions/deploy-pages@'));
assert.ok(steps[guardIndex + 1].includes(condition), 'deployment is guarded immediately before it runs');
assert.ok(steps.find((step) => step.startsWith('name: Check the published page\n')).includes(condition));
assert.match(deploy, /needs: check\n/);
assert.match(deploy, /permissions:\n      contents: read\n/);
assert.match(workflow, /\n  workflow_dispatch:\n/);
assert.ok(workflow.includes(`    if: >-
      (github.event_name == 'workflow_run' && github.event.workflow_run.event == 'push' && github.event.workflow_run.conclusion == 'success')
      || (github.event_name == 'workflow_dispatch' && github.ref == 'refs/heads/main')
`));
assert.match(deploy, /^    if: github.event_name == 'workflow_run' \|\| github.event_name == 'workflow_dispatch'\n/);
assert.equal(workflow.match(/ref: \$\{\{ github.event.workflow_run.head_sha \|\| github.sha \}\}/g)?.length, 2);
assert.ok(workflow.includes("RELEASE_TAG: ${{ github.event_name == 'workflow_run' && format('build-{0}', github.event.workflow_run.run_number) || '' }}"));
assert.ok(workflow.includes("$env:RELEASE_TAG -notmatch '^build-[0-9]+$'"));
assert.ok(workflow.includes('$latest.Replace(\'/latest/download/\', "/download/$env:RELEASE_TAG/")'));
assert.ok(workflow.includes('./tests/site_check.ps1 -Page $pagePath'));
assert.ok(workflow.includes('cmp -s "published-$file" "build/site/$file"'));
const script = guard.split('        run: |\n')[1]?.replace(/^          /gm, '');
assert.ok(script, 'the actual guard shell script is extracted');
const bash = process.env.BASH ?? (process.platform === 'win32' ? path.join(process.env.ProgramFiles, 'Git/bin/bash.exe') : 'bash');
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'agb-pages-'));
const output = path.join(root, 'output');
const calls = path.join(root, 'calls');
const stub = `
gh() {
  printf '%s\\n' "$*" >> "$CALLS"
  if [ "$*" != "$EXPECTED_CALL" ]; then
    return 97
  fi
  if [ "$API_ERROR" != 0 ]; then
    echo 'simulated API failure' >&2
    return "$API_ERROR"
  fi
  printf '%s\\n' "$API_VALUE"
}
`;
const sha = 'a'.repeat(40);
function call(event, value, error) {
  fs.writeFileSync(output, '');
  fs.writeFileSync(calls, '');
  const expected = event === 'workflow_dispatch'
    ? 'api repos/example/builders/commits/main --jq .sha'
    : 'api repos/example/builders/releases/latest --jq .tag_name';
  const result = spawnSync(bash, ['--noprofile', '--norc', '-eo', 'pipefail', '-c', stub + script], {
    encoding: 'utf8', timeout: 10000,
    env: { ...process.env, GITHUB_EVENT_NAME: event, GITHUB_SHA: sha, GH_REPO: 'example/builders', RELEASE_TAG: 'build-100',
      EXPECTED_CALL: expected, API_VALUE: value, API_ERROR: String(error),
      GITHUB_OUTPUT: output.replaceAll('\\', '/'), CALLS: calls.replaceAll('\\', '/') },
  });
  assert.ifError(result.error);
  assert.equal(fs.readFileSync(calls, 'utf8'), `${expected}\n`);
  return { result, outputs: fs.readFileSync(output, 'utf8') };
}
function dispatch(head, error = 0) {
  const { result, outputs } = call('workflow_dispatch', head, error);
  if (error) {
    assert.equal(result.status, error, result.stderr);
    assert.equal(outputs, '', 'an API error must not authorize deployment');
  } else {
    assert.equal(result.status, 0, result.stderr);
    assert.equal(outputs, `deploy=${head === sha}\n`);
    if (head !== sha) assert.match(result.stdout, /::notice::Skipping a{40}; main is now at /);
  }
}
function run(latest, error = 0) {
  const { result, outputs } = call('workflow_run', latest, error);
  if (error) {
    assert.equal(result.status, error, result.stderr);
    assert.equal(outputs, '', 'an API error must not authorize deployment');
  } else {
    assert.equal(result.status, 0, result.stderr);
    assert.equal(outputs, `deploy=${latest === 'build-100'}\n`);
    if (latest !== 'build-100') assert.match(result.stdout, /::notice::Skipping build-100;/);
  }
}
try {
  run('build-100');
  console.log('ok   the current release deploys');
  run('build-101');
  console.log('ok   a rerun of an older release skips deployment and the published-page check');
  run('build-100');
  run('build-102');
  console.log('ok   the final guard reads latest again after it changes');
  run('build-100', 1);
  run('build-100', 4);
  run('');
  console.log('ok   API failures and an empty latest tag never authorize deployment');
  dispatch(sha);
  console.log('ok   a manual run deploys while its commit is still the head of main');
  dispatch('b'.repeat(40));
  dispatch('');
  console.log('ok   a manual run skips once main has moved on');
  dispatch(sha, 1);
  dispatch(sha, 4);
  console.log('ok   API failures never authorize a manual deployment');
  console.log('ok   the release gate, pinned checkouts and smoke assertions remain');
} finally {
  assert.equal(path.dirname(root), path.resolve(os.tmpdir()));
  assert.ok(path.basename(root).startsWith('agb-pages-'));
  fs.rmSync(root, { recursive: true, force: true });
}
