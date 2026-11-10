function clean(value, maxLength) {
  var s = String(value === undefined || value === null ? "" : value)
  s = s.replace(/[\x00-\x1f\x7f]/g, " ").replace(/[<>]/g, "")
  s = s.replace(/\s+/g, " ").replace(/^\s+|\s+$/g, "")
  return s.slice(0, maxLength || 160)
}

function isHelperProcess(cmd) {
  var line = String(cmd || "")
  if (line.indexOf("OMAESTRATA_HELPER") !== -1) return true
  if (/\bpython[0-9.]*\s+(?:-[^\s]+\s+)*-c\b/.test(line)) return true
  if (/\b(?:bash|sh)\s+-c\b/.test(line)) return true
  return false
}

function isStrataProcess(cmd, comm, pattern) {
  var needle = String(pattern || "strata").toLowerCase()
  if (!needle || isHelperProcess(cmd)) return false
  var line = String(cmd || "")
  if (String(comm || "").toLowerCase() === needle) return true
  if (/\bserve\/server\.py\b/.test(line) && line.toLowerCase().indexOf("--engine " + needle) !== -1) return true
  if (/(?:^|[\/\s])strata\.py(?:\s|$)/.test(line) && /\bserve\b/.test(line)) return true
  var tokens = line.split(/\s+/)
  for (var i = 0; i < tokens.length && i < 12; i++) {
    var base = tokens[i].split("/").pop().toLowerCase()
    if (base === needle) return true
  }
  return false
}

function parseSnapshot(raw) {
  try {
    var d = JSON.parse(String(raw || "").slice(0, 65536))
    if (!d || d.ok !== true) return null
    var gpus = []
    var rows = d.gpus || []
    for (var i = 0; i < rows.length && i < 8; i++) {
      var g = rows[i] || {}
      gpus.push({
        name: clean(g.name || "GPU", 48),
        utilization: numberOrNull(g.utilization),
        memoryUsed: numberOrNull(g.memoryUsed),
        memoryTotal: numberOrNull(g.memoryTotal),
        temperature: numberOrNull(g.temperature)
      })
    }
    var latestLog = clean(d.latestLog || "", 72)
    return {
      online: !!d.online,
      model: modelFromLogName(latestLog) || clean(d.model || "Model not reported", 112),
      latestLog: latestLog,
      generationTokS: optionalNumberOrNull(d.generationTokS),
      prefillTokS: optionalNumberOrNull(d.prefillTokS),
      cpu: numberOrNull(d.cpu),
      ram: numberOrNull(d.ram),
      disk: numberOrNull(d.disk),
      gpus: gpus,
      timestamp: clean(d.timestamp || "", 32),
      error: clean(d.error || "", 100)
    }
  } catch (e) { return null }
}

function numberOrNull(x) {
  var n = Number(x)
  return isFinite(n) ? n : null
}

function percent(x) { return x === null || x === undefined ? "—" : Math.max(0, Math.min(100, Math.round(x))) + "%" }
function fillRatio(value, total) {
  if (total === undefined) {
    var n = Number(value)
    return isFinite(n) ? Math.max(0, Math.min(1, n / 100)) : 0
  }
  var used = Number(value)
  var max = Number(total)
  if (!isFinite(used) || !isFinite(max) || max <= 0) return 0
  return Math.max(0, Math.min(1, used / max))
}
function gpuShortName(name) {
  var raw = String(name || "GPU")
  var m = /(H100|A100|P100|RTX\s?\d+|RX\s?\d+)/i.exec(raw)
  return clean(m ? m[1].replace(/\s+/g, "") : raw, 18)
}
function gpuSectionTitle(index, name) {
  return "GPU " + String(index) + " · " + gpuShortName(name)
}
function memory(g) {
  if (g.memoryUsed === null || g.memoryTotal === null) return ""
  return Math.round(g.memoryUsed) + "/" + Math.round(g.memoryTotal) + " MiB"
}
function memoryPercent(g) {
  if (!g || g.memoryUsed === null || g.memoryUsed === undefined || g.memoryTotal === null || g.memoryTotal === undefined || Number(g.memoryTotal) <= 0) return "—"
  return percent(100 * Number(g.memoryUsed) / Number(g.memoryTotal))
}
function tempLabel(value) {
  if (value === null || value === undefined) return "—"
  var n = Number(value)
  return isFinite(n) ? Math.round(n) + "°C" : "—"
}
function compact(s, state, vertical) {
  if (state === "error") return vertical ? "S ?" : (s ? "Strata · STALE" : "Strata · SSH?")
  if (!s) return vertical ? "S —" : "Strata · —"
  if (vertical) return s.online ? "S ON" : "S OFF"
  if (!s.online) return "Strata · OFF"
  return "● " + (s.model || "ON")
}

function statusLabel(s, state) {
  if (state === "error") return "● SSH ERROR"
  if (!s) return "● —"
  return s.online ? "● ONLINE" : "● OFFLINE"
}

function widgetActionLabel(s, state, launchState, vertical) {
  if (launchState === "starting") return vertical ? "◌" : "STARTING…"
  if (launchState === "stopping") return vertical ? "■" : "STOPPING…"
  if (launchState === "error") return vertical ? "↻" : "↻ RETRY"
  if (state === "connecting" && !s) return vertical ? "▶" : "▶ START"
  if (s && s.online) return compact(s, state, vertical)
  return vertical ? "▶" : "▶ START"
}

function tooltip(s, state) {
  if (state === "error" && !s) return "OmaeStrata: SSH ERROR — no successful status snapshot yet"
  if (!s) return "OmaeStrata: status unavailable"
  var stale = state === "error"
  var prefix = stale ? "SSH ERROR — last successful snapshot" + (s.timestamp ? " at " + s.timestamp : "") : "Strata status"
  var lines = [prefix, (stale ? "Last known Strata: " : "Strata: ") + (s.online ? "ON" : "OFF"), (stale ? "Last known model: " : "Model: ") + (s.online ? s.model : "—"), (stale ? "Last known CPU: " : "CPU: ") + percent(s.cpu), (stale ? "Last known RAM: " : "RAM: ") + percent(s.ram), (stale ? "Last known Disk: " : "Disk: ") + percent(s.disk)]
  for (var i = 0; i < s.gpus.length; i++) {
    var g = s.gpus[i]
    lines.push((stale ? "Last known " : "") + gpuSectionTitle(i, g.name) + ": " + percent(g.utilization) + " · MEM " + memoryPercent(g) + " · " + tempLabel(g.temperature))
  }
  if (s.error) lines.push("GPU metrics: " + s.error)
  return lines.join("\n")
}

function parseThroughputLine(raw) {
  var line = String(raw || "").replace(/\x1b\[[0-9;]*[A-Za-z]/g, "").slice(0, 1024)
  if (!/^\[strata\]\s*/i.test(line)) return null

  var request = /\bprefill\s+(\d+(?:\.\d+)?)\s+tok\/s\s+decode\s+(\d+(?:\.\d+)?)\s+tok\/s\b/i.exec(line)
  if (request) return { generationTokS: numberOrNull(request[2]), prefillTokS: numberOrNull(request[1]) }

  var promptSummary = /\bprompt\s+\d+\s+tokens?\s*=/i.test(line)
  var rates = line.match(/\d+(?:\.\d+)?(?=\s+tok\/s\b)/ig) || []
  if (promptSummary && rates.length >= 2) return { generationTokS: numberOrNull(rates[1]), prefillTokS: numberOrNull(rates[0]) }

  var live = /^\[strata\]\s+[^:]+:.*?,\s*(\d+(?:\.\d+)?)\s+tok\/s,\s*\d+\s+s\b/i.exec(line)
  if (live) return { generationTokS: numberOrNull(live[1]), prefillTokS: null }

  var completed = /^\[strata\]\s+done:.*?\((\d+(?:\.\d+)?)\s+tok\/s\)/i.exec(line)
  if (completed) return { generationTokS: numberOrNull(completed[1]), prefillTokS: null }
  return null
}

// Remote collector uses /proc for process and CPU state, selects the newest
// Strata model log for model identity, and invokes nvidia-smi for GPU metrics.
// Keep this string static: configuration is passed as separate argv values.
var REMOTE_PYTHON = [
  "import glob,json,os,re,subprocess,time",
  "pattern=os.environ.get('OMAE_STRATA_PATTERN','strata').lower()",
  "self_pid=str(os.getpid())",
  "py_re=re.compile(r'python[0-9.]*\\s+(?:-[^\\s]+\\s+)*-c\\b')",
  "sh_re=re.compile(r'(?:bash|sh)\\s+-c\\b')",
  "def is_helper(cmd):",
  " return ('OMAESTRATA_HELPER' in cmd) or bool(py_re.search(cmd) or sh_re.search(cmd))",
  "def is_strata(cmd, comm):",
  " if is_helper(cmd): return False",
  " if comm.lower()==pattern: return True",
  " if 'serve/server.py' in cmd and ('--engine '+pattern) in cmd.lower(): return True",
  " if re.search(r'(?:^|[/\\s])strata\\.py(?:\\s|$)', cmd) and re.search(r'\\bserve\\b', cmd): return True",
  " return any(os.path.basename(tok).lower()==pattern for tok in cmd.split()[:12])",
  "procs=[]",
  "for p in os.listdir('/proc'):",
  " if not p.isdigit() or p==self_pid: continue",
  " try:",
  "  cmd=open('/proc/'+p+'/cmdline','rb').read().replace(bytes([0]),b' ').decode(errors='replace').strip()",
  "  comm=open('/proc/'+p+'/comm','r',errors='replace').read().strip()",
  "  if is_strata(cmd, comm): procs.append(cmd)",
  " except: pass",
  "model=''",
  "if procs:",
  " for c in procs:",
  "  m=re.search(r'(?:--model(?:=|\\s+)|-m\\s+)([^\\s]+)',c)",
  "  if m: model=os.path.basename(m.group(1)); break",
  " if not model:",
  "  m=re.search(r'([^\\s]+\\.(?:gguf|safetensors|bin))',procs[0],re.I); model=os.path.basename(m.group(1)) if m else 'Running (model not parsed)'",
  "logs=glob.glob(os.path.join(os.environ.get('OMAE_STRATA_ROOT','/home/akira/Strata'),'strata-*.log'))",
  "latest_log=max(logs,key=os.path.getmtime) if logs else ''",
  "log_model=os.path.basename(latest_log)[7:-4].upper() if latest_log else ''",
  "if log_model: model=log_model",
  "cpu=None",
  "try:",
  " vals=list(map(int,open('/proc/stat').readline().split()[1:])); idle=vals[3]+(vals[4] if len(vals)>4 else 0); total=sum(vals); time.sleep(.18); vals2=list(map(int,open('/proc/stat').readline().split()[1:])); idle2=vals2[3]+(vals2[4] if len(vals2)>4 else 0); total2=sum(vals2); cpu=round(100*(1-(idle2-idle)/max(1,total2-total)),1)",
  "except: pass",
  "ram=None",
  "try:",
  " info={}",
  " for line in open('/proc/meminfo'):",
  "  parts=line.split(); info[parts[0].rstrip(':')]=int(parts[1])",
  " total=info.get('MemTotal') or 0; avail=info.get('MemAvailable', info.get('MemFree', 0)); ram=round(100*(1-avail/max(1,total)),1)",
  "except: pass",
  "disk=None",
  "try:",
  " st=os.statvfs(os.environ.get('OMAE_DISK_PATH','/')); total=st.f_frsize*st.f_blocks; free=st.f_frsize*st.f_bavail; disk=round(100*(1-free/max(1,total)),1)",
  "except: pass",
  "gpus=[]; err=''",
  "try:",
  " out=subprocess.check_output(['nvidia-smi','--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu','--format=csv,noheader,nounits'],stderr=subprocess.STDOUT,text=True,timeout=3)",
  " for line in out.strip().splitlines():",
  "  parts=[x.strip() for x in line.split(',')]; gpus.append({'name':parts[0],'utilization':float(parts[1]),'memoryUsed':float(parts[2]),'memoryTotal':float(parts[3]),'temperature':float(parts[4]) if len(parts)>4 else None})",
  "except Exception as e: err=str(e)[:100]",
  "def fnum(x):",
  " try: return float(x)",
  " except: return None",
  "if not gpus:",
  " try:",
  "  out=subprocess.check_output(['rocm-smi','--json','--showuse','--showmeminfo','vram','--showtemp','--showproductname'],stderr=subprocess.DEVNULL,text=True,timeout=5)",
  "  data=json.loads(out)",
  "  for v in data.values():",
  "   if not isinstance(v,dict): continue",
  "   used=fnum(v.get('VRAM Total Used Memory (B)')); total=fnum(v.get('VRAM Total Memory (B)'))",
  "   gpus.append({'name':v.get('Card Series') or 'AMD GPU','utilization':fnum(v.get('GPU use (%)')),'memoryUsed':None if used is None else used/1048576.0,'memoryTotal':None if total is None else total/1048576.0,'temperature':fnum(v.get('Temperature (Sensor edge) (C)'))})",
  "  if gpus: err=''",
  " except Exception as e:",
  "  if not gpus: err=str(e)[:100]",
  "if not gpus:",
  " try:",
  "  for card in sorted(glob.glob('/sys/class/drm/card[0-9]')):",
  "   dev=os.path.join(card,'device'); vp=os.path.join(dev,'vendor')",
  "   if not os.path.exists(vp) or open(vp).read().strip()!='0x1002': continue",
  "   def rd(n):",
  "    p=os.path.join(dev,n); return open(p).read().strip() if os.path.exists(p) else ''",
  "   used=fnum(rd('mem_info_vram_used')); total=fnum(rd('mem_info_vram_total'))",
  "   temps=glob.glob(os.path.join(dev,'hwmon/hwmon*/temp1_input')); temp=fnum(open(temps[0]).read())/1000.0 if temps else None",
  "   gpus.append({'name':'AMD GPU','utilization':fnum(rd('gpu_busy_percent')),'memoryUsed':None if used is None else used/1048576.0,'memoryTotal':None if total is None else total/1048576.0,'temperature':temp})",
  "  if gpus: err=''",
  " except Exception as e:",
  "  if not gpus: err=str(e)[:100]",
  "print(json.dumps({'ok':True,'online':bool(procs),'model':model,'latestLog':os.path.basename(latest_log) if latest_log else '', 'cpu':cpu,'ram':ram,'disk':disk,'gpus':gpus,'error':err,'timestamp':time.strftime('%H:%M:%S')}))"
].join("\n")

function parseMetricsLine(raw) {
  try {
    var d = JSON.parse(String(raw || ""))
    if (!d || d.ok !== true) return null
    var latestLog = clean(d.latestLog || "", 72)
    return {
      generationTokS: optionalNumberOrNull(d.generationTokS),
      prefillTokS: optionalNumberOrNull(d.prefillTokS),
      model: modelFromLogName(latestLog) || clean(d.model || "", 112),
      latestLog: latestLog
    }
  } catch (e) { return null }
}

function modelFromLogName(filename) {
  var match = /^strata-([A-Za-z0-9_.-]+)\.log$/i.exec(String(filename || ""))
  return match ? clean(match[1], 72).toUpperCase() : ""
}

function optionalNumberOrNull(value) {
  return value === null || value === undefined ? null : numberOrNull(value)
}

var REMOTE_METRICS_PYTHON = [
  "import glob,json,os,re,time",
  "root=os.environ.get('OMAE_STRATA_ROOT','/home/akira/Strata')",
  "while True:",
  " try:",
  "  files=glob.glob(os.path.join(root,'strata-*.log'))",
  "  if not files: raise FileNotFoundError('no Strata model log')",
  "  path=max(files,key=os.path.getmtime)",
  "  with open(path,'rb') as f:",
  "   f.seek(max(0,os.path.getsize(path)-262144))",
  "   lines=f.read().decode('utf-8','replace').splitlines()",
  "  generation=None; prefill=None",
  "  for line in reversed(lines):",
  "   line=re.sub(r'\\x1b\\[[0-9;]*[A-Za-z]','',line)",
  "   rates=re.findall(r'(\\d+(?:\\.\\d+)?)\\s+tok/s\\b',line,re.I)",
  "   explicit=re.search(r'\\bprefill\\s+(\\d+(?:\\.\\d+)?)\\s+tok/s\\s+decode\\s+(\\d+(?:\\.\\d+)?)\\s+tok/s\\b',line,re.I)",
  "   if explicit:",
  "    if prefill is None: prefill=float(explicit.group(1))",
  "    if generation is None: generation=float(explicit.group(2))",
  "   elif re.search(r'\\bprompt\\s+\\d+\\s+tokens?\\s*=',line,re.I) and len(rates)>=2:",
  "    if prefill is None: prefill=float(rates[0])",
  "    if generation is None: generation=float(rates[1])",
  "   elif rates and generation is None:",
  "    generation=float(rates[-1])",
  "   if generation is not None and prefill is not None: break",
  "  filename=os.path.basename(path)",
  "  model=filename[len('strata-'):-len('.log')].upper()",
  "  print(json.dumps({'ok':True,'generationTokS':generation,'prefillTokS':prefill,'model':model,'latestLog':filename},separators=(',',':')),flush=True)",
  " except Exception:",
  "  print('{}',flush=True)",
  " time.sleep(1)"
].join("\n")

function metricsCommand(target, cfg) {
  var conf = configFrom(cfg)
  if (conf.mode === "local") {
    return ["env", "OMAESTRATA_HELPER=1", "OMAE_STRATA_ROOT=" + conf.strataRoot, "python3", "-u", "-c", REMOTE_METRICS_PYTHON]
  }
  var remote = "OMAESTRATA_HELPER=1 OMAE_STRATA_ROOT=" + shellQuote(conf.strataRoot) + " python3 -u -c " + shellQuote(REMOTE_METRICS_PYTHON)
  return ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=3", "--", String(target || "akira@192.168.1.168"), remote]
}

function startCommand(target, cfg) {
  var conf = configFrom(cfg)
  if (conf.mode === "local") return [conf.startScript]
  return ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=3", "--", String(target || "akira@192.168.1.168"), conf.startScript]
}

var STOP_PYTHON = [
  "import os,re,signal,time",
  "pattern=os.environ.get('OMAE_STRATA_PATTERN','strata').lower()",
  "self_pid=str(os.getpid())",
  "py_re=re.compile(r'python[0-9.]*\\s+(?:-[^\\s]+\\s+)*-c\\b')",
  "sh_re=re.compile(r'(?:bash|sh)\\s+-c\\b')",
  "def is_helper(cmd):",
  " return ('OMAESTRATA_HELPER' in cmd) or bool(py_re.search(cmd) or sh_re.search(cmd))",
  "def is_strata(cmd, comm):",
  " if is_helper(cmd): return False",
  " if comm.lower()==pattern: return True",
  " if 'serve/server.py' in cmd and ('--engine '+pattern) in cmd.lower(): return True",
  " if re.search(r'(?:^|[/\\s])strata\\.py(?:\\s|$)', cmd) and re.search(r'\\bserve\\b', cmd): return True",
  " return any(os.path.basename(tok).lower()==pattern for tok in cmd.split()[:12])",
  "pids=[]",
  "for p in os.listdir('/proc'):",
  " if not p.isdigit() or p==self_pid: continue",
  " try:",
  "  cmd=open('/proc/'+p+'/cmdline','rb').read().replace(bytes([0]),b' ').decode(errors='replace').strip()",
  "  comm=open('/proc/'+p+'/comm','r',errors='replace').read().strip()",
  "  if is_strata(cmd, comm): pids.append(int(p))",
  " except: pass",
  "for pid in pids:",
  " try: os.kill(pid, signal.SIGTERM)",
  " except: pass",
  "deadline=time.time()+3",
  "while time.time()<deadline:",
  " alive=[pid for pid in pids if os.path.exists('/proc/'+str(pid))]",
  " if not alive: break",
  " time.sleep(0.2)",
  "for pid in pids:",
  " try:",
  "  if os.path.exists('/proc/'+str(pid)): os.kill(pid, signal.SIGKILL)",
  " except: pass",
  "print('ok')"
].join("\n")

function stopCommand(target, pattern, cfg) {
  var conf = configFrom(cfg)
  var patternSafe = String(pattern || "strata").replace(/[^A-Za-z0-9_.-]/g, "")
  if (conf.mode === "local") {
    return ["env", "OMAESTRATA_HELPER=1", "OMAE_STRATA_PATTERN=" + patternSafe, "python3", "-c", STOP_PYTHON]
  }
  var remote = "OMAESTRATA_HELPER=1 OMAE_STRATA_PATTERN='" + patternSafe + "' python3 -c " + shellQuote(STOP_PYTHON)
  return ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=3", "--", String(target || "akira@192.168.1.168"), remote]
}

function command(target, pattern, cfg) {
  var conf = configFrom(cfg)
  var patternSafe = String(pattern || "strata").replace(/[^A-Za-z0-9_.-]/g, "")
  if (conf.mode === "local") {
    return ["env", "OMAE_STRATA_PATTERN=" + patternSafe, "OMAE_STRATA_ROOT=" + conf.strataRoot, "OMAE_DISK_PATH=" + conf.diskPath, "python3", "-c", REMOTE_PYTHON]
  }
  var remote = "OMAE_STRATA_PATTERN='" + patternSafe + "' OMAE_STRATA_ROOT=" + shellQuote(conf.strataRoot) + " OMAE_DISK_PATH=" + shellQuote(conf.diskPath) + " python3 -c " + shellQuote(REMOTE_PYTHON)
  return ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=4", "-o", "ServerAliveInterval=4", "-o", "ServerAliveCountMax=1", "--", String(target || "akira@192.168.1.168"), remote]
}

function shellQuote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

function parseEnv(raw) {
  var out = {}
  var lines = String(raw || "").slice(0, 8192).split(/\r?\n/)
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].replace(/^\s+/, "")
    if (!line || line.charAt(0) === "#") continue
    if (line.indexOf("export ") === 0) line = line.slice(7)
    var eq = line.indexOf("=")
    if (eq < 1) continue
    var key = line.slice(0, eq).replace(/\s+$/g, "")
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) continue
    var val = line.slice(eq + 1).replace(/^\s+|\s+$/g, "")
    if ((val.charAt(0) === "\"" && val.charAt(val.length - 1) === "\"") || (val.charAt(0) === "'" && val.charAt(val.length - 1) === "'")) val = val.slice(1, -1)
    out[key] = val.replace(/[\x00-\x1f\x7f]/g, "").slice(0, 240)
  }
  return out
}

function pick(env, key, fallback) {
  if (!env) return fallback
  var value = env[key]
  if (value === undefined || value === null || String(value) === "") return fallback
  return String(value)
}

function preferCustom(settingVal, envVal, fallback) {
  var setting = String(settingVal === undefined || settingVal === null ? "" : settingVal)
  var env = String(envVal === undefined || envVal === null ? "" : envVal)
  var def = String(fallback || "")
  if (setting && setting !== def) return setting
  if (env) return env
  return setting || def
}

function sanitizeRemotePath(value, fallback) {
  var s = String(value || "")
  if (!s || s.charAt(0) !== "/" || s.indexOf("..") !== -1 || /[^A-Za-z0-9_./+-]/.test(s)) return fallback
  return s.slice(0, 240)
}

function sanitizeSshTarget(value, fallback) {
  var s = String(value || "")
  if (!s || /[^A-Za-z0-9_.@%:-]/.test(s)) return fallback
  return s.slice(0, 120)
}

function configFrom(cfg) {
  cfg = cfg || {}
  return {
    mode: String(cfg.mode || "ssh").toLowerCase() === "local" ? "local" : "ssh",
    strataRoot: sanitizeRemotePath(cfg.strataRoot, "/home/akira/Strata"),
    startScript: sanitizeRemotePath(cfg.startScript, "/home/akira/Strata/run-iq3_s.sh"),
    diskPath: sanitizeRemotePath(cfg.diskPath, "/")
  }
}
