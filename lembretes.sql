-- ===== LEMBRETES NO WHATSAPP (rode depois do schema.sql) =====
-- Avisa a profissional 1h e 30min antes de cada atendimento, via CallMeBot.
-- Configure a apikey no painel, aba "Avisos".
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;

create table public.reminder_settings(
  id smallint primary key default 1 check (id = 1),
  phone text not null default '',
  apikey text not null default '',
  enabled boolean not null default false
);
insert into public.reminder_settings(id) values (1) on conflict do nothing;
alter table public.reminder_settings enable row level security;
revoke all on public.reminder_settings from anon;
create policy admin_all on public.reminder_settings for all to authenticated using (is_admin()) with check (is_admin());

alter table public.bookings
  add column reminded_60 boolean not null default false,
  add column reminded_30 boolean not null default false;

create function public.reset_reminders() returns trigger language plpgsql set search_path=public as $$
begin
  if new.day is distinct from old.day or new.at_time is distinct from old.at_time then
    new.reminded_60 := false; new.reminded_30 := false;
  end if;
  return new;
end $$;
create trigger bookings_reset_reminders before update on public.bookings
  for each row execute function public.reset_reminders();

create function public.send_whatsapp(p_text text) returns bigint
language plpgsql security definer set search_path=public as $$
declare s reminder_settings;
begin
  select * into s from reminder_settings where id = 1;
  if s.phone = '' or s.apikey = '' then return null; end if;
  return net.http_get(
    url := 'https://api.callmebot.com/whatsapp.php',
    params := jsonb_build_object('phone', s.phone, 'text', p_text, 'apikey', s.apikey));
end $$;
revoke all on function public.send_whatsapp(text) from public, anon, authenticated;

create function public.send_reminders() returns int
language plpgsql security definer set search_path=public as $$
declare b record; n int := 0; label text;
begin
  if not coalesce((select enabled from reminder_settings where id = 1), false) then return 0; end if;
  for b in
    select bk.id, bk.at_time, bk.client_name, bk.reminded_60, s.name as svc,
           extract(epoch from (((bk.day + bk.at_time) at time zone 'America/Sao_Paulo') - now())) / 60 as mins
    from bookings bk join services s on s.id = bk.service_id
    where (bk.status = 'confirmado' or (bk.status = 'pendente' and bk.created_at > now() - interval '12 hours'))
      and not bk.reminded_30
      and ((bk.day + bk.at_time) at time zone 'America/Sao_Paulo') between now() and now() + interval '61 minutes'
  loop
    if b.mins <= 31 then
      label := case when b.mins >= 25 then '30 minutos' else greatest(round(b.mins), 1)::int || ' minutos' end;
      update bookings set reminded_30 = true, reminded_60 = true where id = b.id;
    elsif not b.reminded_60 then
      label := '1 hora';
      update bookings set reminded_60 = true where id = b.id;
    else
      continue;
    end if;
    -- LGPD: só o primeiro nome vai para o CallMeBot (sem telefone)
    perform send_whatsapp(format(E'⏰ Lembrete: atendimento em %s (%s)\n%s · %s',
      label, to_char(b.at_time, 'HH24:MI'), split_part(trim(b.client_name), ' ', 1), b.svc));
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.send_reminders() from public, anon, authenticated;

create function public.test_reminder() returns bigint
language plpgsql security definer set search_path=public as $$
begin
  if not is_admin() then raise exception 'not_admin'; end if;
  return send_whatsapp('✅ Teste do site: os lembretes de atendimento estão funcionando!');
end $$;

create function public.reminder_status(p_id bigint) returns text
language plpgsql security definer set search_path=public as $$
declare r record;
begin
  if not is_admin() then raise exception 'not_admin'; end if;
  select status_code, left(coalesce(content, error_msg, ''), 300) as body into r from net._http_response where id = p_id;
  if not found then return 'aguardando'; end if;
  return coalesce(r.status_code::text, 'erro') || ' ' || r.body;
end $$;
revoke all on function public.test_reminder(), public.reminder_status(bigint) from public, anon;
grant execute on function public.test_reminder(), public.reminder_status(bigint) to authenticated;

select cron.schedule('lembretes-atendimento', '* * * * *', 'select public.send_reminders()');

-- LGPD: anonimiza atendimentos antigos todo dia às 3h (Brasília)
select cron.schedule('anonimizar-antigos', '0 6 * * *', 'select public.anonimizar_antigos()');

-- ===== AVISOS PELO TELEGRAM (substitui o CallMeBot) =====
alter table public.reminder_settings
  add column if not exists tg_token text not null default '',
  add column if not exists tg_chat_id text not null default '';

create or replace function public.send_whatsapp(p_text text) returns bigint
language plpgsql security definer set search_path=public as $$
declare s reminder_settings;
begin
  select * into s from reminder_settings where id = 1;
  if s.tg_token <> '' and s.tg_chat_id <> '' then
    return net.http_post(
      url := 'https://api.telegram.org/bot' || s.tg_token || '/sendMessage',
      body := jsonb_build_object('chat_id', s.tg_chat_id, 'text', p_text),
      headers := '{"Content-Type": "application/json"}'::jsonb);
  end if;
  if s.phone = '' or s.apikey = '' then return null; end if;
  return net.http_get(
    url := 'https://api.callmebot.com/whatsapp.php',
    params := jsonb_build_object('phone', s.phone, 'text', p_text, 'apikey', s.apikey));
end $$;
revoke all on function public.send_whatsapp(text) from public, anon, authenticated;

create or replace function public.tg_connect() returns bigint
language plpgsql security definer set search_path=public as $$
declare t text;
begin
  if not is_admin() then raise exception 'not_admin'; end if;
  select tg_token into t from reminder_settings where id = 1;
  if coalesce(t, '') = '' then raise exception 'sem_token'; end if;
  return net.http_get(url := 'https://api.telegram.org/bot' || t || '/getUpdates');
end $$;

create or replace function public.tg_finish(p_id bigint) returns text
language plpgsql security definer set search_path=public as $$
declare r record; j jsonb; msg jsonb;
begin
  if not is_admin() then raise exception 'not_admin'; end if;
  select status_code, content into r from net._http_response where id = p_id;
  if not found then return 'aguardando'; end if;
  if r.status_code <> 200 then return 'token_invalido'; end if;
  j := r.content::jsonb;
  select coalesce(e->'message', e->'my_chat_member') into msg
    from jsonb_array_elements(j->'result') e order by (e->>'update_id')::bigint desc limit 1;
  if msg is null then return 'sem_mensagem'; end if;
  update reminder_settings set tg_chat_id = msg->'chat'->>'id', enabled = true where id = 1;
  return 'ok:' || coalesce(msg->'chat'->>'first_name', msg->'from'->>'first_name', '');
end $$;
revoke all on function public.tg_connect(), public.tg_finish(bigint) from public, anon;
grant execute on function public.tg_connect(), public.tg_finish(bigint) to authenticated;
