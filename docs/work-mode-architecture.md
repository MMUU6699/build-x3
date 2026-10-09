# Build X Work Mode — ai-manus architecture map

Status: research synthesis and target implementation contract, updated
2026-09-29.

This document separates three things that must not be conflated:

- **ai-manus behavior**: behavior observed in the cited ai-manus source;
- **current Build X**: behavior present in the current `kelivo` working tree;
- **target Build X**: the architecture required to port the behavior. Target
  items are design requirements, not claims that the current code implements or
  that a run has verified them.

## Research evidence

The ai-manus source reviewed was the local checkout at
`C:/Users/musta/Downloads/New folder (6)/ai-manus`, including:

- `backend/app/domain/services/flows/plan_act.py`
- `backend/app/domain/services/agents/{planner,execution,base}.py`
- `backend/app/domain/services/tools/{browser,shell,file,search,message}.py`
- `backend/app/infrastructure/external/browser/{browser_use_browser,playwright_browser}.py`
- `backend/app/infrastructure/external/sandbox/docker_sandbox.py`
- `backend/app/domain/models/{event,plan,agent_output}.py`
- the cited Vue plan, tool, status, computer, and takeover components.

The current Build X implementation reviewed was the corresponding code under
`kelivo`, especially:

- `supabase/functions/work-run/index.ts`;
- `lib/core/services/work/{work_agent_service,work_agent_event}.dart`;
- `lib/core/providers/work_mode_provider.dart`;
- `lib/features/work/{pages/work_surface_view.dart,widgets/work_live_computer_view.dart,widgets/work_planning_card.dart}`;
- `supabase/migrations/20260925000100_create_work_runtime.sql`.

Current-code facts used below: the Edge Function now performs model-generated
`create_plan`, per-step executor loops, failure-driven `update_plan`, Daytona
shell/file operations, and a sandbox-local CDP helper for Chromium. It persists
plan checkpoints in `work_runs.checkpoint`. The mobile service subscribes to
Realtime, backfills ordered `work_events`, and refuses to fabricate a client-side
Work fallback when the hosted runtime is unavailable. Durable user-input resume,
interactive signed takeover, and an always-on worker remain incomplete.

## Literal subsystem mapping

Every row uses the literal mapping form: **ai-manus does X in `file/module` →
Build X will do X via `mechanism`, because `reason`; current Build X gap:
`gap`**. “Will” identifies the target contract only.

| Subsystem | Literal mapping |
|---|---|
| Plan creation | ai-manus does structured plan creation in `backend/app/domain/services/agents/planner.py:create_plan` using `create_plan` and `PlanOutput` → Build X does structured plan creation via `createPlan()` and `PLANNER_TOOLS` in `supabase/functions/work-run/index.ts`, persisting a `planning` event, because the plan is the boundary between answering and doing work; current gap: planner output is not yet a separately claimed worker job. |
| Direct answer decision | ai-manus does no-work answers through the planner/Plan-Act flow in `backend/app/domain/services/prompts/planner.py` and `flows/plan_act.py` → Build X routes a planner result with zero steps to `message` plus `done` without creating a Daytona sandbox, because conversational answers must not create work state; the retained prompt classifier is test/UI compatibility code and is not an execution authority. |
| Direct tool calls | ai-manus gives planning no executor tools and gives execution tools only for the active step in `agents/planner.py`, `agents/execution.py`, and `agents/base.py:_tool_loop` → Build X exposes work tools only inside `executePlanStep()`, because every call must be attributable to a step; the planner receives only `PLANNER_TOOLS`. |
| Step sequencing | ai-manus advances `Plan.get_next_step()` one step at a time in `flows/plan_act.py` → Build X persists plan state through `work_runs.checkpoint` on every `planning` event, because an Edge invocation can end between tools; current gap: the invocation does not yet claim and resume a checkpoint in a separate worker. |
| Step completion guard | ai-manus rejects `complete_step(success=true)` without a work-tool call in `agents/execution.py` → Build X will enforce a per-step successful-tool guard in `executePlanStep()`, because model prose is not evidence; current Build X gap: failed-tool evidence is in the local step call, not yet persisted as a separate audit field. |
| Replanning | ai-manus calls `PlannerAgent.update_plan` only after a failed step or `success=false` in `flows/plan_act.py:step_needs_replan` → Build X will call `replan()` with `UPDATE_PLAN_TOOLS` only for those outcomes and preserve completed steps, because successful work must not be repeated; current Build X gap: replan is request-local until the worker/resume split is added. |
| Waiting and resume | ai-manus emits `WaitEvent` for `message_ask_user` and resumes the same step through `ExecutionAgent.resume_step` → Build X will persist `waiting` state, the checkpoint, and an authenticated resume action, because clarification and takeover are pauses rather than completion; current Build X gap: the Edge Function writes a `waiting` event but the client has no matching resume protocol. |
| Finalization | ai-manus summarizes through `ExecutionAgent.summarize` and completes through `deliver_result` in `agents/execution.py` → Build X will require `deliver_result` after all steps and emit `deliverable` then `done`, because the answer must be grounded in tool results and saved artifacts; current Build X gap: the Edge Function can synthesize a report after the loop without proving that `deliver_result` was called and can generate fallback HTML. |
| Browser tool surface | ai-manus does navigate, view, click, input, mouse, key, select, scroll, JavaScript, console, and screenshot operations in `domain/services/tools/browser.py` → Build X will expose the implemented navigate/view/click/input/scroll/screenshot subset through `executeBuildXTool()` and the CDP helper, because fetch and a screenshot cannot preserve interactive browser state; current Build X gap: mouse, key, select, JavaScript, and console operations remain deferred. |
| Browser implementation | ai-manus dispatches browser-use/CDP or Playwright-CDP operations through `BrowserSession` in `infrastructure/external/browser/*` → Build X will run Chromium with a remote-debugging endpoint and a minimal CDP helper inside Daytona, because the target excludes a full desktop Computer Use runtime but still requires real browser control; current Build X gap: the helper is sandbox-local and has no signed browser preview/takeover endpoint. |
| Shell tool | ai-manus runs commands and interactive sessions through `ShellToolkit` and `Sandbox.exec_command/view_shell/wait/write/kill` in `tools/shell.py` and `domain/external/sandbox.py` → Build X provides Daytona command execution plus real stdout/stderr events, because cwd, stdout, and process state are part of the work result; current gap: the hosted path has one-off `process.executeCommand` calls rather than durable interactive sessions. |
| File tool | ai-manus provides read, write, replacement, content search, name search, upload, and download in `tools/file.py` → Build X will provide bounded, workspace-safe Daytona file operations with real old/new content, because file changes must be inspectable and replayable; current Build X gap: upload/download/exists/list and live terminal polling remain deferred. |
| Search | ai-manus delegates `info_search_web` to its configured `SearchEngine` in `tools/search.py` → Build X will keep search as a distinct server-side provider and use browser navigation for opening source pages, because search results are discovery data rather than verified page state; current Build X gap: Serper search is server-side, but its Google-looking event is not a Chrome navigation and has no source-page verification guarantee. |
| MCP tools | ai-manus discovers and invokes MCP tools through `domain/services/tools/mcp.py` and the agent task runner → Build X will expose only authenticated, allowlisted MCP tools through the same executor/event contract, because runtime-discovered tools must still be attributable and replayable; current Build X gap: `work-run` has no MCP tool registration or invocation path. |
| Event schema | ai-manus serializes typed `PlanEvent`, `StepEvent`, `ToolEvent`, `MessageEvent`, `WaitEvent`, `TerminalUpdateEvent`, `FileUpdateEvent`, `TitleEvent`, and `DoneEvent` in `domain/models/event.py` → Build X will persist an explicit versioned equivalent in `work_events`, because reconnecting clients need typed state rather than inferred UI state; current Build X gap: `event_type` and JSON payload are open-ended, and the Flutter parser does not model all server lifecycle events such as `queued`, `sandbox_created`, `waiting`, or `sandbox_deleted`. |
| Event ordering | ai-manus yields tool `CALLING`, executes the tool, then yields `CALLED`, with live shell output from `agents/base.py:_tool_loop` → Build X will allocate an atomic per-run sequence and emit running, live-output, and completed events in order, because timestamps are not a replay protocol; current Build X gap: the Edge Function increments a request-local `sequence`, and command output is emitted only after one-off execution completes. |
| Realtime subscription | ai-manus sends events through its WebSocket routes and frontend session subscription in `ws_routes.py` and `frontend/src/api/chatWs.ts` → Build X subscribes to Realtime and backfills `work_events` ordered by sequence, because clients can connect after events already exist; current gap: reconnect logic still lives in the mobile service rather than a dedicated replay API. |
| Plan UI | ai-manus renders a collapsible plan and status icons in `PlanPanel.vue` and `PlanStepIcon.vue` → Build X renders backend `WorkPlanningEvent` state in the Work widgets, because progress must reflect the run; current gap: legacy provider helpers remain for local widget tests but are not used to fabricate hosted run events. |
| Tool chips | ai-manus renders active and completed tool calls from `ToolUse.vue` and `useToolShimmer.ts` → Build X renders chips from persisted `WorkToolEvent` lifecycle payloads, because a chip is evidence only when tied to a call result; current gap: the hosted schema still has no explicit event-version field. |
| Thinking | ai-manus drives status from actual agent events and manages the Lottie lifecycle in `LiveStatusCanvas.vue` → Build X will drive the indicator from persisted model/tool progress events, because an idle spinner must not imply activity; current Build X gap: hosted `thinking` events are mostly generic acknowledgements and are not a persisted reasoning-token trace. |
| Computer panel | ai-manus switches browser, shell, file, and search viewers from real tool payloads in `ComputerPanelContent.vue` and `toolViews/*` → Build X will select a viewer from the latest real event and retain per-tool history, because each viewer has different payload semantics; current Build X gap: `work_live_computer_view.dart` includes placeholder browser, terminal, and coding states when live data is absent. |
| Scrubber | ai-manus maps a playhead to recorded tool events and supports previous/next, hover time, and `Jump to live` in `ComputerPanelContent.vue` → Build X will scrub persisted event history without rerunning tools, because replay must be read-only; current Build X gap: the Flutter controls operate on in-memory provider lists and have no persisted-history backfill. |
| Takeover | ai-manus exposes Take control and an interactive browser overlay in `BrowserToolView.vue` and `TakeOverView.vue` → Build X will persist a takeover request and issue a short-lived signed browser endpoint only after acceptance, because human input is privileged; current Build X gap: Build X can emit `suggest_user_takeover: browser` in a waiting payload but has no signed endpoint, interactive overlay, or resume path. |
| Sandbox lifecycle | ai-manus starts Docker supervisor services and destroys the container in `docker_sandbox.py` → Build X will create/start a Daytona sandbox, initialize Chromium/CDP, checkpoint its id, and clean it up through an idempotent lease/finalizer, because the mobile client cannot host the Linux runtime; current Build X gap: the Edge Function creates or reuses a sandbox for one request and deletes it in cleanup, with no resumable lease or checkpoint recovery. |
| State persistence | ai-manus uses Mongo repositories and Redis-backed queues/memory in its storage and message-queue infrastructure → Build X will use Supabase Postgres, RLS, Realtime, and durable checkpoints, because identity and ordered replay belong at the service boundary; current Build X gap: `work_runs`/`work_events` provide identity-scoped storage and Realtime, but `work_runs` has no current-step, lease, or resume fields. |
| Runtime boundary | ai-manus separates FastAPI, a worker, and queue-backed execution in `backend/main.py`, `backend/worker.py`, and task infrastructure → Build X will use an Edge Function for bounded orchestration and a worker for resumable long runs, because an uncheckpointed Edge request can lose work; current Build X gap: the current hosted path is one Edge request and the remaining direct/backend fallbacks are not a durable worker architecture. |

## Explicitly not ported

These components are intentionally replaced or deferred. They are not implied
by a similarly named Build X event or widget.

| ai-manus component | Build X decision | Reason |
|---|---|---|
| Docker supervisor, noVNC, and the source desktop stack | Daytona sandbox plus Chromium/CDP; a signed takeover endpoint is a separate target feature | Build X needs a hosted isolated runtime and the requested minimal browser path, not a local Docker desktop. |
| Mongo repositories and GridFS | Supabase Postgres for run/event metadata plus Daytona or an explicit artifact store for files | Supabase already provides auth/RLS and ordered event replay; GridFS semantics are not present in the current schema. |
| Redis queue, cache, and session store | Durable Postgres checkpoints, Realtime, and a worker lease | Realtime is not a durable queue, and the current Edge Function has no safe resume mechanism. |
| FastAPI/uvicorn request path | Supabase Edge Functions plus a worker for long runs | The hosted mobile path invokes `work-run`; the old backend wrapper is not the current orchestration boundary. |
| ai-manus Python browser-use dependency | A small TypeScript CDP helper inside Daytona | Edge Functions cannot import the Python runtime, and the target explicitly excludes porting the full desktop/browser-use stack. |
| ai-manus MCP client manager and runtime server configuration | An authenticated, allowlisted Build X MCP adapter, deferred until the executor and event contract exist | The current Work Function registers no MCP tools; copying client configuration without server-side authorization would not be a safe or faithful port. |
| Vue implementation and Lottie asset lifecycle | Existing Flutter Work widgets, with event semantics ported separately | The interaction contract is portable; the web framework, CSS, and Vue lifecycle are not. |
| ai-manus full browser operation catalog | Target CDP operations, not a claim about current support | The current Build X function implements search/open/click/input/scroll/screenshot through the sandbox-local CDP helper; mouse, key, select, DOM/console, and takeover sessions remain unported gaps. |
| Client-side direct-NIM fallback as an execution authority | Remove it from production Work Mode or make it return an explicit unsupported/error state | Its hard-coded plan, terminal transcript, WebContainer packaging, and placeholder UI can fabricate execution evidence. |
| Legacy Work transcript strings and WebContainer fallback UI | Keep only as explicit unavailable/not-yet-recorded states | They are not an ai-manus runtime port and must never appear as successful shell or browser evidence. |

The OpenHands packages are absent from the current `backend/requirements.txt`
and the old `backend/openhands_server.py` is deleted in the working diff. That
cleanup does not prove that the replacement Work runtime is complete. The
active client path now reports unavailable or not-yet-recorded states instead
of fabricating shell, browser, or deliverable evidence.

## Required implementation invariants

1. A planner result with zero steps emits its message and ends without a
   sandbox. A non-empty plan creates one sandbox and executes one step at a
   time.
2. `complete_step(success=true)` is rejected until a successful real shell,
   file, browser, search, or MCP call is recorded for that step. Failed tool
   calls do not satisfy the guard.
3. Successful steps advance locally. Failed steps trigger `update_plan` while
   preserving completed steps.
4. Every tool call has ordered running/completed events; shell and file updates
   are emitted as bounded live events when available.
5. Browser operations are CDP operations against Chromium in Daytona. `fetch`,
   `curl`, and screenshot-only commands are not substitutes for navigation,
   click, input, scroll, and read-page state.
6. `waiting` is resumable and takeover is explicit, authenticated, and
   short-lived. It is never emitted as `done`.
7. The client renders only persisted or live backend evidence. Synthetic
   fallback plans, terminal transcripts, browser snapshots, and packaging
   messages are not valid completion evidence.
8. The run is recoverable from Postgres after an Edge timeout; no completion
   event is emitted merely because an invocation returned.

## Verification record

No checked-in artifact in the reviewed workspace establishes a trustworthy
two-task Work Mode proof, exact event trace, browser takeover proof, or
resumability proof. This document therefore reports architecture and source
facts only; it does not claim a Work Mode run, run id, event count, browser
interaction, or build/test result.

A future completion report must link the actual browser and terminal artifacts,
the exact ordered event trace, the legacy-reference search result, and the
commands' captured output. If a provider, Daytona image, CDP endpoint, worker,
or signed takeover endpoint is unavailable, the report must say so rather than
turning a simulated event into proof.
