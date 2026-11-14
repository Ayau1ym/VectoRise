-- VectoRise MVP schema for Supabase/PostgreSQL
create extension if not exists pgcrypto;

create type public.vr_role as enum ('student','parent','mentor','school_admin');
create type public.task_status as enum ('planned','in_progress','done','skipped');
create type public.opportunity_status as enum ('draft','published','archived');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role public.vr_role not null default 'student',
  display_name text not null,
  email text,
  locale text not null default 'ru' check (locale in ('ru','kk','en')),
  region text,
  school_name text,
  grade smallint check (grade between 7 and 12),
  birth_year smallint,
  parent_consent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.student_goals (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  target_country text,
  target_institutions text[] not null default '{}',
  target_field text,
  intake_year smallint,
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.achievements (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  category text not null check (category in ('academic','test','language','olympiad','project','leadership','volunteer','other')),
  title text not null,
  organization text,
  description text,
  achieved_on date,
  evidence_url text,
  visibility text not null default 'private' check (visibility in ('private','parent','mentor')),
  created_at timestamptz not null default now()
);

create table public.requirements (
  id uuid primary key default gen_random_uuid(),
  institution text not null,
  program text not null,
  country text not null,
  category text not null,
  description text not null,
  source_url text not null,
  checked_at date not null,
  valid_until date,
  is_active boolean not null default true
);

create table public.opportunities (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  kind text not null check (kind in ('olympiad','scholarship','summer_program','course','competition','research','other')),
  country text,
  eligible_regions text[] not null default '{}',
  grade_min smallint,
  grade_max smallint,
  field text,
  cost_kzt numeric(12,2),
  funding text,
  deadline date,
  url text not null,
  source_name text,
  checked_at date not null,
  status public.opportunity_status not null default 'draft',
  created_at timestamptz not null default now()
);

create table public.roadmap_tasks (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  goal_id uuid references public.student_goals(id) on delete set null,
  requirement_id uuid references public.requirements(id) on delete set null,
  opportunity_id uuid references public.opportunities(id) on delete set null,
  title text not null,
  description text,
  category text,
  due_date date,
  status public.task_status not null default 'planned',
  priority smallint not null default 2 check (priority between 1 and 3),
  completed_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.progress_updates (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  task_id uuid references public.roadmap_tasks(id) on delete set null,
  note text,
  mood smallint check (mood between 1 and 5),
  created_at timestamptz not null default now()
);

create table public.family_links (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  adult_id uuid not null references public.profiles(id) on delete cascade,
  relationship text,
  status text not null default 'pending' check (status in ('pending','active','revoked')),
  permissions jsonb not null default '{"summary":true,"achievements":false,"notes":false}'::jsonb,
  created_at timestamptz not null default now(),
  unique(student_id, adult_id)
);

create table public.mentor_assignments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  mentor_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'active' check (status in ('active','ended')),
  created_at timestamptz not null default now(),
  unique(student_id, mentor_id)
);

create table public.consents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  consent_type text not null,
  document_version text not null,
  granted boolean not null,
  recorded_at timestamptz not null default now()
);

-- Adult-led pilot interest only. Never collect a child's contact details here.
-- No authenticated browser policy is provided: inserts/exports belong on a trusted server.
create table public.pilot_leads (
  id uuid primary key default gen_random_uuid(),
  guardian_name text not null check (char_length(guardian_name) between 2 and 80),
  guardian_email text not null check (guardian_email = lower(guardian_email)),
  student_grade smallint check (student_grade between 9 and 12),
  product_code text not null default 'pilot_4w_9900',
  consented_at timestamptz not null,
  consent_version text not null default 'pilot-contact-v1',
  status text not null default 'new' check (status in ('new','contacted','accepted','declined','deleted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index roadmap_student_due_idx on public.roadmap_tasks(student_id, due_date);
create index opportunities_deadline_idx on public.opportunities(status, deadline);
create index achievements_student_idx on public.achievements(student_id, achieved_on desc);
create index goals_student_active_idx on public.student_goals(student_id, is_active);

alter table public.profiles enable row level security;
alter table public.student_goals enable row level security;
alter table public.achievements enable row level security;
alter table public.requirements enable row level security;
alter table public.opportunities enable row level security;
alter table public.roadmap_tasks enable row level security;
alter table public.progress_updates enable row level security;
alter table public.family_links enable row level security;
alter table public.mentor_assignments enable row level security;
alter table public.consents enable row level security;
alter table public.pilot_leads enable row level security;

-- Public catalog is read-only for signed-in users. Writes should be handled by trusted admin tooling.
create policy "signed-in users read published opportunities" on public.opportunities
for select to authenticated using (status = 'published');
create policy "signed-in users read active requirements" on public.requirements
for select to authenticated using (is_active = true);

-- Owners can manage their own core records. Parent/mentor sharing should use narrowly scoped server views
-- or RPC functions after the consent and relationship flows are implemented and reviewed.
create policy "owner manages own profile" on public.profiles
for all to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy "student manages own goals" on public.student_goals
for all to authenticated using (student_id = auth.uid()) with check (student_id = auth.uid());
create policy "student manages own achievements" on public.achievements
for all to authenticated using (student_id = auth.uid()) with check (student_id = auth.uid());
create policy "student manages own tasks" on public.roadmap_tasks
for all to authenticated using (student_id = auth.uid()) with check (student_id = auth.uid());
create policy "student manages own progress" on public.progress_updates
for all to authenticated using (student_id = auth.uid()) with check (student_id = auth.uid());
create policy "user manages own family links" on public.family_links
for all to authenticated using (student_id = auth.uid() or adult_id = auth.uid())
with check (student_id = auth.uid() or adult_id = auth.uid());
create policy "user reads own mentor assignments" on public.mentor_assignments
for select to authenticated using (student_id = auth.uid() or mentor_id = auth.uid());
create policy "user reads own consents" on public.consents
for select to authenticated using (user_id = auth.uid());
create policy "user records own consents" on public.consents
for insert to authenticated with check (user_id = auth.uid());
