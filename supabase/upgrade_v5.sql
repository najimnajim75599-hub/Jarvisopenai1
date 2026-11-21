-- v5: downloads are public. No account or email confirmation is required.
update storage.buckets set public=true where id='releases';
drop policy if exists rel_dl on storage.objects;
create policy rel_dl on storage.objects for select using(bucket_id='releases');
