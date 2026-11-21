-- JARVIS command-center upgrade. Run AFTER schema.sql and upgrade_v2.sql.
alter table profiles add column if not exists last_login_at timestamptz;
create table if not exists admin_activity_logs(id uuid primary key default gen_random_uuid(),admin_id uuid references auth.users on delete set null,action text not null,detail text,created_at timestamptz default now());
create table if not exists system_events(id uuid primary key default gen_random_uuid(),level text default 'info',message text not null,created_at timestamptz default now());
create table if not exists login_events(id uuid primary key default gen_random_uuid(),user_id uuid references auth.users on delete set null,email text,success boolean not null,created_at timestamptz default now());
create table if not exists site_visits(sid text not null,day date not null default current_date,visited_at timestamptz default now(),primary key(sid,day));
create table if not exists notifications(id uuid primary key default gen_random_uuid(),kind text not null default 'announcement' check(kind in('announcement','maintenance','new_version','direct')),title text not null,body text default '',target_user uuid references auth.users on delete cascade,scheduled_for timestamptz default now(),created_by uuid default auth.uid(),created_at timestamptz default now());
create index if not exists ix_login_events on login_events(created_at desc);create index if not exists ix_logs on admin_activity_logs(created_at desc);create index if not exists ix_notif on notifications(scheduled_for desc);
alter table admin_activity_logs enable row level security;alter table system_events enable row level security;alter table login_events enable row level security;alter table site_visits enable row level security;alter table notifications enable row level security;
create policy al_adm on admin_activity_logs for select using(is_admin());
create policy se_adm on system_events for all using(is_admin()) with check(is_admin());
create policy le_adm on login_events for select using(is_admin() or user_id=auth.uid());
create policy nt_read on notifications for select using(is_admin() or (scheduled_for<=now() and (target_user is null or target_user=auth.uid())));
create policy nt_adm on notifications for all using(is_admin()) with check(is_admin());
-- Public downloads do not require an account or email confirmation.
drop policy if exists rel_dl on storage.objects;
create policy rel_dl on storage.objects for select using(bucket_id='releases');
create or replace function track_visit(sid text) returns void language sql security definer set search_path=public as $$insert into site_visits(sid) values(left(sid,40)) on conflict do nothing$$;
create or replace function log_login(em text,ok boolean) returns void language plpgsql security definer set search_path=public as $$begin
 insert into login_events(user_id,email,success) values(auth.uid(),left(em,200),ok); if ok and auth.uid() is not null then update profiles set last_login_at=now() where id=auth.uid(); end if; end$$;
grant execute on function track_visit(text),log_login(text,boolean) to anon,authenticated;
create or replace function admin_stats() returns json language plpgsql security definer set search_path=public as $$begin
 if not is_admin() then raise exception 'forbidden'; end if;
 return json_build_object('users',(select count(*) from profiles),'active',(select count(*) from profiles where last_login_at>now()-interval '30 days'),
 'downloads',(select coalesce(sum(download_count),0) from software_releases),'visitors',(select count(distinct sid) from site_visits),
 'logins',(select count(*) from login_events),'failed',(select count(*) from login_events where not success),
 'dl_series',(select json_agg(json_build_object('d',d::date,'n',(select count(*) from download_logs where downloaded_at::date=d::date)) order by d) from generate_series(current_date-13,current_date,'1 day') d),
 'user_series',(select json_agg(json_build_object('d',d::date,'n',(select count(*) from profiles where created_at::date=d::date)) order by d) from generate_series(current_date-13,current_date,'1 day') d),
 'visit_series',(select json_agg(json_build_object('d',d::date,'n',(select count(*) from site_visits where day=d::date)) order by d) from generate_series(current_date-13,current_date,'1 day') d));end$$;
create or replace function admin_delete_user(uid uuid) returns void language plpgsql security definer set search_path=public,auth as $$begin
 if not is_admin() then raise exception 'forbidden'; end if; if uid=auth.uid() then raise exception 'You cannot delete yourself'; end if;
 insert into admin_activity_logs(admin_id,action,detail) values(auth.uid(),'DELETE user',(select email from profiles where id=uid)); delete from auth.users where id=uid; end$$;
create or replace function log_change() returns trigger language plpgsql security definer set search_path=public as $$
declare j jsonb:=case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end; begin
 if auth.uid() is not null and is_admin() then insert into admin_activity_logs(admin_id,action,detail) values(auth.uid(),tg_op||' '||tg_table_name,coalesce(j->>'title',j->>'version',j->>'section',j->>'email')); end if; return null; end$$;
do $$ declare t text; begin foreach t in array array['software_releases','features','videos','changelog','website_content','notifications'] loop
 execute format('drop trigger if exists trg_log on %I; create trigger trg_log after insert or update or delete on %I for each row execute function log_change()',t,t); end loop; end$$;
drop trigger if exists trg_log on profiles;
create trigger trg_log after update on profiles for each row when (old.role is distinct from new.role or old.is_blocked is distinct from new.is_blocked) execute function log_change();
