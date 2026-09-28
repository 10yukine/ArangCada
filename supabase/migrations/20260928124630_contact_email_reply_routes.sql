-- Private routing metadata for Gmail replies to public contact mailboxes.
create table public.contact_email_reply_routes (
  inbound_email_id uuid primary key,
  customer_email text not null,
  mailbox text not null check (mailbox in (
    'support@arangcada.app', 'legal@arangcada.app', 'privacy@arangcada.app'
  )),
  original_subject text not null,
  original_message_id text,
  created_at timestamptz not null default now()
);

alter table public.contact_email_reply_routes enable row level security;
revoke all on public.contact_email_reply_routes from public, anon, authenticated;
grant select, insert on public.contact_email_reply_routes to service_role;
