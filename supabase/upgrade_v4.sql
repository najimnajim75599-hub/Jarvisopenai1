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
