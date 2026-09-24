-- ==============================================================================
-- School Attendance Portal — Supabase Schema & Realtime Setup
-- Safe to re-run: idempotent table creation, indexes, RLS, and realtime config.
-- ==============================================================================

-- 1. Helper function: Add column if missing (safe migrations)
create or replace function public._sas_add_col_if_missing(
  p_table text,
  p_column text,
  p_type text,
  p_default text default null
) returns void
language plpgsql
as $$
begin
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = p_table
      and column_name = p_column
  ) then
    if p_default is null then
      execute format('alter table %I add column %I %s', p_table, p_column, p_type);
    else
      execute format(
        'alter table %I add column %I %s default %s',
        p_table, p_column, p_type, p_default
      );
    end if;
  end if;
end;
$$;

-- 2. Tables

-- Staff & Users
create table if not exists users (
  sync_id text primary key,
  name text not null,
  email text unique not null,
  password_hash text not null,
  role text default 'staff',
  phone text default '',
  staff_category text default 'teacher',
  employee_code text unique,
  fingerprint_id text,
  expected_start_time text default '08:00',
  grace_period_minutes integer default 15,
  attendance_policy text default 'standard',
  status text default 'active',
  session_epoch integer default 0,
  created_at bigint not null,
  updated_at bigint not null
);

-- Students
create table if not exists students (
  sync_id text primary key,
  student_code text unique not null,
  name text not null,
  gender text,
  dob bigint,
  parent_name text default '',
  parent_phone text default '',
  whatsapp_phone text default '',
  notification_opt_in integer default 1,
  enrollment_status text default 'enrolled',
  fingerprint_id text,
  created_by integer,
  created_at bigint not null,
  updated_at bigint not null
);

-- School Classes
create table if not exists school_classes (
  sync_id text primary key,
  name text not null,
  numeric_grade integer,
  description text,
  status text default 'active',
  created_at bigint not null,
  updated_at bigint not null
);

-- Sections
create table if not exists sections (
  sync_id text primary key,
  class_sync_id text references school_classes(sync_id) on delete cascade,
  name text not null,
  room_number text,
  capacity integer default 40,
  status text default 'active',
  created_at bigint not null,
  updated_at bigint not null
);

-- Student Enrollments
create table if not exists student_enrollments (
  sync_id text primary key,
  student_sync_id text references students(sync_id) on delete cascade,
  class_sync_id text references school_classes(sync_id) on delete cascade,
  section_sync_id text references sections(sync_id) on delete cascade,
  academic_year text not null,
  roll_number text,
  start_date bigint not null,
  end_date bigint,
  status text default 'active',
  created_at bigint not null,
  updated_at bigint not null
);

-- Unified School Attendances
create table if not exists school_attendances (
  sync_id text primary key,
  person_type text not null, -- 'student' or 'staff'
  student_sync_id text references students(sync_id) on delete set null,
  staff_sync_id text references users(sync_id) on delete set null,
  date text not null, -- YYYY-MM-DD
  check_in_time bigint,
  check_out_time bigint,
  status text default 'present', -- 'present', 'late', 'half_day', 'absent'
  method text default 'fingerprint',
  notes text,
  recorded_by integer default 0,
  created_at bigint not null,
  updated_at bigint not null
);

-- Parent Notification Queue
create table if not exists parent_notification_jobs (
  sync_id text primary key,
  student_sync_id text references students(sync_id) on delete cascade,
  date text not null,
  channel text not null, -- 'sms', 'whatsapp'
  recipient_phone text not null,
  message text not null,
  status text default 'pending', -- 'pending', 'sent', 'failed', 'skipped'
  scheduled_at bigint not null,
  sent_at bigint,
  last_error text,
  created_at bigint not null,
  updated_at bigint not null
);

-- Notification Delivery Attempts
create table if not exists notification_delivery_attempts (
  sync_id text primary key,
  job_sync_id text references parent_notification_jobs(sync_id) on delete cascade,
  attempt_number integer default 1,
  attempted_at bigint not null,
  provider text default 'twilio',
  provider_message_id text,
  status text not null,
  response_body text,
  created_at bigint not null,
  updated_at bigint not null
);

-- School Settings
create table if not exists school_settings (
  sync_id text primary key,
  key text unique not null,
  value text not null,
  created_at bigint not null,
  updated_at bigint not null
);

-- System Activity Logs
create table if not exists activity_logs (
  sync_id text primary key,
  entity_type text not null,
  entity_id text,
  action text not null,
  details text,
  performed_by integer default 0,
  timestamp bigint not null,
  created_at bigint not null,
  updated_at bigint not null
);

-- 3. Indexes for fast lookups and efficient synchronization
create index if not exists idx_users_updated_at on users(updated_at);
create index if not exists idx_users_employee_code on users(employee_code);

create index if not exists idx_students_updated_at on students(updated_at);
create index if not exists idx_students_student_code on students(student_code);
create index if not exists idx_students_fingerprint_id on students(fingerprint_id);

create index if not exists idx_classes_updated_at on school_classes(updated_at);
create index if not exists idx_sections_updated_at on sections(updated_at);
create index if not exists idx_enrollments_updated_at on student_enrollments(updated_at);
create index if not exists idx_enrollments_student on student_enrollments(student_sync_id, status);

create index if not exists idx_attendances_updated_at on school_attendances(updated_at);
create index if not exists idx_attendances_date_person on school_attendances(date, person_type);
create index if not exists idx_attendances_student on school_attendances(student_sync_id, date);
create index if not exists idx_attendances_staff on school_attendances(staff_sync_id, date);

create index if not exists idx_notification_jobs_updated_at on parent_notification_jobs(updated_at);
create index if not exists idx_notification_jobs_date_status on parent_notification_jobs(date, status);

create index if not exists idx_settings_key on school_settings(key);
create index if not exists idx_activity_logs_timestamp on activity_logs(timestamp);

-- 4. Enable Row Level Security (RLS) on all tables
alter table users enable row level security;
alter table students enable row level security;
alter table school_classes enable row level security;
alter table sections enable row level security;
alter table student_enrollments enable row level security;
alter table school_attendances enable row level security;
alter table parent_notification_jobs enable row level security;
alter table notification_delivery_attempts enable row level security;
alter table school_settings enable row level security;
alter table activity_logs enable row level security;

-- Permissive policies for authenticated and anon app syncing
do $$
declare
  t text;
begin
  for t in select unnest(array[
    'users',
    'students',
    'school_classes',
    'sections',
    'student_enrollments',
    'school_attendances',
    'parent_notification_jobs',
    'notification_delivery_attempts',
    'school_settings',
    'activity_logs'
  ]) loop
    execute format('drop policy if exists %I on %I', 'allow_all_' || t, t);
    execute format('create policy %I on %I for all using (true) with check (true)', 'allow_all_' || t, t);
  end loop;
end;
$$;

-- 5. Realtime publication setup
do $$
declare
  t text;
begin
  for t in select unnest(array[
    'users',
    'students',
    'school_classes',
    'sections',
    'student_enrollments',
    'school_attendances',
    'parent_notification_jobs',
    'notification_delivery_attempts',
    'school_settings',
    'activity_logs'
  ]) loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      begin
        execute format('alter publication supabase_realtime add table %I', t);
      exception when others then
        -- Ignore if already present or permission issue
      end;
    end if;
  end loop;
end;
$$;
