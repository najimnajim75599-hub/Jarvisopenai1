-- Run AFTER schema.sql (adds users, onboarding, announcements, planned-feature status).
alter table profiles add column if not exists full_name text,add column if not exists preferred_name text,add column if not exists phone text,
 add column if not exists interaction text default 'voice' check(interaction in('voice','text','both')),add column if not exists onboarded boolean not null default false,
 add column if not exists consent_at timestamptz,add column if not exists is_blocked boolean not null default false;
alter table features add column if not exists status text not null default 'soon' check(status in('available','soon'));
alter table download_logs add column if not exists user_id uuid references auth.users on delete set null;
create table if not exists announcements(id uuid primary key default gen_random_uuid(),title text not null,description text default '',is_active boolean default true,created_at timestamptz default now());
alter table announcements enable row level security;
create policy ann_pub on announcements for select using(is_active or is_admin());
create policy ann_adm on announcements for all using(is_admin()) with check(is_admin());
create policy prof_upd on profiles for update using(id=auth.uid()) with check(id=auth.uid());
create policy prof_adm on profiles for update using(is_admin()) with check(is_admin());
create policy log_own on download_logs for select using(user_id=auth.uid());
create or replace function block_role_change() returns trigger language plpgsql as $$begin if (new.role<>old.role or new.is_blocked<>old.is_blocked) and auth.uid() is not null and not is_admin() then raise exception 'forbidden';end if;return new;end$$;
create or replace function handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$begin insert into profiles(id,email,full_name) values(new.id,new.email,new.raw_user_meta_data->>'full_name');return new;end$$;
create or replace function register_download(rid uuid) returns void language plpgsql security definer set search_path=public as $$begin
 if exists(select 1 from software_releases where id=rid and status='published') and not exists(select 1 from profiles where id=auth.uid() and is_blocked) then
  update software_releases set download_count=download_count+1 where id=rid; insert into download_logs(release_id,user_id) values(rid,auth.uid());end if;end$$;
insert into features(title,description,icon,display_order,status) values
('Voice Intelligence','Talk to JARVIS naturally.','🎙️',1,'soon'),('AI Conversations','Context-aware dialogue.','💬',2,'soon'),('PC Automation','Run tasks on your PC by command.','⚙️',3,'soon'),
('Smart File Management','Find and organize files.','📁',4,'soon'),('Keyboard & Mouse Control','Hands-free input control.','🖱️',5,'soon'),('Weather Intelligence','Live forecasts on request.','🌦️',6,'soon'),
('Screen Understanding','Understand what is on screen.','🖥️',7,'soon'),('Smart Message Assistance','Draft and reply to messages.','✉️',8,'soon'),('Face Recognition','Recognize authorized users.','🧑',9,'soon'),
('Gesture Control','Control JARVIS with gestures.','✋',10,'soon'),('Online AI Intelligence','Connect to online AI models.','🌐',11,'soon'),('Future AI Capabilities','More coming over time.','🚀',12,'soon');
-- Mark a feature live in Admin > Features by editing its Status to: available
