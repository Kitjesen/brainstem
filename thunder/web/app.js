"use strict";

(() => {
  const $ = (id) => document.getElementById(id);
  const axes = ["vx", "vy", "yaw"];
  const motionButtons = [...document.querySelectorAll("[data-motion]")];
  const modelButtons = [...document.querySelectorAll("[data-slot]")];
  const keyDirections = {
    KeyW: [1, 0, 0], KeyS: [-1, 0, 0], KeyA: [0, 1, 0],
    KeyD: [0, -1, 0], KeyQ: [0, 0, 1], KeyE: [0, 0, -1],
  };
  const held = new Map();
  const pending = new Map();
  let socket = null;
  let status = null;
  let statusAt = 0;
  let lastTick = 0;
  let sequence = 0;
  let commandId = 0;
  let connecting = false;
  let connectionAttempt = 0;
  let speedContract = "";
  let heartbeat = null;

  const open = () => socket?.readyState === WebSocket.OPEN;
  const fresh = () => open() && status && performance.now() - statusAt < 600;
  const neutral = () => held.size === 0;
  const working = () => [...pending.values()].some((item) => item.command !== "stop");
  const available = () => fresh() && status.ready === true;
  const busy = () => working() || status?.busy === true;
  const isFormTarget = (target) => target instanceof Element && Boolean(target.closest("input, textarea, select, [contenteditable='true']"));

  function notice(text, kind = "") {
    $("notice").textContent = text;
    $("notice").className = `notice ${kind}`;
  }

  function badge(id, text, kind) {
    $(id).textContent = text;
    $(id).className = `badge ${kind}`;
  }

  function validLimits() {
    return status && Number.isFinite(status.deadzone) && status.deadzone >= 0 && status.deadzone < 1 &&
      axes.every((axis) => Number.isFinite(status.limits?.[axis]) && status.limits[axis] > 0 &&
        Number.isFinite(status.minimums?.[axis]) && status.minimums[axis] >= 0 && status.minimums[axis] <= 1);
  }

  function validSpeeds() {
    return validLimits() && axes.every((axis) => {
      const input = $(`speed-${axis}`);
      const value = input.valueAsNumber;
      return Number.isFinite(value) && value >= Number(input.min) - 1e-9 && value <= Number(input.max) + 1e-9;
    });
  }

  function canMove() {
    return available() && status.input_healthy === true && status.armed === true &&
      status.motor_enabled === true && status.control_paused === false && !busy() &&
      ["STANDING", "WALKING"].includes(status.cms) && !$("zero-dialog").open && validSpeeds();
  }

  function rawForSpeed(speed, maximum, minimum, deadzone) {
    if (speed === 0) return 0;
    const fraction = Math.min(1, Math.max(minimum, Math.abs(speed) / maximum));
    const raw = minimum === 1 ? 1 : deadzone + (fraction - minimum) / (1 - minimum) * (1 - deadzone);
    // Minimum commands must remain outside the deadzone after Vector3 float32 conversion.
    return Math.sign(speed) * Math.min(1, Math.max(deadzone + 1e-6, raw));
  }

  function currentAxes() {
    if (!canMove() || neutral()) return [0, 0, 0];
    const direction = [0, 0, 0];
    for (const value of held.values()) value.forEach((v, i) => { direction[i] += v; });
    return direction.map((v, i) => rawForSpeed(
      Math.sign(v) * $(`speed-${axes[i]}`).valueAsNumber,
      status.limits[axes[i]], status.minimums[axes[i]], status.deadzone,
    ));
  }

  function send(payload) {
    if (!open()) return false;
    if (socket.bufferedAmount > 4096) {
      closeConnection("发送拥塞，操控已暂停；电机使能状态待确认", "error");
      return false;
    }
    try {
      socket.send(JSON.stringify({ ...payload, seq: ++sequence }));
      return true;
    } catch (_) {
      closeConnection("发送失败，操控已暂停；电机使能状态待确认", "error");
      return false;
    }
  }

  function sendInput(forceZero = false) {
    return send({ type: "input", axes: forceZero ? [0, 0, 0] : currentAxes() });
  }

  function clearHeld(sendZero = true) {
    held.clear();
    motionButtons.forEach((button) => button.classList.remove("held"));
    if (sendZero) sendInput(true);
  }

  function closeConnection(message, kind = "") {
    const previous = socket;
    socket = null;
    clearInterval(heartbeat);
    heartbeat = null;
    clearHeld(false);
    status = null;
    statusAt = 0;
    pending.clear();
    if (previous) {
      try {
        if (previous.readyState === WebSocket.OPEN && previous.bufferedAmount <= 4096) {
          previous.send(JSON.stringify({ type: "input", seq: ++sequence, axes: [0, 0, 0] }));
        }
        previous.close(1000, "Operator paused");
      } catch (_) { /* The server watchdog also latches a disconnected controller. */ }
    }
    render();
    if (message) notice(message, kind);
  }

  async function request(path, body) {
    const abort = new AbortController();
    const timer = setTimeout(() => abort.abort(), 5000);
    try {
      const response = await fetch(path, {
        method: body === undefined ? "GET" : "POST",
        credentials: "same-origin", cache: "no-store", signal: abort.signal,
        headers: body === undefined ? {} : { "Content-Type": "application/json" },
        body: body === undefined ? undefined : JSON.stringify(body),
      });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || `HTTP ${response.status}`);
      return result;
    } finally { clearTimeout(timer); }
  }

  async function connect(event) {
    event.preventDefault();
    if (connecting || open()) return;
    if (!["http:", "https:"].includes(location.protocol)) {
      notice("离线页面：请从控制服务地址打开，当前不能连接实机。", "error");
      return;
    }
    const attempt = ++connectionAttempt;
    connecting = true;
    render();
    notice("正在认证并读取状态…");
    try {
      if ($("token").value) {
        await request("/api/session", { token: $("token").value });
        $("token").value = "";
        $("token").type = "password";
        $("show-token").setAttribute("aria-pressed", "false");
        $("show-token").title = "显示口令";
        $("show-token").setAttribute("aria-label", "显示口令");
        $("token-icon").src = "icons/eye.svg";
      }
      const snapshot = await request("/api/status");
      if (attempt !== connectionAttempt || document.hidden) return;
      if (snapshot.connected === true && snapshot.input_healthy === true) throw new Error("已有控制端连接，请先退出原控制端。");
      const candidate = new WebSocket(`${location.protocol === "https:" ? "wss:" : "ws:"}//${location.host}/ws`);
      socket = candidate;
      sequence = 0;
      const timeout = setTimeout(() => {
        if (socket === candidate && !open()) closeConnection("连接超时，请确认控制端是否已被占用。", "error");
      }, 5000);
      candidate.onopen = () => {
        clearTimeout(timeout);
        if (socket !== candidate || document.hidden) { candidate.close(); return; }
        clearHeld(false);
        lastTick = performance.now();
        sendInput(true);
        heartbeat = setInterval(tick, 50);
        notice("控制链路已连接，等待状态反馈。");
        render();
      };
      candidate.onmessage = (message) => {
        if (socket !== candidate) return;
        try {
          const data = JSON.parse(message.data);
          if (data.type === "status") acceptStatus(data);
          else if (data.type === "ack") acceptAck(data);
          else if (data.type === "error") {
            clearHeld();
            notice(data.error || "指令被拒绝", "error");
          }
        } catch (_) { closeConnection("状态消息无效，操控已暂停。", "error"); }
      };
      candidate.onerror = () => {
        if (socket === candidate) closeConnection("连接失败：认证过期、控制端被占用或网络不可达。", "error");
      };
      candidate.onclose = () => {
        clearTimeout(timeout);
        if (socket === candidate) closeConnection("连接中断，操控已暂停；电机使能状态待确认。", "error");
      };
    } catch (error) {
      if (attempt === connectionAttempt) closeConnection(error.name === "AbortError" ? "请求超时，请检查网络。" : error.message, "error");
    } finally {
      if (attempt === connectionAttempt) { connecting = false; render(); }
    }
  }

  function acceptStatus(data) {
    if (typeof data.ready !== "boolean" || typeof data.preview !== "boolean" || typeof data.motor_enabled !== "boolean" || typeof data.armed !== "boolean") {
      throw new Error("Invalid status");
    }
    const first = !status;
    status = data;
    statusAt = performance.now();
    updateSpeedContract();
    if (!canMove() && !neutral()) clearHeld();
    if (first) notice(data.preview ? "演示环境：所有执行器为模拟，不连接实机。" : (data.block_reason || "已连接，操控尚未解锁。"));
    for (const [id, item] of pending) {
      if (!item.accepted) continue;
      const done = item.command === "enable" ? data.armed === true && data.motor_enabled === true :
        item.command === "disable" ? data.motor_enabled === false && data.hardware_state_unknown !== true :
        item.command === "stand" ? data.cms === "STANDING" :
        item.command === "sit" ? data.cms === "GROUNDED" :
        item.command === "model" ? data.model_slot === item.slot && data.model_profile === data.slots?.[item.slot] :
        item.command === "stop" ? Array.isArray(data.command) && data.command.every((v) => Number.isFinite(v) && Math.abs(v) < 1e-6) : false;
      if (done) {
        pending.delete(id);
        notice(`${item.label}：已收到状态确认${data.preview ? "（演示）" : ""}`, "success");
      }
    }
    render();
  }

  function updateSpeedContract() {
    if (!validLimits()) return;
    const signature = JSON.stringify([status.limits, status.minimums, status.deadzone]);
    if (signature === speedContract) return;
    speedContract = signature;
    for (const axis of axes) {
      const input = $(`speed-${axis}`);
      const max = status.limits[axis];
      const min = max * status.minimums[axis];
      input.min = String(min);
      input.max = String(max);
      input.value = String(Math.min(max, Math.max(min, Number.isFinite(input.valueAsNumber) ? input.valueAsNumber : 0.5)));
      $(`range-${axis}`).textContent = `${Number(min.toFixed(4))} – ${Number(max.toFixed(4))}`;
    }
  }

  function acceptAck(data) {
    const item = pending.get(data.id);
    if (!item) return;
    if (data.ok !== true) {
      pending.delete(data.id);
      clearHeld();
      notice(`${item.label}失败：${data.error || "请求被拒绝"}`, "error");
    } else if (item.command === "zero") {
      pending.delete(data.id);
      $("zero-dialog").close();
      notice(`16 电机标零流程已返回，请核对角度反馈${status?.preview ? "（演示，不修改实机）" : ""}。`, "success");
    } else {
      item.accepted = true;
      notice(`${item.label}指令已接受，等待实际状态反馈…`);
    }
    render();
  }

  function command(name, extra = {}) {
    if (!fresh() || (!available() && !["disable", "stop"].includes(name))) return false;
    if (!["disable", "stop"].includes(name) && (busy() || !neutral() || status.input_healthy !== true)) return false;
    if (name === "enable" && status.can_enable !== true) return false;
    if (["stand", "sit"].includes(name) && status.armed !== true) return false;
    if (name === "model" && (status.armed !== true || status.can_switch !== true || !["flat", "stairs"].includes(extra.slot))) return false;
    if (name === "zero" && (!zeroAllowed() || !$("confirm-mechanical").checked || !$("confirm-support").checked)) return false;
    clearHeld();
    if (!open()) return false;
    if (name === "disable") pending.clear();
    const id = `web-${++commandId}`;
    const label = { enable: status.motor_enabled ? "恢复操控" : "使能", disable: "断使能", stand: "L1 站立", sit: "L2 趴下", stop: "停止", model: "模型切换", zero: "全部标零" }[name];
    pending.set(id, { command: name, ...extra, label, accepted: false, started: performance.now() });
    if (!send({ type: "command", id, command: name, ...extra })) { pending.delete(id); return false; }
    notice(`${label}已发送，等待确认…`);
    render();
    return true;
  }

  function tick() {
    const now = performance.now();
    // A suspended/throttled tab must never replay a previously held direction.
    if (document.hidden || now - lastTick > 150 || (status && now - statusAt >= 600)) {
      closeConnection("输入或状态反馈中断，操控已暂停；请重新连接并明确恢复操控。", "error");
      return;
    }
    lastTick = now;
    for (const [id, item] of pending) {
      if (now - item.started > (item.command === "zero" ? 30000 : 15000)) {
        pending.delete(id);
        clearHeld();
        notice(`${item.label}未收到完成确认，请检查当前状态；不会自动重试。`, "error");
      }
    }
    sendInput();
    renderControls();
  }

  function canOpenZero() {
    return available() && status.input_healthy === true && status.can_open_zero === true &&
      status.motor_enabled === false && status.motor_output_enabled !== true &&
      status.hardware_state_unknown !== true && status.armed === false &&
      status.cms === "GROUNDED" && !busy() && neutral();
  }

  function zeroAllowed() {
    return canOpenZero() && status.can_zero === true;
  }

  function renderControls() {
    const ready = available();
    const idle = ready && !busy() && neutral() && status.input_healthy === true;
    $("connect").disabled = connecting || open() || socket?.readyState === WebSocket.CONNECTING;
    $("connect").querySelector("span").textContent = connecting ? "连接中…" : "连接";
    $("disconnect").disabled = !socket && !connecting;
    $("token").disabled = open() || connecting;
    $("enable").disabled = !idle || status.can_enable !== true || status.armed === true;
    $("enable").querySelector("span").textContent = status?.motor_enabled && !status?.armed ? "恢复操控" : "使能";
    $("disable").disabled = !fresh();
    $("stand").disabled = !idle || status.armed !== true;
    $("sit").disabled = !idle || status.armed !== true;
    $("stop").disabled = !fresh();
    modelButtons.forEach((button) => {
      const active = ready && button.dataset.slot === status.model_slot;
      button.setAttribute("aria-pressed", String(Boolean(active)));
      button.disabled = !idle || status.armed !== true || status.can_switch !== true || active;
      button.title = active ? "当前槽位" : (status?.block_reason || "切换策略槽位");
    });
    motionButtons.forEach((button) => { button.disabled = !canMove(); });
    axes.forEach((axis) => { $(`speed-${axis}`).disabled = !ready || !validLimits() || busy() || !neutral(); });
    $("open-zero").disabled = !canOpenZero();
    $("confirm-zero").disabled = !zeroAllowed() || !$("confirm-mechanical").checked || !$("confirm-support").checked;
    const zeroProgress = fresh() && {
      writing: "正在写入 16 个电机零点",
      verifying: "正在核对 16 个电机的新反馈",
      uncertain: "标零写入结果未确认，不会自动重试",
    }[status.zero_phase];
    $("zero-state").textContent = !fresh() ? "连接或状态反馈不可用，请重新连接" :
      zeroProgress ? `${zeroProgress}${status.zero_block_reason ? `：${status.zero_block_reason}` : ""}` :
      status.zero_block_reason || (zeroAllowed() ? "静止检查已通过，等待两项安全确认" :
        status.block_reason || "需趴地、未使能、16 电机健康且连续静止后才能标零");
    const moving = canMove();
    badge("motion-state", moving ? (neutral() ? "待命" : "指令输出中") : "锁定", moving ? "good" : "neutral");
    $("model-pending").textContent = [...pending.values()].some((item) => item.command === "model") ? "等待切换反馈…" : "";
  }

  function render() {
    const connected = open();
    const known = Boolean(fresh());
    $("connection-label").textContent = connected ? "已连接" : connecting ? "连接中" : "未连接";
    $("link-indicator").className = `status-dot ${connected ? "good" : connecting ? "pending" : ""}`;
    $("transport-label").textContent = known ? (status.preview ? "模拟执行器" : "WebSocket / 同源认证") : "等待认证";
    badge("environment-badge", known ? (status.preview ? "演示 · 不连接实机" : "实机连接") : "未连接 · 禁止操控", known ? (status.preview ? "demo" : "good") : "neutral");
    badge("ready-badge", known ? (status.ready ? "程序已就绪" : "程序待就绪") : "程序状态未知", known ? (status.ready ? "good" : "pending") : "neutral");
    badge("armed-badge", known && status.armed ? "操控已解锁" : "操控未解锁", known && status.armed ? "good" : "neutral");
    const motorKnown = known && status.hardware_state_unknown !== true;
    badge("motor-badge", motorKnown ? (status.motor_enabled ? "电机已使能" : "电机未使能") : "电机使能未知", motorKnown ? (status.motor_enabled ? "pending" : "neutral") : "neutral");
    const cms = { GROUNDED: "趴地", STANDING: "站立", WALKING: "策略运行", TRANSITIONING: "姿态切换中", ZERO: "标零中" };
    $("cms-label").textContent = known ? (cms[status.cms] || status.cms || "未知") : "—";
    $("block-reason").textContent = known ? (status.block_reason || (status.busy || working() ? "操作进行中" : "")) : "等待状态反馈";
    $("model-profile").textContent = known ? status.model_profile || "—" : "—";
    $("feedback-state").textContent = known ? "实时反馈" : "无反馈";
    axes.forEach((axis, index) => {
      const value = known && Array.isArray(status.command) ? status.command[index] : null;
      $(`actual-${axis}`).textContent = Number.isFinite(value) ? (value > 0 ? "+" : "") + value.toFixed(2) : "—";
    });
    renderMotors(known ? status.motors : null);
    $("heartbeat-label").textContent = known ? `输入链路 ${status.input_healthy ? "正常" : "等待回中"} · 超时 ${status.input_timeout_ms ?? "—"} ms` : "输入链路未建立";
    renderControls();
  }

  function renderMotors(motors) {
    const list = Array.isArray(motors) ? motors : [];
    const identities = new Set(list.filter((m) => m.online === true).map((m) => `${m.leg}/${m.joint}`));
    $("online-count").textContent = motors ? `${identities.size} / 16` : "— / 16";
    $("motor-updated").textContent = motors ? `反馈 ${new Date().toLocaleTimeString("zh-CN", { hour12: false })}` : "未收到反馈";
    for (const cell of document.querySelectorAll("[data-motor]")) {
      const [leg, joint] = cell.dataset.motor.split("/");
      const motor = list.find((m) => m.leg === leg && m.joint === joint);
      const value = cell.querySelector(".motor-value");
      const angle = cell.querySelector(".angle");
      const dot = cell.querySelector(".status-dot");
      const offline = motor && motor.online !== true;
      const errors = motor && Array.isArray(motor.errors) ? motor.errors : [];
      const fault = errors.length > 0;
      angle.textContent = !motor ? "—" : offline ? "离线" : Number.isFinite(motor.position) ? (motor.position * 180 / Math.PI).toFixed(2) : "—";
      value.className = `motor-value ${offline ? "offline" : fault ? "fault" : ""}`;
      dot.className = `status-dot ${!motor ? "" : offline || fault ? "bad" : "good"}`;
      cell.title = motor ? `${leg} ${joint} · ID ${motor.id} · ${offline ? "离线" : fault ? "报警" : "正常"}${fault ? ` · ${errors.map((e) => typeof e === "string" ? e : JSON.stringify(e)).join(" / ")}` : ""}` : `${leg} ${joint} · 无反馈`;
      cell.setAttribute("aria-label", `${cell.title} · ${angle.textContent}${Number.isFinite(motor?.position) && !offline ? " 度" : ""}`);
    }
  }

  for (const [leg, label] of [["FR", "右前"], ["FL", "左前"], ["RR", "右后"], ["RL", "左后"]]) {
    const row = document.createElement("tr");
    const heading = document.createElement("td");
    heading.append(document.createTextNode(leg));
    const chinese = document.createElement("small"); chinese.textContent = label; heading.append(chinese); row.append(heading);
    for (const joint of ["Hip", "Thigh", "Calf", "Foot"]) {
      const cell = document.createElement("td"); cell.dataset.motor = `${leg}/${joint}`;
      const value = document.createElement("span"); value.className = "motor-value";
      const dot = document.createElement("i"); dot.className = "status-dot"; dot.setAttribute("aria-hidden", "true");
      const angle = document.createElement("span"); angle.className = "angle";
      value.append(dot, angle); cell.append(value); row.append(cell);
    }
    $("motor-rows").append(row);
  }

  for (const button of motionButtons) {
    button.addEventListener("pointerdown", (event) => {
      if (event.button !== 0 || !canMove()) return;
      event.preventDefault();
      try { button.setPointerCapture(event.pointerId); } catch (_) { clearHeld(); return; }
      held.set(`pointer-${event.pointerId}`, button.dataset.motion.split(",").map(Number));
      button.classList.add("held");
      sendInput();
      renderControls();
    });
    button.addEventListener("lostpointercapture", () => { if (!neutral()) { clearHeld(); renderControls(); } });
    button.addEventListener("contextmenu", (event) => event.preventDefault());
  }
  for (const event of ["pointerup", "pointercancel"]) {
    window.addEventListener(event, () => { if (!neutral()) { clearHeld(); renderControls(); } }, true);
  }
  window.addEventListener("keydown", (event) => {
    if (event.repeat || isFormTarget(event.target) || $("zero-dialog").open || event.ctrlKey || event.metaKey || event.altKey) return;
    if (event.code === "Space") {
      event.preventDefault(); clearHeld(); command("stop"); return;
    }
    const direction = keyDirections[event.code] || (event.code === "Enter" && event.target instanceof Element && event.target.closest("[data-motion]")?.dataset.motion.split(",").map(Number));
    if (!direction || !canMove()) return;
    event.preventDefault(); held.set(event.code, direction); sendInput(); renderControls();
  });
  window.addEventListener("keyup", (event) => {
    if (!held.delete(event.code)) return;
    event.preventDefault();
    sendInput();
    renderControls();
  }, true);
  document.addEventListener("focusin", (event) => {
    if (isFormTarget(event.target) && !neutral()) { clearHeld(); renderControls(); }
  });
  function suspend() {
    ++connectionAttempt;
    connecting = false;
    closeConnection("页面已离开或暂停；操控已锁定，电机使能状态待确认。", "error");
  }
  window.addEventListener("blur", () => { if (socket || connecting) suspend(); });
  window.addEventListener("pagehide", suspend);
  document.addEventListener("visibilitychange", () => { if (document.hidden && (socket || connecting)) suspend(); });
  window.addEventListener("offline", () => { if (socket || connecting) suspend(); });

  $("login-form").addEventListener("submit", connect);
  $("disconnect").addEventListener("click", async () => {
    ++connectionAttempt; connecting = false;
    closeConnection("已退出连接；未发送断使能指令，电机实际状态待确认。");
    try { await request("/api/logout", {}); } catch (_) { notice("本页已断开，服务器会话退出未确认。", "error"); }
  });
  $("show-token").addEventListener("click", () => {
    const shown = $("token").type === "password";
    $("token").type = shown ? "text" : "password";
    $("show-token").setAttribute("aria-pressed", String(shown));
    $("show-token").title = shown ? "隐藏口令" : "显示口令";
    $("show-token").setAttribute("aria-label", $("show-token").title);
    $("token-icon").src = `icons/${shown ? "eye-off" : "eye"}.svg`;
  });
  for (const name of ["enable", "disable", "stand", "sit", "stop"]) $(name).addEventListener("click", () => command(name));
  modelButtons.forEach((button) => button.addEventListener("click", () => command("model", { slot: button.dataset.slot })));
  axes.forEach((axis) => $(`speed-${axis}`).addEventListener("input", () => { clearHeld(); renderControls(); }));
  $("open-zero").addEventListener("click", () => {
    clearHeld();
    if (!canOpenZero()) return;
    $("confirm-mechanical").checked = false;
    $("confirm-support").checked = false;
    $("zero-dialog").showModal();
    renderControls();
  });
  for (const id of ["cancel-zero", "close-zero"]) $(id).addEventListener("click", () => $("zero-dialog").close());
  for (const id of ["confirm-mechanical", "confirm-support"]) $(id).addEventListener("change", renderControls);
  $("zero-dialog").addEventListener("close", () => {
    $("confirm-mechanical").checked = false; $("confirm-support").checked = false; clearHeld(); renderControls();
  });
  $("zero-form").addEventListener("submit", (event) => {
    event.preventDefault();
    command("zero", { confirmation: "ALL_16_AT_MECHANICAL_ZERO" });
  });
  $("endpoint").textContent = location.protocol.startsWith("http") ? location.host : "离线页面";
  render();
})();
