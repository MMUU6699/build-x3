import { Buffer } from "node:buffer";
import { Daytona } from "npm:@daytona/sdk@0.217.0";
import { AuthError, createAdminClient, getRequiredSecret, requireUser } from "./_shared/supabase.ts";
import { handlePreflight, isOriginAllowed, jsonResponse } from "./_shared/http.ts";

const NVIDIA_API_URL = "https://integrate.api.nvidia.com/v1/chat/completions";
const DEFAULT_MODEL = "nvidia/nemotron-3-ultra-550b-a55b";
const GLM_MODEL = "z-ai/glm-5.3-flash";
const ALLOWED_MODELS = new Set([DEFAULT_MODEL, GLM_MODEL]);
const ALLOWED_REASONING_EFFORTS = new Set(["none", "low", "medium", "high", "standard"]);
const MAX_PROMPT_CHARS = 4_000_000;
const MAX_HTML_BYTES = 450_000;
const MAX_TOOL_RESULT_CHARS = 16_000;
const MAX_AGENT_ITERATIONS = 100;
const FORBIDDEN_SECRET_FIELDS = new Set([
  "api_key",
  "apiKey",
  "nvidia_api_key",
  "nvidiaApiKey",
  "daytona_api_key",
  "daytonaApiKey",
  "authorization",
  "secret",
]);

class InputError extends Error {}
class NvidiaError extends Error {}

// This helper is uploaded into the Daytona workspace and runs inside the
// sandbox. It speaks the Chrome DevTools Protocol over the sandbox-local
// websocket, so the Edge Function never exposes a raw CDP endpoint.
const CDP_HELPER = String.raw`#!/usr/bin/env python3
import base64, hashlib, json, os, socket, struct, sys, time, urllib.parse, urllib.request

def http(method, url, body=None):
    req = urllib.request.Request(url, method=method, data=body)
    with urllib.request.urlopen(req, timeout=15) as response:
        return json.loads(response.read().decode('utf-8'))

def frame(payload):
    data = payload.encode('utf-8')
    mask = os.urandom(4)
    masked = bytes(data[i] ^ mask[i % 4] for i in range(len(data)))
    n = len(data)
    if n < 126: head = bytes([0x81, 0x80 | n])
    elif n < 65536: head = bytes([0x81, 0x80 | 126]) + struct.pack('>H', n)
    else: head = bytes([0x81, 0x80 | 127]) + struct.pack('>Q', n)
    return head + mask + masked

def read_exact(sock, n):
    out = b''
    while len(out) < n:
        chunk = sock.recv(n - len(out))
        if not chunk: raise RuntimeError('CDP websocket closed')
        out += chunk
    return out

def read_frame(sock):
    first, second = read_exact(sock, 2)
    length = second & 127
    if length == 126: length = struct.unpack('>H', read_exact(sock, 2))[0]
    elif length == 127: length = struct.unpack('>Q', read_exact(sock, 8))[0]
    masked = second & 128
    mask = read_exact(sock, 4) if masked else b''
    data = read_exact(sock, length)
    if masked: data = bytes(data[i] ^ mask[i % 4] for i in range(length))
    return first & 15, data.decode('utf-8', errors='replace')

def connect():
    targets = http('GET', 'http://127.0.0.1:9222/json/list')
    target = next((t for t in targets if t.get('type') == 'page'), None)
    if target is None:
        target = http('PUT', 'http://127.0.0.1:9222/json/new?about:blank')
    ws = urllib.parse.urlparse(target['webSocketDebuggerUrl'])
    sock = socket.create_connection((ws.hostname, ws.port or 80), timeout=20)
    key = base64.b64encode(os.urandom(16)).decode()
    path = ws.path or '/'
    if ws.query: path += '?' + ws.query
    request = ('GET %s HTTP/1.1\r\nHost: %s\r\nUpgrade: websocket\r\n'
               'Connection: Upgrade\r\nSec-WebSocket-Key: %s\r\n'
               'Sec-WebSocket-Version: 13\r\n\r\n') % (path, ws.netloc, key)
    sock.sendall(request.encode())
    response = b''
    while b'\r\n\r\n' not in response: response += sock.recv(4096)
    if b' 101 ' not in response.split(b'\r\n', 1)[0]: raise RuntimeError('CDP websocket handshake failed')
    return sock

def call(sock, counter, method, params=None):
    counter[0] += 1
    ident = counter[0]
    sock.sendall(frame(json.dumps({'id': ident, 'method': method, 'params': params or {}})))
    while True:
        kind, raw = read_frame(sock)
        if kind == 8: raise RuntimeError('CDP websocket closed')
        if kind != 1: continue
        message = json.loads(raw)
        if message.get('id') == ident:
            if 'error' in message: raise RuntimeError(str(message['error']))
            return message.get('result', {})

def evaluate(sock, counter, expression):
    result = call(sock, counter, 'Runtime.evaluate', {
        'expression': expression, 'returnByValue': True, 'awaitPromise': True,
    })
    return result.get('result', {}).get('value')

SNAPSHOT = r'''(() => {
  const selector = 'a,button,input,textarea,select,[role="button"],[contenteditable="true"]';
  const elements = [...document.querySelectorAll(selector)].filter(el => {
    const r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0 && !el.disabled;
  });
  window.__buildxElements = elements;
  return {
    url: location.href, title: document.title || 'Web Page',
    text: (document.body?.innerText || '').slice(0, 8000),
    elements: elements.slice(0, 120).map((el, i) => ({
      index: i + 1, tag: el.tagName.toLowerCase(),
      text: (el.innerText || el.getAttribute('aria-label') || el.value || '').trim().slice(0, 160),
      type: el.getAttribute('type') || null,
    })),
  };
})()'''

def main():
    request = json.loads(sys.stdin.read())
    sock, counter = connect(), [0]
    call(sock, counter, 'Page.enable')
    call(sock, counter, 'Runtime.enable')
    action = request.get('action', 'view')
    if action == 'navigate':
        call(sock, counter, 'Page.navigate', {'url': request['url']})
        time.sleep(float(request.get('wait', 1.0)))
    elif action == 'click':
        idx = int(request.get('index', 0))
        evaluate(sock, counter, 'window.__buildxElements && window.__buildxElements[%d]?.click()' % (idx - 1))
        time.sleep(0.4)
    elif action == 'type':
        idx = int(request.get('index', 0)); text = json.dumps(str(request.get('text', '')))
        expression = '''(() => { const el = window.__buildxElements && window.__buildxElements[%d]; if (!el) throw new Error('Element index not found'); el.focus(); if ('value' in el) { el.value = %s; el.dispatchEvent(new Event('input', {bubbles:true})); el.dispatchEvent(new Event('change', {bubbles:true})); } else { document.execCommand('insertText', false, %s); } return true; })()''' % (idx - 1, text, text)
        evaluate(sock, counter, expression)
        if request.get('press_enter'): call(sock, counter, 'Input.dispatchKeyEvent', {'type': 'keyDown', 'key': 'Enter', 'code': 'Enter'})
        time.sleep(0.4)
    elif action in ('mouse_move', 'mouse_click'):
        x = float(request.get('x', 0)); y = float(request.get('y', 0))
        if action == 'mouse_move':
            call(sock, counter, 'Input.dispatchMouseEvent', {'type': 'mouseMoved', 'x': x, 'y': y})
        else:
            button = str(request.get('button', 'left'))
            call(sock, counter, 'Input.dispatchMouseEvent', {'type': 'mousePressed', 'x': x, 'y': y, 'button': button, 'clickCount': 1})
            call(sock, counter, 'Input.dispatchMouseEvent', {'type': 'mouseReleased', 'x': x, 'y': y, 'button': button, 'clickCount': 1})
        time.sleep(0.15)
    elif action == 'key':
        key = str(request.get('key', ''))
        code = str(request.get('code', key))
        call(sock, counter, 'Input.dispatchKeyEvent', {'type': 'keyDown', 'key': key, 'code': code})
        call(sock, counter, 'Input.dispatchKeyEvent', {'type': 'keyUp', 'key': key, 'code': code})
    elif action == 'insert_text':
        call(sock, counter, 'Input.insertText', {'text': str(request.get('text', ''))})
    elif action == 'scroll':
        direction = -1 if request.get('direction') == 'up' else 1
        evaluate(sock, counter, 'window.scrollBy(0, %d * window.innerHeight)' % direction)
        time.sleep(0.3)
    elif action == 'screenshot':
        result = call(sock, counter, 'Page.captureScreenshot', {'format': 'png'})
        print(json.dumps({'screenshot_base64': result.get('data', '')})); return
    state = evaluate(sock, counter, SNAPSHOT)
    print(json.dumps(state or {}))

if __name__ == '__main__':
    try: main()
    except Exception as exc: print(json.dumps({'error': str(exc)})); sys.exit(1)
`;

function nvidiaApiKey(model: string): string {
  const nemotronKey = Deno.env.get("NVIDIA_NEMOTRON_API_KEY")?.trim();
  const glmKey = Deno.env.get("NVIDIA_GLM_API_KEY")?.trim();
  const generalKey = Deno.env.get("NVIDIA_API_KEY")?.trim();
  const key = nemotronKey || glmKey || generalKey;
  if (!key) {
    throw new Error("Missing required server configuration: NVIDIA API key");
  }
  return key;
}

function getSerperApiKey(): string {`r`n  return Deno.env.get("SERPER_API_KEY")?.trim() || "";
}

async function executeSerperSearch(query: string): Promise<{ text: string; searchSucceeded: boolean }> {
  try {
    const key = getSerperApiKey();
    const res = await fetch("https://google.serper.dev/search", {
      method: "POST",
      headers: {
        "X-API-KEY": key,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ q: query }),
      signal: AbortSignal.timeout(15000),
    });
    if (!res.ok) {
      return {
        text: `Serper search returned HTTP ${res.status}`,
        searchSucceeded: false,
      };
    }
    const data = await res.json() as Record<string, unknown>;
    const organic = Array.isArray(data.organic) ? (data.organic as Array<Record<string, unknown>>) : [];
    if (organic.length === 0) {
      return {
        text: `No search results found for: ${query}`,
        searchSucceeded: false,
      };
    }
    let formatted = "";
    if (data.answerBox && typeof data.answerBox === "object") {
      const ab = data.answerBox as Record<string, unknown>;
      const ans = ab.answer ?? ab.snippet ?? ab.title;
      if (ans) formatted += `Direct Answer: ${ans}\n\n`;
    }
    if (data.knowledgeGraph && typeof data.knowledgeGraph === "object") {
      const kg = data.knowledgeGraph as Record<string, unknown>;
      const title = kg.title ?? "";
      const desc = kg.description ?? "";
      if (title || desc) formatted += `Knowledge Graph: ${title} - ${desc}\n\n`;
    }
    formatted += organic.slice(0, 8).map((item, idx) => {
      const title = item.title ?? "";
      const link = item.link ?? "";
      const snippet = item.snippet ?? "";
      return `[${idx + 1}] ${title}\nURL: ${link}\nSnippet: ${snippet}`;
    }).join("\n\n");
    return { text: formatted.trim(), searchSucceeded: true };
  } catch (e) {
    return {
      text: `Search failed: ${e instanceof Error ? e.message : String(e)}`,
      searchSucceeded: false,
    };
  }
}

async function ensureCdpBrowser(sandbox: any): Promise<void> {
  await sandbox.fs.uploadFile(Buffer.from(CDP_HELPER, "utf8"), "workspace/.buildx_cdp.py", 60);
  const command = [
    "if ! curl -fsS http://127.0.0.1:9222/json/version >/dev/null 2>&1; then",
    "  BIN=$(command -v chromium || command -v chromium-browser || command -v google-chrome)",
    "  nohup $BIN --headless=new --no-sandbox --disable-gpu --remote-debugging-address=127.0.0.1 --remote-debugging-port=9222 --user-data-dir=/tmp/buildx-chrome --window-size=1280,900 about:blank >/tmp/buildx-chrome.log 2>&1 &",
    "  for i in $(seq 1 30); do curl -fsS http://127.0.0.1:9222/json/version >/dev/null 2>&1 && break; sleep 1; done",
    "fi",
  ].join(" ");
  const result = await sandbox.process.executeCommand(command, "workspace", undefined, 40);
  if (result.exitCode !== 0) throw new Error(`Chromium CDP startup failed: ${result.result ?? "unknown error"}`);
}

async function cdpAction(sandbox: any, request: Record<string, unknown>): Promise<Record<string, unknown>> {
  const payload = Buffer.from(JSON.stringify(request), "utf8").toString("base64");
  const result = await sandbox.process.executeCommand(
    `printf '%s' '${payload}' | base64 -d | python3 .buildx_cdp.py`,
    "workspace",
    undefined,
    45,
  );
  const output = String(result.result ?? "").trim();
  if (result.exitCode !== 0 || !output) throw new Error(`CDP action failed: ${output || "no output"}`);
  const line = output.split(/\r?\n/).filter(Boolean).at(-1) ?? "{}";
  const parsed = JSON.parse(line) as Record<string, unknown>;
  if (typeof parsed.error === "string") throw new Error(parsed.error);
  return parsed;
}

function truncateToolResult(value: string, limit = MAX_TOOL_RESULT_CHARS): string {
  if (value.length <= limit) return value;
  return `${value.slice(0, limit)}... [truncated ${value.length - limit} chars]`;
}

function parseBody(value: unknown): {
  runId: string;
  prompt: string;
  model: string;
  reasoningEffort: string;
} {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new InputError("Request body must be a JSON object");
  }
  const body = value as Record<string, unknown>;
  for (const key of FORBIDDEN_SECRET_FIELDS) {
    if (key in body) throw new InputError("Client-provided provider credentials are not accepted");
  }

  const prompt = typeof body.prompt === "string" ? body.prompt.trim() : "";
  if (!prompt || prompt.length > MAX_PROMPT_CHARS) {
    throw new InputError(`prompt must contain between 1 and ${MAX_PROMPT_CHARS} characters`);
  }
  const runId = typeof body.run_id === "string" && /^[0-9a-f-]{36}$/i.test(body.run_id)
    ? body.run_id
    : crypto.randomUUID();
  const model = typeof body.model === "string" ? body.model : DEFAULT_MODEL;
  if (!ALLOWED_MODELS.has(model)) throw new InputError("Unsupported model");
  const reasoningEffort = typeof body.reasoning_effort === "string"
    ? body.reasoning_effort
    : "high";
  if (!ALLOWED_REASONING_EFFORTS.has(reasoningEffort)) {
    throw new InputError("reasoning_effort must be none, low, medium, high, or standard");
  }
  return { runId, prompt, model, reasoningEffort };
}

// Short social turns belong in the conversation surface. Keep this check
// before work_runs and sandbox creation so a greeting can never create files.
function extractHtml(output: string): string {
  const fenced = /```html\s*([\s\S]*?)```/i.exec(output)?.[1]?.trim();
  const htmlStart = output.search(/<!doctype html|<html/i);
  const candidate = fenced || (htmlStart >= 0 ? output.slice(htmlStart).trim() : "");
  if (!candidate || !/<(?:!doctype\s+html|html)[\s>]/i.test(candidate)) {
    throw new Error("Model did not produce a standalone HTML deliverable");
  }
  if (new TextEncoder().encode(candidate).byteLength > MAX_HTML_BYTES) {
    throw new Error("Generated deliverable exceeds the server size limit");
  }
  return candidate;
}

async function generateHtml(
  prompt: string,
  model: string,
  reasoningEffort: string,
): Promise<string> {
  const response = await fetch(NVIDIA_API_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${nvidiaApiKey(model)}`,
      "Accept": "application/json",
    },
    body: JSON.stringify({
      model,
      messages: [
        {
          role: "system",
          content:
            "You are a software delivery agent. Produce one complete, standalone index.html file with embedded CSS and JavaScript. Return only one ```html fenced code block. Do not include secrets, remote credentials, or prose outside the code block.",
        },
        { role: "user", content: prompt },
      ],
      temperature: 0.7,
      top_p: 0.95,
      max_tokens: 4096,
      stream: true,
      chat_template_kwargs: {
        enable_thinking: reasoningEffort !== "none",
        ...(reasoningEffort === "low" || reasoningEffort === "medium"
          ? { medium_effort: true }
          : {}),
        force_nonempty_content: true,
      },
    }),
    signal: AbortSignal.timeout(75000),
  });
  if (!response.ok) {
    const body = await response.text();
    let detail = body;
    try {
      const parsed = JSON.parse(body) as Record<string, unknown>;
      const error = parsed.error;
      detail = error && typeof error === "object"
        ? String((error as Record<string, unknown>).message ?? (error as Record<string, unknown>).detail ?? JSON.stringify(error))
        : String(error ?? parsed.message ?? parsed.detail ?? body);
    } catch {
      // Keep the upstream proxy's plain-text diagnostic when it is not JSON.
    }
    detail = detail.replace(/bearer\s+\S+|nvapi-[\w-]+/gi, "[redacted]").replace(/\s+/g, " ").slice(0, 500);
    console.error("NVIDIA work generation failed", { status: response.status, detail });
    throw new NvidiaError(`NVIDIA returned HTTP ${response.status}: ${detail}`);
  }

  if (!response.body) throw new Error("Model returned no content");
  const reader = response.body.pipeThrough(new TextDecoderStream()).getReader();
  let pending = "";
  let content = "";
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    pending += value;
    const lines = pending.split(/\r?\n/);
    pending = lines.pop() ?? "";
    for (const line of lines) {
      if (!line.startsWith("data:")) continue;
      const data = line.slice(5).trim();
      if (!data || data === "[DONE]") continue;
      try {
        const chunk = JSON.parse(data) as Record<string, unknown>;
        const choices = chunk.choices;
        const delta = Array.isArray(choices)
          ? (choices[0] as Record<string, unknown>)?.delta
          : null;
        const text = delta && typeof delta === "object"
          ? (delta as Record<string, unknown>).content
          : null;
        if (typeof text === "string") content += text;
      } catch {
        // Ignore non-JSON keep-alive lines in the provider stream.
      }
    }
  }
  if (!content.trim()) throw new Error("Model returned no content");
  return extractHtml(content);
}

const AGENT_TOOLS = [
  {
    type: "function",
    function: {
      name: "browser_search",
      description: "Search Google and retrieve top web results with links, answers, and summaries.",
      parameters: { type: "object", properties: { query: { type: "string", description: "Search query" } }, required: ["query"] },
    },
  },
  {
    type: "function",
    function: {
      name: "browser_open",
      description: "Navigate to a webpage in Google Chrome / Chromium and extract its page title and content.",
      parameters: { type: "object", properties: { url: { type: "string", description: "HTTP or HTTPS URL to visit" } }, required: ["url"] },
    },
  },
  {
    type: "function",
    function: {
      name: "shell_execute",
      description: "Run a bash command inside the Ubuntu sandbox workspace (e.g. git clone <url> workspace/<repo>, ls -la, python3, cat). Returns stdout and stderr.",
      parameters: { type: "object", properties: { command: { type: "string", description: "Bash command to execute" } }, required: ["command"] },
    },
  },
  {
    type: "function",
    function: {
      name: "file_write",
      description: "Create or replace a file under the Daytona workspace directory.",
      parameters: { type: "object", properties: { path: { type: "string", description: "Relative file path inside workspace/" }, content: { type: "string", description: "File content" } }, required: ["path", "content"] },
    },
  },
  {
    type: "function",
    function: {
      name: "file_read",
      description: "Read a text file under the Daytona workspace directory.",
      parameters: { type: "object", properties: { path: { type: "string", description: "Relative file path inside workspace/" } }, required: ["path"] },
    },
  },
  {
    type: "function",
    function: {
      name: "file_delete",
      description: "Delete a file under the Daytona workspace directory.",
      parameters: { type: "object", properties: { path: { type: "string", description: "Relative file path inside workspace/" } }, required: ["path"] },
    },
  },
  {
    type: "function",
    function: {
      name: "file_str_replace",
      description: "Replace one exact string in a text file under the Daytona workspace.",
      parameters: { type: "object", properties: { path: { type: "string" }, old_text: { type: "string" }, new_text: { type: "string" } }, required: ["path", "old_text", "new_text"] },
    },
  },
  {
    type: "function",
    function: {
      name: "file_find",
      description: "Find files under the Daytona workspace using a shell glob.",
      parameters: { type: "object", properties: { path: { type: "string" }, pattern: { type: "string" } }, required: ["path", "pattern"] },
    },
  },
  {
    type: "function",
    function: {
      name: "complete_step",
      description: "Report the outcome of the current plan step ONLY when its work is actually finished and verified (e.g. files saved, commands run, or pages visited). Do not call without executing work tools.",
      parameters: {
        type: "object",
        properties: {
          success: { type: "boolean", description: "Whether the step succeeded" },
          result: { type: "string", description: "Detailed outcome and verified findings of this step" },
        },
        required: ["success", "result"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "message_ask_user",
      description: "Ask the user a question or suggest human takeover (e.g. for CAPTCHAs, logins, or clarifications).",
      parameters: {
        type: "object",
        properties: {
          text: { type: "string", description: "Question or message to the user" },
          suggest_user_takeover: { type: "string", enum: ["none", "browser"], description: "Suggest taking over interactive browser" },
        },
        required: ["text"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "deliver_result",
      description: "Deliver the final result and summary to the user when all steps are completed.",
      parameters: {
        type: "object",
        properties: {
          message: { type: "string", description: "Comprehensive final summary and answer explaining the findings" },
          files: { type: "array", items: { type: "string" }, description: "List of files produced or analyzed" },
        },
        required: ["message"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "browser_view",
      description: "Read the current Chrome page state, extracted text, and indexed interactive elements.",
      parameters: { type: "object", properties: {} },
    },
  },
    {
      type: "function",
      function: {
        name: "browser_click",
        description: "Click a current-page interactive element by its index or by viewport coordinates.",
        parameters: { type: "object", properties: { index: { type: "integer" }, coordinate_x: { type: "number" }, coordinate_y: { type: "number" } }, required: [] },
      },
    },
  {
    type: "function",
    function: {
      name: "browser_input",
      description: "Type into a current-page editable element by its index from browser_view.",
      parameters: { type: "object", properties: { index: { type: "integer" }, text: { type: "string" }, press_enter: { type: "boolean" } }, required: ["index", "text", "press_enter"] },
    },
  },
    {
      type: "function",
      function: {
        name: "browser_scroll",
      description: "Scroll the current Chrome page up or down.",
      parameters: { type: "object", properties: { direction: { type: "string", enum: ["up", "down"] } }, required: ["direction"] },
    },
  },
  {
    type: "function",
    function: {
      name: "browser_screenshot",
      description: "Capture the current Chrome page as a PNG screenshot.",
      parameters: { type: "object", properties: {} },
    },
  },
  {
    type: "function",
    function: {
      name: "message_notify_user",
      description: "Send a short progress acknowledgement without waiting for a reply.",
      parameters: { type: "object", properties: { text: { type: "string" } }, required: ["text"] },
    },
  },
  {
    type: "function",
    function: {
      name: "browser_move_mouse",
      description: "Move the real browser mouse cursor to viewport coordinates.",
      parameters: { type: "object", properties: { coordinate_x: { type: "number" }, coordinate_y: { type: "number" } }, required: ["coordinate_x", "coordinate_y"] },
    },
  },
  {
    type: "function",
    function: {
      name: "browser_press_key",
      description: "Press a real key in the active Chromium page, such as Enter, Escape, or Control+A.",
      parameters: { type: "object", properties: { key: { type: "string" }, code: { type: "string" } }, required: ["key"] },
    },
  },
];

const PLANNER_TOOLS = [
  {
    type: "function",
    function: {
      name: "create_plan",
      description: "Submit the plan for the user's request. Use an empty steps array for a direct answer or infeasible request.",
      parameters: {
        type: "object",
        properties: {
          title: { type: "string" },
          goal: { type: "string" },
          message: { type: "string" },
          language: { type: "string" },
          steps: { type: "array", items: { type: "object", properties: { id: { type: "integer" }, title: { type: "string" } }, required: ["id", "title"] } },
        },
        required: ["title", "goal", "message", "language", "steps"],
      },
    },
  },
];

const UPDATE_PLAN_TOOLS = [
  {
    type: "function",
    function: {
      name: "update_plan",
      description: "Submit replacement steps for the unfinished portion after a failed step.",
      parameters: {
        type: "object",
        properties: { steps: { type: "array", items: { type: "object", properties: { id: { type: "integer" }, title: { type: "string" } }, required: ["id", "title"] } } },
        required: ["steps"],
      },
    },
  },
];

function workspacePath(value: unknown): string {
  const raw = typeof value === "string" ? value.trim().replaceAll("\\", "/") : "";
  const relative = raw.replace(/^workspace\//, "");
  if (!relative || relative.startsWith("/") || relative.split("/").some((part) => part === ".." || part === "")) {
    throw new InputError("File tools accept only safe relative workspace paths");
  }
  return `workspace/${relative}`;
}

function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (character) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  })[character] ?? character);
}

type BuildPlanStep = {
  id: number;
  title: string;
  status: "pending" | "in_progress" | "completed" | "failed";
  result?: string;
  error?: string;
};

type BuildPlan = {
  title: string;
  goal: string;
  message: string;
  language: string;
  steps: BuildPlanStep[];
};

async function askNvidia(
  model: string,
  messages: Array<Record<string, unknown>>,
  tools: unknown[],
  toolChoice: string,
  reasoningEffort: string,
): Promise<Record<string, unknown>> {
  const response = await fetch(NVIDIA_API_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${nvidiaApiKey(model)}`,
      "Accept": "application/json",
    },
    body: JSON.stringify({
      model,
      messages,
      tools,
      tool_choice: toolChoice,
      temperature: 0.2,
      top_p: 0.95,
      max_tokens: 4096,
      stream: false,
      chat_template_kwargs: {
        enable_thinking: reasoningEffort !== "none",
        force_nonempty_content: true,
      },
    }),
    signal: AbortSignal.timeout(60_000),
  });
  if (!response.ok) {
    const detail = (await response.text()).replace(/bearer\s+\S+|nvapi-[\w-]+/gi, "[redacted]").slice(0, 500);
    throw new NvidiaError(`NVIDIA agent returned HTTP ${response.status}: ${detail}`);
  }
  const body = await response.json() as Record<string, unknown>;
  const choices = body.choices;
  const choice = Array.isArray(choices) ? choices[0] as Record<string, unknown> : null;
  const message = choice?.message;
  if (!message || typeof message !== "object") throw new Error("Agent returned no message");
  return message as Record<string, unknown>;
}

function toolCallsOf(message: Record<string, unknown>): Array<Record<string, unknown>> {
  return Array.isArray(message.tool_calls)
    ? message.tool_calls.filter((value): value is Record<string, unknown> => !!value && typeof value === "object")
    : [];
}

function parseToolArgs(call: Record<string, unknown>): Record<string, unknown> {
  const fn = call.function && typeof call.function === "object" ? call.function as Record<string, unknown> : {};
  try {
    const value = JSON.parse(String(fn.arguments ?? "{}"));
    return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : {};
  } catch {
    return {};
  }
}

async function createPlan(
  prompt: string,
  model: string,
  reasoningEffort: string,
): Promise<BuildPlan> {
  const message = await askNvidia(
    model,
    [
      {
        role: "system",
        content: "You are the Build X Work planner. Always call create_plan. Decide whether the request needs real computer work. For greetings, ordinary questions, or infeasible requests, return a helpful message and steps: []. For work, return a short ordered plan of atomic steps. Do not execute tools.",
      },
      { role: "user", content: prompt },
    ],
    PLANNER_TOOLS,
    "required",
    reasoningEffort,
  );
  const call = toolCallsOf(message).find((candidate) => {
    const fn = candidate.function && typeof candidate.function === "object" ? candidate.function as Record<string, unknown> : {};
    return fn.name === "create_plan";
  });
  if (!call) throw new Error("Planner did not submit create_plan");
  const args = parseToolArgs(call);
  const rawSteps = Array.isArray(args.steps) ? args.steps : [];
  const steps: BuildPlanStep[] = rawSteps.slice(0, 12).map((value, index) => {
    const step = value && typeof value === "object" ? value as Record<string, unknown> : {};
    return {
      id: Number.isFinite(Number(step.id)) ? Number(step.id) : index + 1,
      title: String(step.title ?? "Complete requested work").trim(),
      status: index === 0 ? "in_progress" : "pending",
    };
  });
  return {
    title: String(args.title ?? prompt.slice(0, 80)).trim() || "Build X task",
    goal: String(args.goal ?? prompt).trim(),
    message: String(args.message ?? "").trim(),
    language: String(args.language ?? "en").trim() || "en",
    steps,
  };
}

function planPayload(plan: BuildPlan): Record<string, unknown> {
  return { steps: plan.steps.map(({ id, title, status }) => ({ id, title, status })) };
}

async function executeBuildXTool(
  name: string,
  args: Record<string, unknown>,
  sandbox: any,
  appendEvent: (eventType: string, payload?: Record<string, unknown>) => Promise<void>,
): Promise<{ output: string; didWork: boolean; waiting?: boolean }> {
  if (name === "shell_execute") {
    const command = String(args.command ?? "").trim();
    if (!command || command.length > 12_000) throw new InputError("Command length must be between 1 and 12000 characters");
    const result = await sandbox.process.executeCommand(command, "workspace", undefined, 90);
    const output = truncateToolResult(`exit_code: ${result.exitCode}\n${result.result ?? ""}`);
    await appendEvent("terminal", { command, output });
    return { output, didWork: true };
  }

  if (name === "file_write") {
    const path = workspacePath(args.path);
    const content = String(args.content ?? "");
    let oldContent = "";
    try {
      oldContent = new TextDecoder().decode(await sandbox.fs.downloadFile(path, 30));
    } catch {
      // A missing file is a new file.
    }
    await sandbox.fs.uploadFile(Buffer.from(content, "utf8"), path, 60);
    await appendEvent("coding", { filePath: path, oldContent, newContent: content, isNew: oldContent.length === 0 });
    return { output: `Wrote ${path} (${Buffer.byteLength(content, "utf8")} bytes).`, didWork: true };
  }

  if (name === "file_read") {
    const path = workspacePath(args.path);
    const content = new TextDecoder().decode(await sandbox.fs.downloadFile(path, 30));
    await appendEvent("coding", {
      filePath: path,
      oldContent: content,
      newContent: content,
      isNew: false,
      operation: "read",
    });
    return { output: truncateToolResult(content), didWork: true };
  }

  if (name === "file_delete") {
    const path = workspacePath(args.path);
    await sandbox.fs.deleteFile(path);
    return { output: `Deleted ${path}.`, didWork: true };
  }

  if (name === "file_str_replace") {
    const path = workspacePath(args.path);
    const oldText = String(args.old_text ?? "");
    const newText = String(args.new_text ?? "");
    if (!oldText) throw new InputError("old_text is required");
    const oldContent = new TextDecoder().decode(await sandbox.fs.downloadFile(path, 30));
    if (!oldContent.includes(oldText)) throw new InputError("old_text was not found in the file");
    const newContent = oldContent.replace(oldText, newText);
    await sandbox.fs.uploadFile(Buffer.from(newContent, "utf8"), path, 60);
    await appendEvent("coding", { filePath: path, oldContent, newContent, isNew: false });
    return { output: `Replaced text in ${path}.`, didWork: true };
  }

  if (name === "file_find") {
    const path = workspacePath(args.path);
    const relativePath = path.replace(/^workspace\//, "");
    const pattern = String(args.pattern ?? "*");
    if (!/^[a-zA-Z0-9._*?/-]+$/.test(pattern)) throw new InputError("pattern contains unsupported characters");
    const result = await sandbox.process.executeCommand(`find '${relativePath}' -type f -name '${pattern}' -print | head -200`, "workspace", undefined, 30);
    return { output: truncateToolResult(String(result.result ?? "")), didWork: true };
  }

  if (name === "browser_open" || name === "browser_view" || name === "browser_click" || name === "browser_input" || name === "browser_scroll" || name === "browser_screenshot" || name === "browser_move_mouse" || name === "browser_press_key") {
    await ensureCdpBrowser(sandbox);
    let request: Record<string, unknown> = { action: name === "browser_open" ? "navigate" : name.replace("browser_", "") };
    if (name === "browser_open") {
      const rawUrl = String(args.url ?? "").trim();
      if (!/^https?:\/\//i.test(rawUrl)) throw new InputError("URL must start with http:// or https://");
      request = { action: "navigate", url: rawUrl };
    } else if (name === "browser_click") {
      if (args.coordinate_x != null && args.coordinate_y != null) {
        request = { action: "mouse_click", x: Number(args.coordinate_x), y: Number(args.coordinate_y), button: "left" };
      } else {
        request = { action: "click", index: Number(args.index) };
      }
    } else if (name === "browser_input") {
      request.index = Number(args.index);
      request.text = String(args.text ?? "");
      request.press_enter = Boolean(args.press_enter);
    } else if (name === "browser_scroll") request.direction = String(args.direction ?? "down");
    else if (name === "browser_move_mouse") {
      request = { action: "mouse_move", x: Number(args.coordinate_x), y: Number(args.coordinate_y) };
    } else if (name === "browser_press_key") {
      request = { action: "key", key: String(args.key ?? ""), code: String(args.code ?? args.key ?? "") };
    }
    const state = await cdpAction(sandbox, request);
    if (name === "browser_screenshot") {
      const screenshot = String(state.screenshot_base64 ?? "");
      const page = await cdpAction(sandbox, { action: "view" });
      await appendEvent("computer", {
        action: "Captured Chrome screenshot",
        screenshot_base64: screenshot,
        url: String(page.url ?? ""),
        title: String(page.title ?? "Web Page"),
      });
      return { output: `Captured screenshot (${screenshot.length} base64 chars).`, didWork: true };
    }
    // Every browser operation produces a real frame for the Computer panel.
    // The UI must never invent a webpage when the browser has not emitted one.
    const frame = await cdpAction(sandbox, { action: "screenshot" });
    const snapshot = JSON.stringify(state);
    await appendEvent("browsing", {
      url: String(state.url ?? ""),
      title: String(state.title ?? "Web Page"),
      snapshot: truncateToolResult(snapshot, 8_000),
      status: "complete",
      screenshot_base64: String(frame.screenshot_base64 ?? ""),
    });
    return { output: truncateToolResult(snapshot), didWork: true };
  }

  if (name === "browser_search") {
    const query = String(args.query ?? "").trim().slice(0, 240);
    if (!query) throw new InputError("Search query is required");
    await ensureCdpBrowser(sandbox);
    const page = await cdpAction(sandbox, { action: "navigate", url: `https://www.google.com/search?q=${encodeURIComponent(query)}` });
    const frame = await cdpAction(sandbox, { action: "screenshot" });
    const search = await executeSerperSearch(query);
    await appendEvent("browsing", {
      url: String(page.url ?? `https://www.google.com/search?q=${encodeURIComponent(query)}`),
      title: String(page.title ?? `Google Search: ${query}`),
      snapshot: truncateToolResult(search.text, 8_000),
      status: search.searchSucceeded ? "complete" : "unavailable",
      screenshot_base64: String(frame.screenshot_base64 ?? ""),
    });
    return { output: search.text, didWork: true };
  }

  if (name === "message_notify_user") {
    await appendEvent("message", { content: String(args.text ?? "") });
    return { output: "OK", didWork: false };
  }

  if (name === "message_ask_user") {
    await appendEvent("waiting", {
      message: String(args.text ?? ""),
      suggest_user_takeover: String(args.suggest_user_takeover ?? "none"),
    });
    return { output: "Waiting for user response.", didWork: false, waiting: true };
  }

  throw new InputError(`Unknown sandbox tool: ${name}`);
}

async function executePlanStep(
  prompt: string,
  step: BuildPlanStep,
  model: string,
  reasoningEffort: string,
  sandbox: any,
  appendEvent: (eventType: string, payload?: Record<string, unknown>) => Promise<void>,
): Promise<{ success: boolean; result: string; waiting?: boolean }> {
  const messages: Array<Record<string, unknown>> = [
    {
      role: "system",
      content: "You are the Build X Work executor. Execute only the current plan step using real tools. Start with message_notify_user, then use shell, file, browser, or search tools as needed. Inspect and verify results. Finish with complete_step. Never claim success without a real work-tool call.",
    },
    { role: "user", content: `User request: ${prompt}\n\nCurrent step: ${step.title}` },
  ];
  let workCount = 0;
  for (let iteration = 0; iteration < MAX_AGENT_ITERATIONS; iteration += 1) {
    const message = await askNvidia(model, messages, AGENT_TOOLS, "auto", reasoningEffort);
    messages.push(message);
    const calls = toolCallsOf(message);
    if (calls.length === 0) {
      messages.push({ role: "user", content: "Continue the current step and call a real tool or complete_step with an honest result." });
      continue;
    }
    for (const call of calls) {
      const fn = call.function && typeof call.function === "object" ? call.function as Record<string, unknown> : {};
      const name = String(fn.name ?? "");
      const callId = String(call.id ?? crypto.randomUUID());
      const args = parseToolArgs(call);
      const visibleArguments = Object.fromEntries(Object.entries(args).map(([key, value]) => [key, typeof value === "string" ? value.slice(0, 800) : value]));
      await appendEvent("tool", { tool_call_id: callId, name: name.startsWith("browser_") ? "browser" : name.startsWith("file_") ? "file" : name === "shell_execute" ? "shell" : "message", function: name, status: "running", arguments: visibleArguments });
      let output = "";
      let didWork = false;
      let waiting = false;
      let failure = "";
      try {
        if (name === "complete_step") {
          const success = Boolean(args.success);
          if (success && workCount === 0) {
            output = "Rejected: complete_step(success=true) requires a real shell/file/browser/search tool call first.";
            await appendEvent("tool", { tool_call_id: callId, name: "message", function: name, status: "completed", arguments: visibleArguments, result: output });
            messages.push({ role: "tool", tool_call_id: callId, name, content: output });
            continue;
          }
          output = String(args.result ?? "");
          await appendEvent("tool", { tool_call_id: callId, name: "message", function: name, status: "completed", arguments: visibleArguments, result: output });
          return { success, result: output, waiting: false };
        } else {
          const result = await executeBuildXTool(name, args, sandbox, appendEvent);
          output = result.output; didWork = result.didWork; waiting = Boolean(result.waiting);
          if (waiting) return { success: false, result: output, waiting: true };
          if (didWork) workCount += 1;
        }
      } catch (error) {
        failure = error instanceof Error ? error.message : String(error);
        output = `Tool failed: ${failure}`;
      }
      await appendEvent("tool", { tool_call_id: callId, name: name.startsWith("browser_") ? "browser" : name.startsWith("file_") ? "file" : name === "shell_execute" ? "shell" : "message", function: name, status: "completed", arguments: visibleArguments, result: truncateToolResult(output, 4_000), error: failure || undefined });
      messages.push({ role: "tool", tool_call_id: callId, name, content: truncateToolResult(output) });
    }
  }
  return { success: false, result: "Executor reached the maximum iteration count.", waiting: false };
}

async function replan(
  prompt: string,
  plan: BuildPlan,
  failedStep: BuildPlanStep,
  model: string,
  reasoningEffort: string,
): Promise<BuildPlanStep[]> {
  const message = await askNvidia(
    model,
    [
      { role: "system", content: "You are the Build X Work planner updating only the unfinished portion of a plan after failure. Preserve completed work conceptually and return replacement remaining steps by calling update_plan." },
      { role: "user", content: `Request: ${prompt}\nCurrent plan: ${JSON.stringify(plan)}\nFailed step: ${JSON.stringify(failedStep)}` },
    ],
    UPDATE_PLAN_TOOLS,
    "required",
    reasoningEffort,
  );
  const call = toolCallsOf(message).find((candidate) => {
    const fn = candidate.function && typeof candidate.function === "object" ? candidate.function as Record<string, unknown> : {};
    return fn.name === "update_plan";
  });
  if (!call) throw new Error("Planner did not submit update_plan");
  const args = parseToolArgs(call);
  const rawSteps = Array.isArray(args.steps) ? args.steps : [];
  return rawSteps.slice(0, 12).map((value, index) => {
    const raw = value && typeof value === "object" ? value as Record<string, unknown> : {};
    return { id: Number(raw.id ?? index + 1), title: String(raw.title ?? "Continue task"), status: index === 0 ? "in_progress" : "pending" };
  });
}

async function summarizePlan(
  prompt: string,
  plan: BuildPlan,
  results: string[],
  model: string,
  reasoningEffort: string,
): Promise<string> {
  const message = await askNvidia(
    model,
    [
      { role: "system", content: "Summarize the verified results of this Build X Work run. Mention real commands, browser pages, extracted content, and files when present. Do not invent evidence." },
      { role: "user", content: `Request: ${prompt}\nPlan: ${JSON.stringify(plan)}\nVerified step results:\n${results.join("\n\n")}` },
    ],
    [],
    "none",
    reasoningEffort,
  );
  return String(message.content ?? "").trim() || results.filter(Boolean).join("\n\n") || "Task completed.";
}

async function runPlanActLoop(
  prompt: string,
  initialPlan: BuildPlan,
  model: string,
  reasoningEffort: string,
  sandbox: any,
  appendEvent: (eventType: string, payload?: Record<string, unknown>) => Promise<void>,
): Promise<{ html: string | null; report: string; waiting: boolean; plan: BuildPlan }> {
  const plan = initialPlan;
  const results: string[] = [];
  await ensureCdpBrowser(sandbox);
  const initialFrame = await cdpAction(sandbox, { action: "screenshot" });
  const initialPage = await cdpAction(sandbox, { action: "view" });
  await appendEvent("browsing", {
    url: String(initialPage.url ?? "about:blank"),
    title: String(initialPage.title ?? "Chromium"),
    snapshot: "Chromium CDP session ready",
    status: "ready",
    screenshot_base64: String(initialFrame.screenshot_base64 ?? ""),
  });
  for (let index = 0; index < MAX_AGENT_ITERATIONS && index < plan.steps.length; index += 1) {
    const step = plan.steps[index];
    step.status = "in_progress";
    await appendEvent("planning", planPayload(plan));
    await appendEvent("thinking", {
      content: "Thinking",
      phase: `step_${index + 1}`,
      status: "running",
      elapsed_seconds: 0,
      effort: reasoningEffort,
    });
    const outcome = await executePlanStep(prompt, step, model, reasoningEffort, sandbox, appendEvent);
    await appendEvent("thinking", {
      content: "Thinking",
      phase: `step_${index + 1}`,
      status: "completed",
      elapsed_seconds: 0,
      effort: reasoningEffort,
    });
    if (outcome.waiting) {
      await appendEvent("message", { content: outcome.result });
      return { html: null, report: outcome.result, waiting: true, plan };
    }
    step.status = outcome.success ? "completed" : "failed";
    step.result = outcome.result;
    if (!outcome.success) {
      step.error = outcome.result;
      const replacement = await replan(prompt, plan, step, model, reasoningEffort);
      plan.steps.splice(index + 1, plan.steps.length - index - 1, ...replacement);
    }
    results.push(outcome.result);
    await appendEvent("planning", planPayload(plan));
  }
  const report = await summarizePlan(prompt, plan, results, model, reasoningEffort);
  let html: string | null = null;
  try {
    const content = new TextDecoder().decode(await sandbox.fs.downloadFile("workspace/index.html", 30));
    if (/<(?:!doctype\s+html|html)[\s>]/i.test(content)) html = content;
  } catch { /* no HTML artifact */ }
  return { html, report, waiting: false, plan };
}

function safeFailure(error: unknown): string {
  if (error instanceof DOMException && error.name === "TimeoutError") return "Operation timed out";
  if (error instanceof Error) {
    if (error instanceof NvidiaError) return error.message;
    const allowed = new Set([
      "Model generation failed",
      "Model returned no choices",
      "Model returned no content",
      "Model did not produce a standalone HTML deliverable",
      "Generated deliverable exceeds the server size limit",
    ]);
    if (allowed.has(error.message)) return error.message;
  }
  return "Work execution failed";
}

Deno.serve(async (req: Request) => {
  const preflight = handlePreflight(req);
  if (preflight) return preflight;
  if (!isOriginAllowed(req)) return jsonResponse(req, { error: "Origin is not allowed" }, 403);
  if (req.method !== "POST") return jsonResponse(req, { error: "Method not allowed" }, 405);

  let runId: string | null = null;
  let sandbox: any = null;
  let preserveSandbox = false;
  let daytona: Daytona | null = null;
  let admin: ReturnType<typeof createAdminClient> | null = null;
  let userId: string | null = null;
  let sequence = 0;
  let phase = "authenticate";

  const appendEvent = async (eventType: string, payload: Record<string, unknown> = {}) => {
    if (!admin || !runId || !userId) return;
    sequence += 1;
    const { error } = await admin.from("work_events").insert({
      run_id: runId,
      user_id: userId,
      sequence,
      event_type: eventType,
      payload,
    });
    if (error) throw new Error("Failed to persist work event");
    if (eventType === "planning" && admin && runId) {
      await admin.from("work_runs").update({ checkpoint: payload }).eq("id", runId);
    }
  };

  try {
    const { user } = await requireUser(req);
    userId = user.id;
    const { runId: requestedRunId, prompt, model, reasoningEffort } = parseBody(await req.json());
    phase = "initialize_run";
    admin = createAdminClient();
    runId = requestedRunId;

    const { error: insertError } = await admin.from("work_runs").insert({
      id: runId,
      user_id: userId,
      prompt,
      model,
      reasoning_effort: reasoningEffort,
      status: "queued",
    });
    if (insertError) throw new Error("Failed to persist work run");
    await appendEvent("queued", { model, reasoning_effort: reasoningEffort });

    phase = "planning";
    const { error: runningError } = await admin.from("work_runs").update({
      status: "running",
      started_at: new Date().toISOString(),
    }).eq("id", runId);
    if (runningError) throw new Error("Failed to persist running work state");
    const initialPlan = await createPlan(prompt, model, reasoningEffort);
    if (initialPlan.message) await appendEvent("message", { content: initialPlan.message });
    await appendEvent("planning", planPayload(initialPlan));
    if (initialPlan.steps.length === 0) {
      const directResult = { title: initialPlan.title, type: "conversation", entrypoint: null, files: [], previewHtml: null };
      await admin.from("work_runs").update({ status: "completed", result: directResult, completed_at: new Date().toISOString() }).eq("id", runId);
      await appendEvent("completed", { entrypoint: null, files: [] });
      await appendEvent("done", {});
      return jsonResponse(req, { run_id: runId, status: "completed", result: directResult, message: initialPlan.message }, 200);
    }

    const daytonaApiKey = getRequiredSecret("DAYTONA_API_KEY");
    const daytonaApiUrl = Deno.env.get("DAYTONA_API_URL")?.trim();
    const daytonaTarget = Deno.env.get("DAYTONA_TARGET")?.trim();
    daytona = new Daytona({
      apiKey: daytonaApiKey,
      ...(daytonaApiUrl ? { apiUrl: daytonaApiUrl } : {}),
      ...(daytonaTarget ? { target: daytonaTarget } : {}),
    });

    phase = "check_existing_daytona_sandbox";
    try {
      for await (const candidate of daytona.list({
        labels: { "build-x-user": userId },
      })) {
        const state = String(candidate.state ?? "").toLowerCase();
        if (state === "started" || state === "running") {
          sandbox = candidate;
          break;
        }
      }
    } catch (_) {}

    if (!sandbox) {
      phase = "create_daytona_sandbox";
      try {
        sandbox = await daytona.create({
          language: "typescript",
          labels: { "build-x-run": runId, "build-x-user": userId },
          autoStopInterval: 10,
          autoArchiveInterval: 60,
          autoDeleteInterval: 30,
        }, { timeout: 90 });
      } catch (createError) {
      // The SDK create timeout is client-side; Daytona can still finish
      // starting the server-side sandbox. Find it by this run's unique label
      // so it can be persisted and always cleaned up.
      phase = "recover_timed_out_daytona_sandbox";
      for await (const candidate of daytona.list({
        labels: { "build-x-run": runId },
      })) {
        sandbox = candidate;
        break;
      }
      if (!sandbox) throw createError;
      const sandboxState = String(sandbox.state ?? "").toLowerCase();
      if (sandboxState && sandboxState !== "started" && sandboxState !== "running") {
        phase = "start_recovered_daytona_sandbox";
        await sandbox.start(30);
      }
    }
    }
    const { error: sandboxUpdateError } = await admin.from("work_runs")
      .update({ sandbox_id: sandbox.id })
      .eq("id", runId);
    if (sandboxUpdateError) throw new Error("Failed to persist sandbox state");
    await appendEvent("sandbox_created", {
      sandbox_id: sandbox.id,
      state: sandbox.state ?? null,
    });

    phase = "init_sandbox_workspace";
    await sandbox.process.executeCommand("mkdir -p workspace", undefined, undefined, 30);

    phase = "execute_agent";
    await appendEvent("generating", { model, reasoning_effort: reasoningEffort });
    let agentResult: { html: string | null; report: string };
    try {
      const planResult = await runPlanActLoop(
        prompt,
        initialPlan,
        model,
        reasoningEffort,
        sandbox,
        appendEvent,
      );
      agentResult = { html: planResult.html, report: planResult.report };
      if (planResult.waiting) {
        preserveSandbox = true;
        await admin.from("work_runs").update({ status: "waiting", checkpoint: planPayload(planResult.plan) }).eq("id", runId);
        return jsonResponse(req, { run_id: runId, status: "waiting", message: planResult.report }, 200);
      }
      await appendEvent("planning", planPayload(planResult.plan));
    } catch (error) {
      if (!(error instanceof DOMException && error.name === "TimeoutError")) throw error;
      agentResult = {
        html: null,
        report: "The model request timed out while running in the sandbox.",
      };
      await appendEvent("warning", {
        code: "model_timeout",
        message: agentResult.report,
      });
    }

    const isExplicitWebTask = agentResult.html !== null ||
      /\b(create|build|make|generate)\b.*\b(website|web app|landing page|html|dashboard|portfolio|webpage|موقع|صفحة ويب|تطبيق ويب)\b/i.test(prompt);

    let html: string | null = agentResult.html;
    if (isExplicitWebTask && !html) {
      try {
        html = await generateHtml(
          `${prompt}\n\nAgent summary: ${agentResult.report}`,
          model,
          reasoningEffort,
        );
        await sandbox.fs.uploadFile(Buffer.from(html, "utf8"), "workspace/index.html", 60);
        await appendEvent("coding", {
          filePath: "workspace/index.html",
          newContent: html,
          oldContent: "",
          isNew: true,
        });
      } catch (_) {}
    }

    const reportMarkdown = `# Task Execution Report\n\nTask: ${prompt}\n\n## Agent Summary\n\n${agentResult.report}\n`;
    try {
      await sandbox.fs.uploadFile(Buffer.from(reportMarkdown, "utf8"), "workspace/research-report.md", 60);
    } catch (_) {}

    await appendEvent("message", {
      content: agentResult.report.trim() || "تم إنجاز المهمة بنجاح وفق الخطوات المحددة.",
    });

    const result = {
      title: prompt.length <= 80 ? prompt : `${prompt.slice(0, 77)}...`,
      type: isExplicitWebTask && html ? "web_app" : "task_completion",
      entrypoint: isExplicitWebTask && html ? "index.html" : "research-report.md",
      files: isExplicitWebTask && html ? ["index.html", "research-report.md"] : ["research-report.md"],
      previewHtml: isExplicitWebTask ? html : null,
    };
    const { error: updateError } = await admin.from("work_runs").update({
      status: "completed",
      result,
      completed_at: new Date().toISOString(),
    }).eq("id", runId);
    if (updateError) throw new Error("Failed to persist completed work run");
    await appendEvent("completed", {
      entrypoint: result.entrypoint,
      files: result.files,
    });
    await appendEvent("deliverable", {
      title: result.title,
      type: result.type,
      entrypoint: result.entrypoint,
      files: result.files,
      previewHtml: result.previewHtml,
      summary: agentResult.report.trim() || "The task was executed in the Daytona sandbox environment.",
    });
    await appendEvent("done", {});

    phase = "cleanup_daytona_sandbox";
    // Non-blocking cleanup in background so user receives completion immediately
    const sandboxToDelete = sandbox;
    sandbox = null;
    const cleanupPromise = (async () => {
      try {
        await daytona.delete(sandboxToDelete, 30, true);
        await appendEvent("sandbox_deleted", { sandbox_id: sandboxToDelete.id });
      } catch (e) {
        console.error("Background sandbox deletion error:", e);
      }
    })();
    // @ts-ignore EdgeRuntime is available in Supabase Edge Functions
    if (typeof EdgeRuntime !== "undefined" && EdgeRuntime?.waitUntil) {
      // @ts-ignore
      EdgeRuntime.waitUntil(cleanupPromise);
    }

    return jsonResponse(req, { run_id: runId, status: "completed", result }, 200);
  } catch (error) {
    if (error instanceof AuthError) return jsonResponse(req, { error: "Unauthorized" }, 401);
    if (error instanceof InputError || error instanceof SyntaxError) {
      return jsonResponse(req, { error: error.message }, 400);
    }

    const failure = safeFailure(error);
    const diagnostic = error instanceof Error
      ? error.message
        .replace(/bearer\s+\S+|nvapi-[\w-]+/gi, "[redacted]")
        .replace(/\b(?:[a-f0-9]{32,}|[A-Za-z0-9_-]{40,})\b/gi, "[redacted]")
        .replace(/\s+/g, " ")
        .slice(0, 300)
      : "Unknown error";
    console.error("work-run failed", {
      run_id: runId,
      phase,
      type: error instanceof Error ? error.name : "UnknownError",
      diagnostic,
    });
    if (admin && runId) {
      try {
        await appendEvent("failed", { message: failure, phase, diagnostic });
        await appendEvent("done", { error: failure });
        await admin.from("work_runs").update({
          status: "failed",
          error: `${failure} (${phase})`,
          completed_at: new Date().toISOString(),
        }).eq("id", runId);
      } catch {
        console.error("Failed to persist terminal work-run state", { run_id: runId });
      }
    }
    return jsonResponse(req, { error: failure, run_id: runId }, 502);
  } finally {
    if (daytona && sandbox && !preserveSandbox) {
      try {
        await daytona.delete(sandbox, 30, true);
      } catch {
        console.error("Failed to delete Daytona sandbox", { run_id: runId });
      }
    }
  }
});
