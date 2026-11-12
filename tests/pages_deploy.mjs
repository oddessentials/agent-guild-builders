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
assert.match(workflow, /if: github.event.workflow_run.event == 'push' && github.event.workflow_run.conclusion == 'success'/);
assert.equal(workflow.match(/ref: \$\{\{ github.event.workflow_run.head_sha \}\}/g)?.length, 2);
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
  if [ "$*" != "api repos/example/builders/releases/latest --jq .tag_name" ]; then
    return 97
  fi
  if [ "$API_ERROR" != 0 ]; then
    echo 'simulated API failure' >&2
    return "$API_ERROR"
  fi
  printf '%s\\n' "$LATEST_TAG"
}
`;
function run(latest, error = 0) {
  fs.writeFileSync(output, '');
  fs.writeFileSync(calls, '');
  const result = spawnSync(bash, ['--noprofile', '--norc', '-eo', 'pipefail', '-c', stub + script], {
    encoding: 'utf8', timeout: 10000,
    env: { ...process.env, GH_REPO: 'example/builders', RELEASE_TAG: 'build-100', LATEST_TAG: latest,
      API_ERROR: String(error), GITHUB_OUTPUT: output.replaceAll('\\', '/'), CALLS: calls.replaceAll('\\', '/') },
  });
  assert.ifError(result.error);
  assert.equal(fs.readFileSync(calls, 'utf8'), 'api repos/example/builders/releases/latest --jq .tag_name\n');
  const outputs = fs.readFileSync(output, 'utf8');
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
  console.log('ok   the release gate, pinned checkouts and smoke assertions remain');
} finally {
  assert.equal(path.dirname(root), path.resolve(os.tmpdir()));
  assert.ok(path.basename(root).startsWith('agb-pages-'));
  fs.rmSync(root, { recursive: true, force: true });
}
