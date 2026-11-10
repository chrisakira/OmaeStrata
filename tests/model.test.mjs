import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import vm from 'node:vm'

const context = {}
vm.createContext(context)
vm.runInContext(fs.readFileSync(new URL('../Model.js', import.meta.url), 'utf8'), context)

const online = {
  online: true,
  model: 'bonsai.gguf',
  cpu: 24,
  gpus: [],
  timestamp: '12:34:56',
  error: ''
}

test('SSH failure marks the last successful bar reading stale', () => {
  assert.match(context.compact(online, 'error', false), /STALE/)
  assert.match(context.tooltip(online, 'error'), /SSH ERROR/)
  assert.match(context.tooltip(online, 'error'), /last successful snapshot/i)
  assert.match(context.tooltip(online, 'error'), /12:34:56/)
})

test('vertical bar labels stay short and communicate state', () => {
  assert.equal(context.compact(online, 'ok', true), 'S ON')
  assert.equal(context.compact({ ...online, online: false }, 'ok', true), 'S OFF')
  assert.equal(context.compact(online, 'error', true), 'S ?')
})

test('SSH error with no prior snapshot is not presented as an offline server', () => {
  assert.equal(context.compact(null, 'error', false), 'Strata · SSH?')
  assert.match(context.tooltip(null, 'error'), /SSH ERROR/)
})

test('parses live generation throughput lines', () => {
  const parsed = context.parseThroughputLine('[strata] thinking: 5 of budget 32 tokens, 22.7 tok/s, 2 s')
  assert.equal(parsed.generationTokS, 22.7)
  assert.equal(parsed.prefillTokS, null)
})

test('parses completed request prefill and decode speeds', () => {
  const parsed = context.parseThroughputLine('[strata] request prompt 120 cached 40 output 25 prompt_read 90 ms total 640 ms prefill 888.9 tok/s decode 41.7 tok/s')
  assert.equal(parsed.prefillTokS, 888.9)
  assert.equal(parsed.generationTokS, 41.7)
})

test('parses prompt-eval and generation rates from Strata completion log lines', () => {
  const parsed = context.parseThroughputLine('[strata] eval: prompt 120 tokens = 100 ms + 20 cached 5 ms (1200.0 tok/s), eval time = 500 ms / 25 tokens (50.0 tok/s), total time = 600 ms')
  assert.equal(parsed.prefillTokS, 1200)
  assert.equal(parsed.generationTokS, 50)
})

test('derives the model identifier from the selected Strata log filename', () => {
  assert.equal(context.modelFromLogName('strata-iq3_s.log'), 'IQ3_S')
  assert.equal(context.modelFromLogName('strata-iq2_s.log'), 'IQ2_S')
  assert.equal(context.modelFromLogName('unrelated.log'), '')
})

test('snapshot model identity follows the latest log filename instead of process arguments', () => {
  const parsed = context.parseSnapshot(JSON.stringify({
    ok: true,
    online: true,
    model: 'stale-process-argument.gguf',
    latestLog: 'strata-iq2_s.log',
    generationTokS: 28.5,
    prefillTokS: 1340.2,
    cpu: 12,
    gpus: []
  }))
  assert.equal(parsed.model, 'IQ2_S')
  assert.equal(parsed.generationTokS, 28.5)
  assert.equal(parsed.prefillTokS, 1340.2)
})

test('ignores unrelated server output', () => {
  assert.equal(context.parseThroughputLine('[strata] listening on 0.0.0.0:8080'), null)
})

test('parses log-derived metrics JSON without requiring request content', () => {
  const parsed = context.parseMetricsLine('{"ok":true,"generationTokS":33.2,"prefillTokS":1789.5,"model":"IQ3_S","latestLog":"strata-iq3_s.log"}')
  assert.equal(parsed.generationTokS, 33.2)
  assert.equal(parsed.prefillTokS, 1789.5)
  assert.equal(parsed.model, 'IQ3_S')
  assert.equal(parsed.latestLog, 'strata-iq3_s.log')
  assert.equal(context.parseMetricsLine('{"ok":true,"generationTokS":null,"prefillTokS":null}').generationTokS, null)
})

test('metrics command tails the newest Strata model log over SSH', () => {
  const command = Array.from(context.metricsCommand('akira@192.168.1.168'))
  assert.equal(command[0], 'ssh')
  assert.equal(command.at(-2), 'akira@192.168.1.168')
  assert.match(command.at(-1), /strata-\*\.log/)
  assert.match(command.at(-1), /getmtime/)
  assert.match(command.at(-1), /generationTokS/)
  assert.match(command.at(-1), /prefillTokS/)
  assert.doesNotMatch(command.at(-1), /127\.0\.0\.1:8080\/metrics/)
  assert.match(command.at(-1), /generationTokS/)
})

test('status command selects the model from the newest Strata log', () => {
  const command = Array.from(context.command('akira@192.168.1.168', 'strata'))
  assert.equal(command[0], 'ssh')
  assert.match(command.at(-1), /strata-\*\.log/)
  assert.match(command.at(-1), /getmtime/)
  assert.match(command.at(-1), /latestLog/)
})

test('start command invokes the fixed remote script through non-interactive SSH', () => {
  const command = Array.from(context.startCommand('akira@192.168.1.168'))
  assert.equal(command[0], 'ssh')
  assert.ok(command.includes('BatchMode=yes'))
  assert.deepEqual(command.slice(-2), ['akira@192.168.1.168', '/home/akira/Strata/run-iq3_s.sh'])
})

const metricsHelper = "python3 -u -c import glob,json,os,re,time root='/home/akira/Strata' files=glob.glob(os.path.join(root,'strata-*.log'))"
const statusHelper = "OMAE_STRATA_PATTERN='strata' python3 -c import glob,json,os,re,subprocess,time; pattern=os.environ.get('OMAE_STRATA_PATTERN','strata')"
const serverCmd = '/home/akira/Strata/.venv/bin/python /home/akira/Strata/serve/server.py --engine strata --config /home/akira/Strata/strata-iq3_s.json --port 8080 --open'

test('metrics and status python -c helpers are not a running Strata server', () => {
  assert.equal(context.isStrataProcess(metricsHelper, 'python3', 'strata'), false)
  assert.equal(context.isStrataProcess(statusHelper, 'python3', 'strata'), false)
  assert.equal(context.isStrataProcess('OMAESTRATA_HELPER=1 python3 -u -c print(1)', 'python3', 'strata'), false)
})

test('serve/server.py --engine strata is treated as the running server', () => {
  assert.equal(context.isStrataProcess(serverCmd, 'python', 'strata'), true)
})

const strataPyServe = '/home/sabinho/github/Strata/.venv/bin/python /home/sabinho/github/Strata/strata.py serve --profile strata-coder-iq1_m.json'

test('strata.py serve is treated as the running server', () => {
  assert.equal(context.isStrataProcess(strataPyServe, 'python', 'strata'), true)
})

test('stop command SIGTERMs matching processes over SSH and locally', () => {
  const ssh = Array.from(context.stopCommand('akira@192.168.1.168', 'strata'))
  assert.equal(ssh[0], 'ssh')
  assert.ok(ssh.includes('BatchMode=yes'))
  assert.equal(ssh.at(-2), 'akira@192.168.1.168')
  assert.match(ssh.at(-1), /OMAESTRATA_HELPER=1/)
  assert.match(ssh.at(-1), /SIGTERM/)
  assert.match(ssh.at(-1), /SIGKILL/)
  assert.match(ssh.at(-1), /strata\\.py/)
  const local = Array.from(context.stopCommand('u@h', 'strata', { mode: 'local', strataRoot: '/opt/s', startScript: '/opt/s/run.sh', diskPath: '/' }))
  assert.equal(local[0], 'env')
  assert.ok(local.includes('python3'))
  assert.ok(!local.includes('ssh'))
  assert.ok(local.includes('OMAESTRATA_HELPER=1'))
})

test('status collector skips helpers and matches serve/server.py --engine', () => {
  const remote = Array.from(context.command('akira@192.168.1.168', 'strata')).at(-1)
  assert.match(remote, /os\.getpid/)
  assert.match(remote, /OMAESTRATA_HELPER/)
  assert.match(remote, /serve\/server\.py/)
  assert.match(remote, /python\[0-9\.\]\*/)
  assert.doesNotMatch(remote, /pattern in cmd\.lower\(\)/)
})

test('metrics command marks itself as a helper', () => {
  const remote = Array.from(context.metricsCommand('akira@192.168.1.168')).at(-1)
  assert.match(remote, /OMAESTRATA_HELPER=1/)
})

test('snapshot keeps GPU utilization, memory percent, and temperature', () => {
  const parsed = context.parseSnapshot(JSON.stringify({
    ok: true,
    online: true,
    latestLog: 'strata-iq3_s.log',
    cpu: 8,
    gpus: [{
      name: 'Tesla P100-PCIE-16GB',
      utilization: 12,
      memoryUsed: 4096,
      memoryTotal: 16384,
      temperature: 61
    }]
  }))
  assert.equal(parsed.gpus[0].utilization, 12)
  assert.equal(parsed.gpus[0].temperature, 61)
  assert.equal(context.memoryPercent(parsed.gpus[0]), '25%')
  assert.equal(context.tempLabel(parsed.gpus[0].temperature), '61°C')
  assert.match(context.tooltip(parsed, 'ok'), /12%/)
  assert.match(context.tooltip(parsed, 'ok'), /25%/)
  assert.match(context.tooltip(parsed, 'ok'), /61°C/)
  assert.doesNotMatch(context.tooltip(parsed, 'ok'), /MiB/)
  assert.equal(context.gpuSectionTitle(0, parsed.gpus[0].name), 'GPU 0 · P100')
  assert.equal(context.gpuSectionTitle(1, parsed.gpus[0].name), 'GPU 1 · P100')
})

test('snapshot keeps host RAM and disk usage percents', () => {
  const parsed = context.parseSnapshot(JSON.stringify({
    ok: true,
    online: true,
    latestLog: 'strata-iq3_s.log',
    cpu: 8,
    ram: 41.2,
    disk: 67.5,
    gpus: []
  }))
  assert.equal(parsed.ram, 41.2)
  assert.equal(parsed.disk, 67.5)
  assert.match(context.tooltip(parsed, 'ok'), /RAM: 41%/)
  assert.match(context.tooltip(parsed, 'ok'), /Disk: 68%/)
})

test('status collector reads meminfo and root filesystem usage', () => {
  const remote = Array.from(context.command('akira@192.168.1.168', 'strata')).at(-1)
  assert.match(remote, /MemAvailable/)
  assert.match(remote, /statvfs/)
  assert.match(remote, /ram/)
})

test('status collector queries nvidia-smi temperature', () => {
  const remote = Array.from(context.command('akira@192.168.1.168', 'strata')).at(-1)
  assert.match(remote, /temperature\.gpu/)
  assert.match(remote, /temperature/)
})

test('status collector falls back to rocm-smi and amdgpu sysfs', () => {
  const remote = Array.from(context.command('akira@192.168.1.168', 'strata')).at(-1)
  assert.match(remote, /rocm-smi/)
  assert.match(remote, /gpu_busy_percent/)
  assert.match(remote, /0x1002/)
})

test('parses dotenv assignments and ignores comments', () => {
  const env = context.parseEnv([
    '# comment',
    'SSH_TARGET=user@host',
    'STRATA_ROOT="/opt/strata"',
    "export DISK_PATH=/",
    'START_SCRIPT=/opt/strata/run.sh'
  ].join('\n'))
  assert.equal(env.SSH_TARGET, 'user@host')
  assert.equal(env.STRATA_ROOT, '/opt/strata')
  assert.equal(env.DISK_PATH, '/')
  assert.equal(env.START_SCRIPT, '/opt/strata/run.sh')
})

test('commands take strata root, start script, and disk path from config', () => {
  const cfg = { strataRoot: '/opt/s', startScript: '/opt/s/run.sh', diskPath: '/data' }
  const status = Array.from(context.command('u@h', 'strata', cfg))
  assert.match(status.at(-1), /OMAE_STRATA_ROOT=/)
  assert.match(status.at(-1), /OMAE_DISK_PATH=/)
  assert.doesNotMatch(status.at(-1), /\/home\/akira\/Strata\/strata-\*\.log/)
  const start = Array.from(context.startCommand('u@h', cfg))
  assert.deepEqual(start.slice(-2), ['u@h', '/opt/s/run.sh'])
  const metrics = Array.from(context.metricsCommand('u@h', cfg))
  assert.match(metrics.at(-1), /OMAE_STRATA_ROOT=/)
})

test('local mode runs the collector and start script without SSH', () => {
  const cfg = { mode: 'local', strataRoot: '/opt/s', startScript: '/opt/s/run.sh', diskPath: '/data' }
  const status = Array.from(context.command('u@h', 'strata', cfg))
  assert.equal(status[0], 'env')
  assert.ok(status.includes('python3'))
  assert.ok(!status.includes('ssh'))
  assert.ok(status.some((part) => String(part).indexOf('OMAE_STRATA_ROOT=') === 0))
  const start = Array.from(context.startCommand('u@h', cfg))
  assert.deepEqual(start, ['/opt/s/run.sh'])
  const metrics = Array.from(context.metricsCommand('u@h', cfg))
  assert.equal(metrics[0], 'env')
  assert.ok(metrics.includes('python3'))
  assert.ok(!metrics.includes('ssh'))
})
