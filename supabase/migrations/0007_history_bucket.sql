-- Storage bucket for user history images (public read; authenticated write).
insert into storage.buckets (id, name, public)
values ('history', 'history', true)
on conflict (id) do nothing;

-- Authenticated team members may upload/update/delete history images.
create policy "history_write" on storage.objects
  for all to authenticated
  using (bucket_id = 'history')
  with check (bucket_id = 'history');
