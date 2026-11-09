// Exercise installed Harness services directly. No model, credentials or GitHub.
import { createRequire } from 'node:module';
import { pathToFileURL, fileURLToPath } from 'node:url';
import { resolve, dirname } from 'node:path';
import { spawnSync } from 'node:child_process';
import { existsSync, unlinkSync } from 'node:fs';

const runtime = resolve(process.argv[2]);
const python = process.argv[3];
const require = createRequire(resolve(runtime, 'package.json'));
const load = name => import(pathToFileURL(require.resolve(name)).href);
const { Context } = await load('@deepseek-ai/cordis');
const output = {};
// A tripwire for unexpected use of global fetch by these local-only services.
// This is an observation aid, not an OS network sandbox.
globalThis.fetch = async () => { throw new Error('NETWORK_FORBIDDEN_IN_PREPARATION_PROBE'); };

const sandboxContext = new Context();
try {
  const { default: Sandbox } = await load('@deepseek-ai/dsh-sandbox-local');
  const { probe } = await load('@deepseek-ai/node-addon-system/landlock-run');
  output.landlock = probe();
  await sandboxContext.plugin(Sandbox);
  const wrapped = await sandboxContext.sandbox.confine(
    ['true'], { mode: 'read-only', workspaceRoot: process.cwd() });
  const check = spawnSync(wrapped.argv[0], wrapped.argv.slice(1), { timeout: 5000, encoding: 'utf8' });
  output.sandbox = { state: check.status === 0 ? 'AVAILABLE' : 'FAILED',
    enforcement: wrapped.enforcement, exit_code: check.status, stderr: check.stderr };
  // The source tree is outside the temporary working directory supplied by probe.py.
  // A successful sandbox must reject this exact, otherwise harmless write.
  const deniedPath = resolve(dirname(fileURLToPath(import.meta.url)), '.sandbox-escape-probe');
  try {
    const denied = await sandboxContext.sandbox.confine(
      ['/bin/sh', '-c', 'printf ESCAPED > "$1"', 'probe', deniedPath],
      { mode: 'read-only', workspaceRoot: process.cwd() });
    const attempt = spawnSync(denied.argv[0], denied.argv.slice(1),
      { timeout: 5000, encoding: 'utf8' });
    const explicitDenial = /read-only file system|permission denied|operation not permitted/i
      .test(attempt.stderr ?? '');
    output.sandbox.external_write = {
      rejected: attempt.status !== 0 && !attempt.error && explicitDenial && !existsSync(deniedPath),
      exit_code: attempt.status,
      stderr: attempt.stderr.replaceAll(deniedPath, '<READ_ONLY_SOURCE>'),
    };
  } finally {
    // Only our dedicated sentinel may be removed, if the sandbox unexpectedly fails.
    if (existsSync(deniedPath)) unlinkSync(deniedPath);
  }
} catch (error) {
  output.sandbox = { state: 'UNAVAILABLE', code: error.code, message: error.message };
} finally {
  await sandboxContext.fiber.dispose();
}

const ctx = new Context();
try {
  const { default: SystemPrompt } = await load('@deepseek-ai/dsh-system-prompt');
  const { default: ToolRuntime } = await load('@deepseek-ai/dsh-tools');
  const { apply, Config } = await load('@deepseek-ai/dsh-mcp-client');
  await ctx.plugin(SystemPrompt);
  await ctx.plugin(ToolRuntime);
  const config = Config({
    serverName: 'preparation', transport: 'stdio', command: python,
    args: [resolve(dirname(fileURLToPath(import.meta.url)), 'mcp_fixture.py')],
    cwd: process.cwd(), toolCallTimeoutMs: 5000, failOnStartupError: true,
    reconnect: { enabled: false },
  });
  await ctx.plugin({ name: 'convoy-preparation-mcp', inject: ['tools'], apply }, config);
  const names = ctx.tools.schemas().map(tool => tool.name);
  const result = await ctx.tools.execute({
    name: 'mcp__preparation__read_sentinel', arguments: {}, callId: 'preparation-probe',
    signal: AbortSignal.timeout(5000),
  });
  const ok = !result.isError && JSON.stringify(result.value).includes('CONVOY_PREPARATION_MCP_OK');
  output.mcp = { state: ok ? 'PASS' : 'FAIL', tools: names, result };
} catch (error) {
  output.mcp = { state: 'FAIL', message: error.message };
} finally {
  await ctx.fiber.dispose();
}
console.log(JSON.stringify(output, null, 2));
process.exitCode = output.mcp?.state === 'PASS' &&
  output.sandbox?.state === 'AVAILABLE' &&
  output.sandbox?.enforcement === 'full' &&
  output.sandbox?.external_write?.rejected ? 0 : 1;
