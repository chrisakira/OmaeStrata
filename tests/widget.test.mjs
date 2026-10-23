import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import vm from 'node:vm'

const bar = fs.readFileSync(new URL('../BarWidget.qml', import.meta.url), 'utf8')
const panel = fs.readFileSync(new URL('../Panel.qml', import.meta.url), 'utf8')
const model = {}
vm.createContext(model)
vm.runInContext(fs.readFileSync(new URL('../Model.js', import.meta.url), 'utf8'), model)

test('bar widget QML has no duplicate object ids', () => {
  const ids = [...bar.matchAll(/^\s*id:\s*(\w+)/gm)].map((match) => match[1])
  assert.equal(new Set(ids).size, ids.length, `duplicate ids: ${ids.filter((id, i) => ids.indexOf(id) !== i).join(', ')}`)
})

test('offline and unresolved widget face visibly offers the server start action', () => {
  assert.equal(model.widgetActionLabel({ online: false }, 'ok', 'idle', false), '▶ START')
  assert.equal(model.widgetActionLabel(null, 'connecting', 'idle', false), '▶ START')
  assert.equal(model.widgetActionLabel(null, 'connecting', 'idle', true), '▶')
  assert.equal(model.widgetActionLabel({ online: false }, 'ok', 'starting', false), 'STARTING…')
  assert.equal(model.widgetActionLabel({ online: true }, 'ok', 'stopping', false), 'STOPPING…')
  assert.equal(model.widgetActionLabel({ online: false }, 'ok', 'error', false), '↻ RETRY')
  assert.match(bar, /text:\s*Model\.clean\(root\.widgetLabel,\s*46\)/)
  assert.match(bar, /root\.requestStart\(\)/)
  assert.match(bar, /Model\.stopCommand/)
  assert.match(bar, /connectionMode/)
  assert.match(panel, /root\.stopServer\(\)/)
  assert.match(panel, /text:\s*root\.startLabel/)
  assert.match(panel, /text:\s*root\.stopLabel/)
})

test('background status refresh preserves visible data without checking copy', () => {
  const snapshot = { online: true, model: 'IQ3_S', cpu: 12, gpus: [], timestamp: '12:34:56', error: '' }
  assert.equal(model.compact(snapshot, 'ok', false), '● IQ3_S')
  assert.equal(model.compact(snapshot, 'connecting', false), '● IQ3_S')
  assert.equal(model.statusLabel(snapshot, 'connecting'), '● ONLINE')
  assert.equal(model.tooltip(snapshot, 'connecting'), model.tooltip(snapshot, 'ok'))
  assert.equal(model.compact(null, 'connecting', false), 'Strata · —')
  assert.equal(model.statusLabel(null, 'connecting'), '● —')
  assert.equal(model.tooltip(null, 'connecting'), 'OmaeStrata: status unavailable')
  assert.match(panel, /Model\.statusLabel\(root\.snapshot, root\.stateText\)/)
  assert.doesNotMatch(panel, /CHECKING|Connecting to /)
  assert.match(panel, /textFormat:\s*Text\.PlainText/)
  assert.match(panel, /gen tok\/s|Generation/)
  assert.match(panel, /implicitWidth:\s*parent\.width \* /)
  assert.match(panel, /Model\.memoryPercent\(modelData\)/)
  assert.match(panel, /Model\.tempLabel\(modelData\.temperature\)/)
  assert.match(panel, /Model\.gpuSectionTitle\(index, modelData\.name\)/)
  assert.match(panel, /root\.snapshot\.ram/)
  assert.match(panel, /root\.snapshot\.disk/)
  assert.doesNotMatch(panel, /Model\.memory\(modelData\)/)
})
