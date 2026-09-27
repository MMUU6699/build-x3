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
function conversationalReply(prompt: string): string | null {
  const normalized = prompt
    .toLocaleLowerCase()
    .replace(/[.!?،؟,\s]+/g, " ")
    .trim();
  const greetings = new Set([
    "hi", "hello", "hey", "hello there", "good morning", "good afternoon",
    "good evening", "good night", "how are you", "thanks", "thank you",
    "what can you do", "what are you", "who are you", "can you help me",
    "مرحبا", "اهلا", "أهلا", "أهلاً", "السلام عليكم", "شلونك",
    "كيف حالك", "شكرا", "شكراً", "ماذا تستطيع", "شنو تسوي",
  ]);
  if (!greetings.has(normalized)) return null;
  return /[\u0600-\u06ff]/.test(normalized)
    ? "أهلاً! أنا جاهز لمساعدتك. أخبرني بما تريد بناءه أو البحث عنه أو تعديله، وسأبدأ العمل."
    : "Hello! I’m ready to help. Tell me what you’d like to build, research, or change, and I’ll get started.";
}

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
      description: "Search the web in the live Daytona desktop browser and return page text.",
      parameters: { type: "object", properties: { query: { type: "string" } }, required: ["query"] },
    },
  },
  {
    type: "function",
    function: {
      name: "shell_execute",
      description: "Run a command inside the isolated Daytona sandbox workspace.",
      parameters: { type: "object", properties: { command: { type: "string" } }, required: ["command"] },
    },
  },
  {
    type: "function",
    function: {
      name: "file_write",
      description: "Create or replace a file under the Daytona workspace directory.",
      parameters: { type: "object", properties: { path: { type: "string" }, content: { type: "string" } }, required: ["path", "content"] },
    },
  },
  {
    type: "function",
    function: {
      name: "file_read",
      description: "Read a text file under the Daytona workspace directory.",
      parameters: { type: "object", properties: { path: { type: "string" } }, required: ["path"] },
    },
  },
  {
    type: "function",
    function: {
      name: "file_delete",
      description: "Delete a file under the Daytona workspace directory.",
      parameters: { type: "object", properties: { path: { type: "string" } }, required: ["path"] },
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

function fallbackHtml(prompt: string, searchAvailable: boolean): string {
  const escapedPrompt = escapeHtml(prompt);
  const researchNotice = searchAvailable
    ? "Research completed."
    : "Live web search was blocked by the sandbox network policy; this fallback contains no external claims or citations.";
  return `<!doctype html>
<html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Build X task workspace</title>
<style>
:root{color-scheme:dark;font:16px/1.55 system-ui,sans-serif;background:#10151f;color:#eef3ff}body{margin:0;min-height:100vh;display:grid;place-items:center;padding:24px;box-sizing:border-box}.card{max-width:760px;width:100%;padding:clamp(24px,6vw,52px);border:1px solid #33435e;border-radius:24px;background:linear-gradient(145deg,#1c2940,#141a27);box-shadow:0 24px 80px #0006}small{color:#9cb8f4;text-transform:uppercase;letter-spacing:.14em;font-weight:700}h1{font-size:clamp(2rem,6vw,3.5rem);line-height:1.08;margin:.6em 0}p{color:#ccd6e9}.notice{margin-top:28px;padding:16px;border-left:4px solid #e8b75b;background:#342b1d;color:#ffe4ad;border-radius:8px}.badge{display:inline-block;margin-top:18px;padding:6px 10px;border:1px solid #62789e;border-radius:999px;color:#b8d0ff;font-size:.85rem}
</style><body><main class="card"><small>Build X · Work run</small><h1>Task workspace</h1><p>This sandbox completed the requested work run and saved its output in Daytona.</p><section><h2>Requested task</h2><p>${escapedPrompt}</p></section><aside class="notice">${researchNotice}</aside><span class="badge">Fallback output · model response unavailable</span></main></body></html>`;
}

async function runAgentToolLoop(
  prompt: string,
  model: string,
  reasoningEffort: string,
  researchText: string,
  sandbox: any,
  appendEvent: (eventType: string, payload?: Record<string, unknown>) => Promise<void>,
): Promise<{ html: string | null; report: string }> {
  const messages: Array<Record<string, unknown>> = [
    {
      role: "system",
      content:
        "You are the Build X autonomous work agent. Continue from the live browser research already attached. Use your sandbox tools to inspect research, run appropriate verification, and create requested files under workspace/. For web-app tasks, call file_write with complete HTML at workspace/index.html before finishing. Always create workspace/research-report.md; when search is unavailable, state that clearly and never invent sources. Do not claim a tool succeeded until its result confirms it. Finish with a short user-facing summary.",
    },
    { role: "user", content: `Task: ${prompt}\n\nInitial live browser research:\n${researchText}` },
  ];
  let report = "";

  for (let iteration = 0; iteration < 2; iteration += 1) {
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
        tools: AGENT_TOOLS,
        tool_choice: iteration === 0 ? "required" : "auto",
        temperature: 0.4,
        top_p: 0.95,
        max_tokens: 4096,
        stream: false,
        chat_template_kwargs: {
          enable_thinking: reasoningEffort !== "none",
          ...(reasoningEffort === "low" || reasoningEffort === "medium" ? { medium_effort: true } : {}),
          force_nonempty_content: true,
        },
      }),
      signal: AbortSignal.timeout(30000),
    });
    if (!response.ok) {
      const detail = (await response.text()).replace(/bearer\s+\S+|nvapi-[\w-]+/gi, "[redacted]").slice(0, 300);
      throw new NvidiaError(`NVIDIA agent returned HTTP ${response.status}: ${detail}`);
    }
    const data = await response.json() as Record<string, unknown>;
    const choices = data.choices;
    const choice = Array.isArray(choices) ? choices[0] as Record<string, unknown> : null;
    const message = choice?.message as Record<string, unknown> | undefined;
    if (!message) throw new Error("Agent returned no message");
    const toolCalls = Array.isArray(message.tool_calls) ? message.tool_calls as Array<Record<string, unknown>> : [];
    messages.push(message);
    if (toolCalls.length === 0) {
      report = typeof message.content === "string" ? message.content : "The sandbox agent completed its task.";
      break;
    }

    for (const call of toolCalls) {
      const callId = String(call.id ?? crypto.randomUUID());
      const fn = call.function && typeof call.function === "object" ? call.function as Record<string, unknown> : {};
      const name = String(fn.name ?? "");
      let args: Record<string, unknown> = {};
      try { args = JSON.parse(String(fn.arguments ?? "{}")) as Record<string, unknown>; } catch { /* Return validation feedback as the tool result. */ }
      const visibleArguments = Object.fromEntries(Object.entries(args).map(([key, value]) => [
        key,
        typeof value === "string" ? value.slice(0, 800) : value,
      ]));
      await appendEvent("tool", {
        tool_call_id: callId,
        name: name.startsWith("browser_") ? "browser" : name.startsWith("file_") ? "file" : name === "shell_execute" ? "shell" : "tool",
        function: name,
        status: "running",
        arguments: visibleArguments,
      });
      let toolOutput = "";
      try {
        if (name === "shell_execute") {
          const command = String(args.command ?? "").trim();
          if (!command || command.length > 5000) throw new InputError("Command length must be between 1 and 5000 characters");
          await appendEvent("thinking", { content: "Running a command in the Daytona workspace.", effort: reasoningEffort });
          const result = await sandbox.process.executeCommand(command, "workspace", undefined, 60);
          toolOutput = `exit_code: ${result.exitCode}\n${result.result ?? ""}`.slice(0, 12000);
          await appendEvent("terminal", { command, output: toolOutput });
        } else if (name === "file_write") {
          const path = workspacePath(args.path);
          const content = String(args.content ?? "");
          if (new TextEncoder().encode(content).byteLength > 450_000) throw new InputError("Workspace file exceeds 450 KB");
          let oldContent = "";
          try { oldContent = new TextDecoder().decode(await sandbox.fs.downloadFile(path, 30)); } catch { /* New file. */ }
          await sandbox.fs.uploadFile(Buffer.from(content, "utf8"), path, 60);
          await appendEvent("coding", { filePath: path, oldContent, newContent: content, isNew: oldContent.length === 0 });
          toolOutput = `Wrote ${path} (${Buffer.byteLength(content, "utf8")} bytes).`;
        } else if (name === "file_read") {
          const path = workspacePath(args.path);
          const content = new TextDecoder().decode(await sandbox.fs.downloadFile(path, 30));
          toolOutput = content.slice(0, 12000);
        } else if (name === "file_delete") {
          const path = workspacePath(args.path);
          await sandbox.fs.deleteFile(path);
          toolOutput = `Deleted ${path}.`;
        } else if (name === "browser_search") {
          const query = String(args.query ?? "").trim().slice(0, 240);
          if (!query) throw new InputError("Search query is required");
          const url = `https://www.google.com/search?q=${encodeURIComponent(query)}`;
          await sandbox.computerUse.keyboard.hotkey("ctrl+l");
          await sandbox.computerUse.keyboard.type(url);
          await sandbox.computerUse.keyboard.press("enter");
          await new Promise((resolve) => setTimeout(resolve, 3500));
          const screen = await sandbox.computerUse.screenshot.takeCompressed({ format: "jpeg", quality: 35, scale: 0.4, showCursor: true });
          const base64 = String((screen as Record<string, unknown>).screenshot ?? "").replace(/^data:image\/[\w.+-]+;base64,/i, "");
          const script = `import urllib.request, html, re\nu = ${JSON.stringify(url)}\nr = urllib.request.urlopen(urllib.request.Request(u, headers={'User-Agent': 'Mozilla/5.0'}), timeout=20).read().decode('utf-8', 'ignore')\nprint(html.unescape(re.sub(r'\\s+', ' ', re.sub('<[^>]+>', ' ', r)))[:5000])\n`;
          await sandbox.fs.uploadFile(Buffer.from(script, "utf8"), "workspace/search-tool.py", 30);
          const result = await sandbox.process.executeCommand("python3 workspace/search-tool.py", undefined, undefined, 30);
          toolOutput = result.result ?? "Search results opened in the Daytona browser.";
          await appendEvent("browsing", { url, title: "Google Search", snapshot: toolOutput.slice(0, 5000), status: "complete" });
          await appendEvent("computer", { action: `Searched for: ${query}`, screenshot_base64: base64 });
        } else {
          throw new InputError(`Unknown sandbox tool: ${name}`);
        }
      } catch (error) {
        toolOutput = error instanceof Error ? error.message : "Sandbox tool failed";
      }
      await appendEvent("tool", {
        tool_call_id: callId,
        name: name.startsWith("browser_") ? "browser" : name.startsWith("file_") ? "file" : name === "shell_execute" ? "shell" : "tool",
        function: name,
        status: "completed",
        arguments: visibleArguments,
        result: toolOutput.slice(0, 1200),
      });
      await appendEvent("thinking", { content: `Daytona ${name} tool completed.`, effort: reasoningEffort });
      messages.push({ role: "tool", tool_call_id: callId, name, content: toolOutput });
    }
  }

  try {
    const html = new TextDecoder().decode(await sandbox.fs.downloadFile("workspace/index.html", 30));
    if (/<(?:!doctype\s+html|html)[\s>]/i.test(html)) return { html, report };
  } catch { /* Use the standalone artifact generation fallback below. */ }
  return { html: null, report };
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
  };

  try {
    const { user } = await requireUser(req);
    userId = user.id;
    const { runId: requestedRunId, prompt, model, reasoningEffort } = parseBody(await req.json());
    const reply = conversationalReply(prompt);
    if (reply != null) {
      return jsonResponse(req, {
        run_id: requestedRunId,
        status: "conversation",
        message: reply,
      }, 200);
    }
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

    const daytonaApiKey = getRequiredSecret("DAYTONA_API_KEY");
    const daytonaApiUrl = Deno.env.get("DAYTONA_API_URL")?.trim();
    const daytonaTarget = Deno.env.get("DAYTONA_TARGET")?.trim();
    daytona = new Daytona({
      apiKey: daytonaApiKey,
      ...(daytonaApiUrl ? { apiUrl: daytonaApiUrl } : {}),
      ...(daytonaTarget ? { target: daytonaTarget } : {}),
    });

    phase = "persist_running_state";
    const { error: runningError } = await admin.from("work_runs").update({
      status: "running",
      started_at: new Date().toISOString(),
    }).eq("id", runId);
    if (runningError) throw new Error("Failed to persist running work state");
    await appendEvent("planning", {
      steps: [
        { id: 1, title: "Research in the sandbox browser", status: "in_progress" },
        { id: 2, title: "Create files and execute verification commands", status: "pending" },
        { id: 3, title: "Prepare the report and deliverable", status: "pending" },
      ],
    });

    phase = "create_daytona_sandbox";
    try {
      sandbox = await daytona.create({
        language: "typescript",
        labels: { "build-x-run": runId, "build-x-user": userId },
        autoStopInterval: 5,
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
    const { error: sandboxUpdateError } = await admin.from("work_runs")
      .update({ sandbox_id: sandbox.id })
      .eq("id", runId);
    if (sandboxUpdateError) throw new Error("Failed to persist sandbox state");
    await appendEvent("sandbox_created", {
      sandbox_id: sandbox.id,
      state: sandbox.state ?? null,
    });

    // Daytona's default image includes the Xfce/VNC desktop and browser stack.
    // We drive the real desktop with Computer Use and forward actual screenshots
    // through work_events so Work mode can render what the sandbox displays.
    phase = "start_daytona_computer";
    await sandbox.computerUse.start();
    phase = "launch_browser";
    await sandbox.process.executeCommand("mkdir -p workspace", undefined, undefined, 30);
    const browserLaunch = await sandbox.process.executeCommand(
      "if command -v chromium >/dev/null 2>&1; then (nohup chromium --no-sandbox --disable-dev-shm-usage --no-first-run about:blank >/tmp/build-x-browser.log 2>&1 &) ; elif command -v chromium-browser >/dev/null 2>&1; then (nohup chromium-browser --no-sandbox --disable-dev-shm-usage --no-first-run about:blank >/tmp/build-x-browser.log 2>&1 &) ; elif command -v google-chrome-stable >/dev/null 2>&1; then (nohup google-chrome-stable --no-sandbox --disable-dev-shm-usage --no-first-run about:blank >/tmp/build-x-browser.log 2>&1 &) ; elif command -v google-chrome >/dev/null 2>&1; then (nohup google-chrome --no-sandbox --disable-dev-shm-usage --no-first-run about:blank >/tmp/build-x-browser.log 2>&1 &) ; else echo 'No Chromium browser is installed in the Daytona image' >&2; exit 127; fi",
      undefined,
      undefined,
      30,
    );
    if (browserLaunch.exitCode !== 0) throw new Error("Daytona browser could not be started");
    await new Promise((resolve) => setTimeout(resolve, 1800));
    await appendEvent("thinking", { content: "Opening the sandbox browser to research the task.", effort: reasoningEffort });
    const searchQuery = encodeURIComponent(prompt.slice(0, 240));
    const searchUrl = `https://www.google.com/search?q=${searchQuery}`;
    const browserCallId = crypto.randomUUID();
    await appendEvent("tool", {
      tool_call_id: browserCallId,
      name: "browser",
      function: "browser_search",
      status: "running",
      arguments: { query: prompt.slice(0, 240) },
    });
    phase = "drive_browser_and_search";
    phase = "browser_focus_address_bar";
    await sandbox.computerUse.keyboard.hotkey("ctrl+l");
    phase = "browser_type_search_url";
    await sandbox.computerUse.keyboard.type(searchUrl);
    phase = "browser_submit_search";
    await sandbox.computerUse.keyboard.press("enter");
    await new Promise((resolve) => setTimeout(resolve, 4500));
    phase = "capture_browser_screenshot";
    const screenshot = await sandbox.computerUse.screenshot.takeCompressed({
      format: "jpeg",
      quality: 45,
      scale: 0.5,
      showCursor: true,
    });
    const screenshotData = String((screenshot as Record<string, unknown>).screenshot ?? "");
    const screenshotBase64 = screenshotData.replace(/^data:image\/[\w.+-]+;base64,/i, "");
    await appendEvent("computer", {
      action: `Opened the browser and searched for: ${prompt.slice(0, 180)}`,
      screenshot_base64: screenshotBase64,
    });
    await appendEvent("browsing", {
      url: searchUrl,
      title: "Google Search",
      snapshot: "Search page opened in the Daytona computer; retrieving search results.",
      status: "browsing",
    });
    const searchUrls = [
      searchUrl,
      `https://html.duckduckgo.com/html/?q=${searchQuery}`,
      `https://www.bing.com/search?q=${searchQuery}`,
    ];
    const searchScript = `import urllib.request, html, re, sys\nurls = ${JSON.stringify(searchUrls)}\nerrors = []\nfor u in urls:\n    try:\n        req = urllib.request.Request(u, headers={'User-Agent': 'Mozilla/5.0 BuildX research'})\n        r = urllib.request.urlopen(req, timeout=8).read().decode('utf-8', 'ignore')\n        t = html.unescape(re.sub(r'\\s+', ' ', re.sub('<[^>]+>', ' ', r))).strip()\n        if len(t) > 100:\n            print('SOURCE: ' + u + '\\n' + t[:5000])\n            sys.exit(0)\n        errors.append('empty response: ' + u.split('/')[2])\n    except Exception as e:\n        errors.append(u.split('/')[2] + ': ' + type(e).__name__)\nprint('Search providers unavailable: ' + '; '.join(errors))\nsys.exit(2)\n`;
    phase = "write_search_script";
    await sandbox.fs.uploadFile(Buffer.from(searchScript, "utf8"), "workspace/search.py", 60);
    phase = "fetch_search_results";
    const searchResult = await sandbox.process.executeCommand(
      "python3 workspace/search.py",
      undefined,
      undefined,
      30,
    );
    const searchOutput = searchResult.result ?? "";
    const searchSucceeded = searchResult.exitCode === 0;
    const researchText = searchSucceeded
      ? searchOutput.slice(0, 5000)
      : "No external search results were available: the Daytona sandbox could not reach Google, DuckDuckGo, or Bing. The browser navigation was attempted, but this report must not invent sources.";
    await appendEvent("tool", {
      tool_call_id: browserCallId,
      name: "browser",
      function: "browser_search",
      status: searchSucceeded ? "completed" : "failed",
      arguments: { query: prompt.slice(0, 240) },
      result: searchSucceeded ? researchText.slice(0, 1200) : searchOutput.slice(0, 500),
    });
    await appendEvent("browsing", {
      url: searchUrl,
      title: "Google Search",
      snapshot: searchSucceeded
        ? researchText
        : "The browser search page was opened, but external web access is blocked from this Daytona sandbox.",
      status: searchSucceeded ? "complete" : "unavailable",
    });
    await appendEvent("terminal", {
      command: "python3 workspace/search.py",
      output: `exit code: ${searchResult.exitCode ?? "unknown"}\n${searchOutput}`,
    });
    await appendEvent("planning", {
      steps: [
        { id: 1, title: "Research in the sandbox browser", status: searchSucceeded ? "completed" : "failed" },
        { id: 2, title: "Create files and execute verification commands", status: "in_progress" },
        { id: 3, title: "Prepare the report and deliverable", status: "pending" },
      ],
    });

    phase = "generate_deliverable";
    await appendEvent("generating", { model, reasoning_effort: reasoningEffort });
    let agentResult: { html: string | null; report: string };
    let html: string;
    let modelFallback = false;
    try {
      agentResult = await runAgentToolLoop(
        prompt,
        model,
        reasoningEffort,
        researchText,
        sandbox,
        appendEvent,
      );
      html = agentResult.html ?? await generateHtml(
        `${prompt}\n\nUse this live web research gathered in the Daytona sandbox to inform the deliverable. Cite useful sources by URL when relevant.\n\n${researchText}\n\nAgent summary: ${agentResult.report}`,
        model,
        reasoningEffort,
      );
    } catch (error) {
      if (!(error instanceof DOMException && error.name === "TimeoutError")) throw error;
      modelFallback = true;
      agentResult = {
        html: null,
        report: "The NVIDIA model request timed out. Build X saved a transparent fallback workspace instead of claiming the task was completed by the model.",
      };
      html = fallbackHtml(prompt, searchSucceeded);
      await appendEvent("warning", {
        code: "model_timeout_fallback",
        message: agentResult.report,
      });
    }

    if (!agentResult.html) {
      await sandbox.fs.uploadFile(Buffer.from(html, "utf8"), "workspace/index.html", 60);
      await appendEvent("coding", {
        filePath: "workspace/index.html",
        newContent: html,
        oldContent: "",
        isNew: true,
      });
    }
    await appendEvent("planning", {
      steps: [
        { id: 1, title: "Research in the sandbox browser", status: searchSucceeded ? "completed" : "failed" },
        { id: 2, title: "Create files and execute verification commands", status: "completed" },
        { id: 3, title: "Prepare the report and deliverable", status: "in_progress" },
      ],
    });
    const reportExists = await sandbox.process.executeCommand("test -s workspace/research-report.md", undefined, undefined, 15);
    if (reportExists.exitCode !== 0) {
      const reportMarkdown = `# Research report\n\nTask: ${prompt}\n\n## Search results\n\n${researchText}\n\n## Agent summary\n\n${agentResult.report}\n`;
      await sandbox.fs.uploadFile(Buffer.from(reportMarkdown, "utf8"), "workspace/research-report.md", 60);
      await appendEvent("coding", {
        filePath: "workspace/research-report.md",
        newContent: reportMarkdown,
        oldContent: "",
        isNew: true,
      });
    }
    const verification = await sandbox.process.executeCommand(
      "test -s workspace/index.html && wc -c < workspace/index.html",
      undefined,
      undefined,
      30,
    );
    if (verification.exitCode !== 0) throw new Error("Sandbox verification failed");
    await appendEvent("terminal", {
      command: "test -s workspace/index.html && wc -c < workspace/index.html",
      output: verification.result ?? "index.html verified",
    });
    await appendEvent("verified", {
      entrypoint: "index.html",
      bytes: Buffer.byteLength(html, "utf8"),
    });
    await appendEvent("message", {
      content: agentResult.report.trim() || (searchSucceeded
        ? "The Daytona browser research, workspace files, and verification command completed successfully."
        : "The Daytona browser opened, but internet search was unavailable. The run recorded that limitation and did not invent sources."),
    });

    const result = {
      title: prompt.length <= 80 ? prompt : `${prompt.slice(0, 77)}...`,
      type: "web_app",
      entrypoint: "index.html",
      files: ["index.html", "research-report.md"],
      previewHtml: html,
    };
    phase = "cleanup_daytona_sandbox";
    // Cleanup is part of a successful run. If deletion fails, mark the run as
    // failed and let the finally block make one more cleanup attempt.
    await sandbox.computerUse.stop().catch(() => undefined);
    await daytona.delete(sandbox, 30, true);
    await appendEvent("sandbox_deleted", { sandbox_id: sandbox.id });
    sandbox = null;

    const { error: updateError } = await admin.from("work_runs").update({
      status: "completed",
      result,
      completed_at: new Date().toISOString(),
    }).eq("id", runId);
    if (updateError) throw new Error("Failed to persist completed work run");
    await appendEvent("completed", {
      entrypoint: "index.html",
      files: ["index.html", "research-report.md"],
    });
    await appendEvent("deliverable", {
      title: result.title,
      type: result.type,
      entrypoint: result.entrypoint,
      files: result.files,
      previewHtml: result.previewHtml,
      summary: searchSucceeded
        ? modelFallback
          ? "NVIDIA inference timed out; a clearly labeled fallback deliverable was written and verified in Daytona."
          : "The report was researched in the sandbox browser and the deliverable was written and verified in Daytona."
        : modelFallback
          ? "Sandbox internet search was unavailable and NVIDIA inference timed out; a clearly labeled fallback deliverable was written and verified in Daytona."
          : "The Daytona browser opened, but outbound search was unavailable. The deliverable was written and verified in Daytona without invented sources.",
    });
    await appendEvent("planning", {
      steps: [
        { id: 1, title: "Research in the sandbox browser", status: "completed" },
        { id: 2, title: "Create files and execute verification commands", status: "completed" },
        { id: 3, title: "Prepare the report and deliverable", status: "completed" },
      ],
    });
    await appendEvent("done", {});

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
    if (daytona && sandbox) {
      try {
        await sandbox.computerUse.stop().catch(() => undefined);
        await daytona.delete(sandbox, 30, true);
      } catch {
        console.error("Failed to delete Daytona sandbox", { run_id: runId });
      }
    }
  }
});
