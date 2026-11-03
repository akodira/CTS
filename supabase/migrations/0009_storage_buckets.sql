-- CTS migration 0009
-- Storage buckets and attachment authorization hooks.

begin;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'attachments',
  'attachments',
  false,
  26214400,
  array[
    'application/pdf',
    'image/png',
    'image/jpeg',
    'image/webp',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'text/csv',
    'text/plain',
    'application/zip'
  ]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Access is granted by application logic after ticket/attachment authorization:
--   1. draft uploads are restricted to the owner via a future storage policy
--   2. downloads go through /api/attachments/[id]/download which issues a
--      short-lived signed URL after checking private.can_view_ticket
--   3. service role is never exposed to the browser

commit;
