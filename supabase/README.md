# Build X Supabase runtime

This directory contains the authenticated NVIDIA proxy and the server-side
Daytona work runner. Provider credentials stay in Supabase Edge Function
secrets and are never accepted from app request bodies.

## Prerequisites

- A Supabase project with email/password and any required OAuth providers enabled.
- A Daytona API key.
- An NVIDIA API key with access to `nvidia/nemotron-3-ultra-550b-a55b`.
- Supabase CLI installed and authenticated.

## Configure and deploy

```sh
supabase link --project-ref YOUR_PROJECT_REF
supabase secrets set NVIDIA_API_KEY=YOUR_NVIDIA_KEY DAYTONA_API_KEY=YOUR_DAYTONA_KEY
supabase secrets set CORS_ALLOWED_ORIGINS=https://app.example.com
supabase db push
supabase functions deploy nvidia-chat
supabase functions deploy work-run
```

`SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` are supplied
by the Edge Function runtime. Do not put the service-role key in the Flutter app.
For self-hosted Daytona, also set `DAYTONA_API_URL`; `DAYTONA_TARGET` is optional.
For local browser development only, `CORS_ALLOWED_ORIGINS=*` may be used. Use an
explicit comma-separated allowlist in production.

Build the Flutter app with its public project values:

```sh
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLIC_PUBLISHABLE_KEY
```

The publishable key is intended for clients. NVIDIA, Daytona, and service-role
keys are server-only secrets.

## Calling the functions

Invoke functions through the authenticated Supabase client so the current user
JWT is sent automatically:

```ts
await supabase.functions.invoke('nvidia-chat', {
  body: { messages: [{ role: 'user', content: 'Hello' }] },
})

await supabase.functions.invoke('work-run', {
  body: {
    prompt: 'Build a standalone pomodoro timer',
    model: 'nvidia/nemotron-3-ultra-550b-a55b',
    reasoning_effort: 'high',
  },
})
```

`work-run` returns `200` with `{ run_id, status: "completed", result }`. The
`result` contains `title`, `type`, `entrypoint`, `files`, and `previewHtml`.
Validation errors return `400`, invalid sessions return `401`, and execution
failures return `502` with a safe error and the run ID when one was created.

Subscribe to `work_runs` and `work_events` through Supabase Realtime. RLS only
allows an authenticated user to read their own rows. Writes to work records are
performed by the server-side function.

## Auth configuration

Register `buildx://login-callback` in Supabase Auth redirect URLs for the mobile
app and configure the Google provider credentials if Google sign-in is enabled.
Configure a separate HTTPS redirect and password-recovery page for web builds.
