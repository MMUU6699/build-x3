begin;

alter table public.work_runs
  drop constraint if exists work_runs_reasoning_effort_value;

alter table public.work_runs
  add constraint work_runs_reasoning_effort_value
  check (reasoning_effort in ('none', 'low', 'medium', 'high', 'standard'));

commit;
