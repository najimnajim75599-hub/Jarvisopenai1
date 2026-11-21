-- v5: downloads require an account. Guests can no longer obtain release files, even by calling the API directly.
drop policy if exists rel_dl on storage.objects;
create policy rel_dl on storage.objects for select to authenticated using(bucket_id='releases' and (is_admin() or (exists(select 1 from software_releases r where r.file_path=name and r.status='published') and not exists(select 1 from profiles where id=auth.uid() and is_blocked))));
