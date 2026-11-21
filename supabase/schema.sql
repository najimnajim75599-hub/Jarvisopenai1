-- JARVIS schema. Run once in Supabase SQL Editor.
create extension if not exists pgcrypto;
create table profiles(id uuid primary key references auth.users on delete cascade,email text,role text not null default 'user' check(role in('user','admin')),created_at timestamptz default now());
create table software_releases(id uuid primary key default gen_random_uuid(),version text not null unique,title text not null,description text default '',file_path text not null,file_name text not null,file_size bigint not null check(file_size>0),file_type text not null check(file_type in('zip','exe','bat')),release_date date default current_date,status text not null default 'draft' check(status in('draft','published','archived')),download_count int not null default 0,created_at timestamptz default now());
create table features(id uuid primary key default gen_random_uuid(),title text not null,description text default '',icon text default '⚡',is_active boolean default true,display_order int default 0);
create table website_content(id uuid primary key default gen_random_uuid(),section text not null unique,title text,description text,content text,updated_at timestamptz default now());
create table videos(id uuid primary key default gen_random_uuid(),title text not null,description text default '',video_path text not null,thumbnail_path text,is_active boolean default true,created_at timestamptz default now());
create table changelog(id uuid primary key default gen_random_uuid(),version text not null,title text not null,description text default '',release_date date default current_date,created_at timestamptz default now());
create table download_logs(id uuid primary key default gen_random_uuid(),release_id uuid not null references software_releases on delete cascade,downloaded_at timestamptz default now());
create index on software_releases(status,release_date desc);create index on download_logs(release_id,downloaded_at desc);create index on features(display_order);

create function is_admin() returns boolean language sql security definer stable set search_path=public as $$select exists(select 1 from profiles where id=auth.uid() and role='admin')$$;
create function handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$begin insert into profiles(id,email) values(new.id,new.email);return new;end$$;
create trigger on_auth_user_created after insert on auth.users for each row execute function handle_new_user();
create function register_download(rid uuid) returns void language plpgsql security definer set search_path=public as $$begin
 if exists(select 1 from software_releases where id=rid and status='published') then
  update software_releases set download_count=download_count+1 where id=rid; insert into download_logs(release_id) values(rid);end if;end$$;
grant execute on function register_download(uuid) to anon,authenticated;

-- Prevent users from promoting themselves
create function block_role_change() returns trigger language plpgsql as $$begin if new.role<>old.role and not (select is_admin()) and auth.uid() is not null then raise exception 'forbidden';end if;return new;end$$;
create trigger no_self_promote before update on profiles for each row execute function block_role_change();

alter table profiles enable row level security;alter table software_releases enable row level security;alter table features enable row level security;alter table website_content enable row level security;alter table videos enable row level security;alter table changelog enable row level security;alter table download_logs enable row level security;
create policy p_read_self on profiles for select using(id=auth.uid() or is_admin());
create policy rel_pub on software_releases for select using(status='published' or is_admin());
create policy rel_adm on software_releases for all using(is_admin()) with check(is_admin());
create policy feat_pub on features for select using(is_active or is_admin());
create policy feat_adm on features for all using(is_admin()) with check(is_admin());
create policy cont_pub on website_content for select using(true);
create policy cont_adm on website_content for all using(is_admin()) with check(is_admin());
create policy vid_pub on videos for select using(is_active or is_admin());
create policy vid_adm on videos for all using(is_admin()) with check(is_admin());
create policy chg_pub on changelog for select using(true);
create policy chg_adm on changelog for all using(is_admin()) with check(is_admin());
create policy log_adm on download_logs for select using(is_admin());

-- Storage: private 'releases', public 'media'
insert into storage.buckets(id,name,public,file_size_limit) values('releases','releases',false,52428800),('media','media',true,52428800) on conflict do nothing;
create policy rel_dl on storage.objects for select using(bucket_id='releases' and (is_admin() or exists(select 1 from software_releases r where r.file_path=name and r.status='published')));
create policy rel_up on storage.objects for insert with check(bucket_id='releases' and is_admin());
create policy rel_del on storage.objects for delete using(bucket_id='releases' and is_admin());
create policy med_up on storage.objects for insert with check(bucket_id='media' and is_admin());
create policy med_upd on storage.objects for update using(bucket_id='media' and is_admin());
create policy med_del on storage.objects for delete using(bucket_id='media' and is_admin());
create policy med_read on storage.objects for select using(bucket_id='media');

-- ADMIN SETUP: 1) Authentication > Users > Add user (your email + password, auto-confirm). 2) Run, with your email:
-- update profiles set role='admin' where email='YOUR_EMAIL';
