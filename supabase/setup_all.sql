-- ===== schema.sql =====
-- JARVIS schema. Run once in Supabase SQL Editor.
create extension if not exists pgcrypto;
create table if not exists profiles(id uuid primary key references auth.users on delete cascade,email text,role text not null default 'user' check(role in('user','admin')),created_at timestamptz default now());
create table if not exists software_releases(id uuid primary key default gen_random_uuid(),version text not null unique,title text not null,description text default '',file_path text not null,file_name text not null,file_size bigint not null check(file_size>0),file_type text not null check(file_type in('zip','exe','bat')),release_date date default current_date,status text not null default 'draft' check(status in('draft','published','archived')),download_count int not null default 0,created_at timestamptz default now());
create table if not exists features(id uuid primary key default gen_random_uuid(),title text not null,description text default '',icon text default '⚡',is_active boolean default true,display_order int default 0);
create table if not exists website_content(id uuid primary key default gen_random_uuid(),section text not null unique,title text,description text,content text,updated_at timestamptz default now());
create table if not exists videos(id uuid primary key default gen_random_uuid(),title text not null,description text default '',video_path text not null,thumbnail_path text,is_active boolean default true,created_at timestamptz default now());
create table if not exists changelog(id uuid primary key default gen_random_uuid(),version text not null,title text not null,description text default '',release_date date default current_date,created_at timestamptz default now());
create table if not exists download_logs(id uuid primary key default gen_random_uuid(),release_id uuid not null references software_releases on delete cascade,downloaded_at timestamptz default now());
create index if not exists software_releases_status_release_date_idx on software_releases(status,release_date desc);create index if not exists download_logs_release_id_downloaded_at_idx on download_logs(release_id,downloaded_at desc);create index if not exists features_display_order_idx on features(display_order);
grant usage on schema public to anon, authenticated;
grant select on public.profiles, public.software_releases, public.features, public.website_content, public.videos, public.changelog, public.download_logs to anon, authenticated;
grant insert, update, delete on public.profiles, public.software_releases, public.features, public.website_content, public.videos, public.changelog, public.download_logs to authenticated;

create or replace function is_admin() returns boolean language sql security definer stable set search_path=public as $$select exists(select 1 from profiles where id=auth.uid() and role in('admin','editor'))$$;
create or replace function get_my_profile() returns json language plpgsql security definer set search_path=public as $$declare r profiles%rowtype; begin
 if auth.uid() is null then return null; end if;
 select * into r from profiles where id=auth.uid();
 if not found then return null; end if;
 return json_build_object('id',r.id,'email',r.email,'role',r.role,'created_at',r.created_at);
end$$;
grant execute on function get_my_profile() to authenticated;
create or replace function handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$begin insert into profiles(id,email) values(new.id,new.email) on conflict(id) do update set email=excluded.email;return new;end$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function handle_new_user();
create or replace function register_download(rid uuid) returns void language plpgsql security definer set search_path=public as $$begin
 if exists(select 1 from software_releases where id=rid and status='published') then
  update software_releases set download_count=download_count+1 where id=rid; insert into download_logs(release_id) values(rid);end if;end$$;
grant execute on function register_download(uuid) to anon,authenticated;

-- Prevent users from promoting themselves
create or replace function block_role_change() returns trigger language plpgsql as $$begin if new.role<>old.role and not (select is_admin()) and auth.uid() is not null then raise exception 'forbidden';end if;return new;end$$;
drop trigger if exists no_self_promote on profiles;
create trigger no_self_promote before update on profiles for each row execute function block_role_change();

alter table profiles enable row level security;alter table software_releases enable row level security;alter table features enable row level security;alter table website_content enable row level security;alter table videos enable row level security;alter table changelog enable row level security;alter table download_logs enable row level security;
drop policy if exists p_read_self on profiles; create policy p_read_self on profiles for select using(id=auth.uid() or is_admin());
drop policy if exists rel_pub on software_releases; create policy rel_pub on software_releases for select using(status='published' or is_admin());
drop policy if exists rel_adm on software_releases; create policy rel_adm on software_releases for all using(is_admin()) with check(is_admin());
drop policy if exists feat_pub on features; create policy feat_pub on features for select using(is_active or is_admin());
drop policy if exists feat_adm on features; create policy feat_adm on features for all using(is_admin()) with check(is_admin());
drop policy if exists cont_pub on website_content; create policy cont_pub on website_content for select using(true);
drop policy if exists cont_adm on website_content; create policy cont_adm on website_content for all using(is_admin()) with check(is_admin());
drop policy if exists vid_pub on videos; create policy vid_pub on videos for select using(is_active or is_admin());
drop policy if exists vid_adm on videos; create policy vid_adm on videos for all using(is_admin()) with check(is_admin());
drop policy if exists chg_pub on changelog; create policy chg_pub on changelog for select using(true);
drop policy if exists chg_adm on changelog; create policy chg_adm on changelog for all using(is_admin()) with check(is_admin());
drop policy if exists log_adm on download_logs; create policy log_adm on download_logs for select using(is_admin());

-- Storage: private 'releases', public 'media'
insert into storage.buckets(id,name,public,file_size_limit) values('releases','releases',false,52428800),('media','media',true,52428800) on conflict do nothing;
drop policy if exists rel_dl on storage.objects; create policy rel_dl on storage.objects for select using(bucket_id='releases' and (is_admin() or exists(select 1 from software_releases r where r.file_path=name and r.status='published')));
drop policy if exists rel_up on storage.objects; create policy rel_up on storage.objects for insert with check(bucket_id='releases' and is_admin());
drop policy if exists rel_del on storage.objects; create policy rel_del on storage.objects for delete using(bucket_id='releases' and is_admin());
drop policy if exists med_up on storage.objects; create policy med_up on storage.objects for insert with check(bucket_id='media' and is_admin());
drop policy if exists med_upd on storage.objects; create policy med_upd on storage.objects for update using(bucket_id='media' and is_admin());
drop policy if exists med_del on storage.objects; create policy med_del on storage.objects for delete using(bucket_id='media' and is_admin());
drop policy if exists med_read on storage.objects; create policy med_read on storage.objects for select using(bucket_id='media');

-- ADMIN SETUP: 1) Authentication > Users > Add user (your email + password, auto-confirm). 2) Run, with your email:
-- update profiles set role='admin' where email='YOUR_EMAIL';

-- ===== upgrade_v2.sql =====
-- Run AFTER schema.sql (adds users, onboarding, announcements, planned-feature status).
alter table profiles add column if not exists full_name text,add column if not exists preferred_name text,add column if not exists phone text,
 add column if not exists interaction text default 'voice' check(interaction in('voice','text','both')),add column if not exists onboarded boolean not null default false,
 add column if not exists consent_at timestamptz,add column if not exists is_blocked boolean not null default false;
alter table features add column if not exists status text not null default 'soon' check(status in('available','soon'));
alter table download_logs add column if not exists user_id uuid references auth.users on delete set null;
create table if not exists announcements(id uuid primary key default gen_random_uuid(),title text not null,description text default '',is_active boolean default true,created_at timestamptz default now());
alter table announcements enable row level security;
drop policy if exists ann_pub on announcements; create policy ann_pub on announcements for select using(is_active or is_admin());
drop policy if exists ann_adm on announcements; create policy ann_adm on announcements for all using(is_admin()) with check(is_admin());
drop policy if exists prof_upd on profiles; create policy prof_upd on profiles for update using(id=auth.uid()) with check(id=auth.uid());
drop policy if exists prof_adm on profiles; create policy prof_adm on profiles for update using(is_admin()) with check(is_admin());
drop policy if exists log_own on download_logs; create policy log_own on download_logs for select using(user_id=auth.uid());
create or replace function block_role_change() returns trigger language plpgsql as $$begin if (new.role<>old.role or new.is_blocked<>old.is_blocked) and auth.uid() is not null and not is_admin() then raise exception 'forbidden';end if;return new;end$$;
create or replace function handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$begin insert into profiles(id,email,full_name) values(new.id,new.email,new.raw_user_meta_data->>'full_name') on conflict(id) do update set email=excluded.email,full_name=coalesce(excluded.full_name,profiles.full_name);return new;end$$;
insert into profiles(id,email,full_name)
select u.id,u.email,u.raw_user_meta_data->>'full_name'
from auth.users u
on conflict(id) do update set email=excluded.email,full_name=coalesce(excluded.full_name,profiles.full_name);
create or replace function register_download(rid uuid) returns void language plpgsql security definer set search_path=public as $$begin
 if exists(select 1 from software_releases where id=rid and status='published') and not exists(select 1 from profiles where id=auth.uid() and is_blocked) then
  update software_releases set download_count=download_count+1 where id=rid; insert into download_logs(release_id,user_id) values(rid,auth.uid());end if;end$$;
insert into features(title,description,icon,display_order,status)
select v.title,v.description,v.icon,v.display_order,v.status
from (values
('Voice Intelligence','Talk to JARVIS naturally.','🎙️',1,'soon'),('AI Conversations','Context-aware dialogue.','💬',2,'soon'),('PC Automation','Run tasks on your PC by command.','⚙️',3,'soon'),
('Smart File Management','Find and organize files.','📁',4,'soon'),('Keyboard & Mouse Control','Hands-free input control.','🖱️',5,'soon'),('Weather Intelligence','Live forecasts on request.','🌦️',6,'soon'),
('Screen Understanding','Understand what is on screen.','🖥️',7,'soon'),('Smart Message Assistance','Draft and reply to messages.','✉️',8,'soon'),('Face Recognition','Recognize authorized users.','🧑',9,'soon'),
('Gesture Control','Control JARVIS with gestures.','✋',10,'soon'),('Online AI Intelligence','Connect to online AI models.','🌐',11,'soon'),('Future AI Capabilities','More coming over time.','🚀',12,'soon'))
AS v(title,description,icon,display_order,status)
where not exists(select 1 from features f where f.title=v.title);
-- Mark a feature live in Admin > Features by editing its Status to: available

-- ===== upgrade_v3.sql =====
-- JARVIS command-center upgrade. Run AFTER schema.sql and upgrade_v2.sql.
alter table profiles add column if not exists last_login_at timestamptz;
create table if not exists admin_activity_logs(id uuid primary key default gen_random_uuid(),admin_id uuid references auth.users on delete set null,action text not null,detail text,created_at timestamptz default now());
create table if not exists system_events(id uuid primary key default gen_random_uuid(),level text default 'info',message text not null,created_at timestamptz default now());
create table if not exists login_events(id uuid primary key default gen_random_uuid(),user_id uuid references auth.users on delete set null,email text,success boolean not null,created_at timestamptz default now());
create table if not exists site_visits(sid text not null,day date not null default current_date,visited_at timestamptz default now(),primary key(sid,day));
create table if not exists notifications(id uuid primary key default gen_random_uuid(),kind text not null default 'announcement' check(kind in('announcement','maintenance','new_version','direct')),title text not null,body text default '',target_user uuid references auth.users on delete cascade,scheduled_for timestamptz default now(),created_by uuid default auth.uid(),created_at timestamptz default now());
create index if not exists ix_login_events on login_events(created_at desc);create index if not exists ix_logs on admin_activity_logs(created_at desc);create index if not exists ix_notif on notifications(scheduled_for desc);
alter table admin_activity_logs enable row level security;alter table system_events enable row level security;alter table login_events enable row level security;alter table site_visits enable row level security;alter table notifications enable row level security;
drop policy if exists al_adm on admin_activity_logs; create policy al_adm on admin_activity_logs for select using(is_admin());
drop policy if exists se_adm on system_events; create policy se_adm on system_events for all using(is_admin()) with check(is_admin());
drop policy if exists le_adm on login_events; create policy le_adm on login_events for select using(is_admin() or user_id=auth.uid());
drop policy if exists nt_read on notifications; create policy nt_read on notifications for select using(is_admin() or (scheduled_for<=now() and (target_user is null or target_user=auth.uid())));
drop policy if exists nt_adm on notifications; create policy nt_adm on notifications for all using(is_admin()) with check(is_admin());
-- blocked accounts cannot fetch release files
drop policy if exists rel_dl on storage.objects;
create policy rel_dl on storage.objects for select using(bucket_id='releases' and (is_admin() or (exists(select 1 from software_releases r where r.file_path=name and r.status='published') and not exists(select 1 from profiles where id=auth.uid() and is_blocked))));
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

-- ===== upgrade_v4.sql =====
-- v4: editor role (limited staff), "set latest release", character image support. Run after v3 (included in setup_all.sql).
alter table profiles drop constraint if exists profiles_role_check;
alter table profiles add constraint profiles_role_check check(role in('user','editor','admin'));
alter table software_releases add column if not exists is_latest boolean not null default false;
create or replace function is_staff() returns boolean language sql security definer stable set search_path=public as $$select exists(select 1 from profiles where id=auth.uid() and role in('admin','editor'))$$;
create or replace function set_latest_release(rid uuid) returns void language plpgsql security definer set search_path=public as $$begin
 if not is_admin() then raise exception 'forbidden'; end if; update software_releases set is_latest=(id=rid) where status<>'archived' or id=rid; end$$;
-- editors may manage website content only (features, content, videos, changelog, media files)
drop policy if exists feat_pub on features; drop policy if exists feat_adm on features;
create policy feat_pub on features for select using(is_active or is_staff());
create policy feat_adm on features for all using(is_staff()) with check(is_staff());
drop policy if exists cont_adm on website_content; create policy cont_adm on website_content for all using(is_staff()) with check(is_staff());
drop policy if exists vid_pub on videos; drop policy if exists vid_adm on videos;
create policy vid_pub on videos for select using(is_active or is_staff());
create policy vid_adm on videos for all using(is_staff()) with check(is_staff());
drop policy if exists chg_adm on changelog; create policy chg_adm on changelog for all using(is_staff()) with check(is_staff());
drop policy if exists med_up on storage.objects; drop policy if exists med_upd on storage.objects; drop policy if exists med_del on storage.objects;
create policy med_up on storage.objects for insert with check(bucket_id='media' and is_staff());
create policy med_upd on storage.objects for update using(bucket_id='media' and is_staff());
create policy med_del on storage.objects for delete using(bucket_id='media' and is_staff());
create or replace function log_change() returns trigger language plpgsql security definer set search_path=public as $$
declare j jsonb:=case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end; begin
 if auth.uid() is not null and is_staff() then insert into admin_activity_logs(admin_id,action,detail) values(auth.uid(),tg_op||' '||tg_table_name,coalesce(j->>'title',j->>'version',j->>'section',j->>'email')); end if; return null; end$$;

-- ===== upgrade_v5.sql =====
-- v5: downloads require an account. Guests can no longer obtain release files, even by calling the API directly.
drop policy if exists rel_dl on storage.objects;
create policy rel_dl on storage.objects for select to authenticated using(bucket_id='releases' and (is_admin() or (exists(select 1 from software_releases r where r.file_path=name and r.status='published') and not exists(select 1 from profiles where id=auth.uid() and is_blocked))));


-- FINAL STEP: register on the website, then run with YOUR email:
-- update profiles set role='admin' where email='YOUR_EMAIL';
