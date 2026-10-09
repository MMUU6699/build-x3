begin;

alter table public.work_runs
  drop constraint if exists work_runs_status_value;

alter table public.work_runs
  add constraint work_runs_status_value check (
    status in ('queued', 'running', 'waiting', 'completed', 'failed', 'cancelled')
  );

comment on column public.work_runs.sandbox_id is
  'The live Daytona sandbox used by the run while it is running or waiting for user control.';

commit;
