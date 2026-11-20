-- ===== AGENDA MANICURE · Supabase =====
create table public.admins(user_id uuid primary key references auth.users on delete cascade);
create table public.services(id serial primary key, name text not null, price_cents int not null check(price_cents>=0), duration_min int not null default 60, active boolean not null default true);
create table public.weekly_hours(weekday smallint not null check(weekday between 0 and 6), at_time time not null, primary key(weekday,at_time)); -- 0=domingo
create table public.days_off(day date primary key, reason text);
create table public.bookings(
  id uuid primary key default gen_random_uuid(),
  service_id int not null references services(id),
  day date not null, at_time time not null,
  client_name text not null check(char_length(client_name) between 2 and 80),
  client_phone text not null check(client_phone ~ '^[0-9]{10,11}$'),
  status text not null default 'pendente' check(status in ('pendente','confirmado','atendido','cancelado','expirado')),
  consent_at timestamptz not null default now(),
  created_at timestamptz not null default now());
-- Conflito barrado no banco (só pendente/confirmado ocupam o horário)
create unique index one_active_per_slot on bookings(day,at_time) where status in ('pendente','confirmado');

-- RLS: tudo fechado; público não lê nem escreve em bookings
alter table admins enable row level security;
alter table services enable row level security;
alter table weekly_hours enable row level security;
alter table days_off enable row level security;
alter table bookings enable row level security;
revoke all on admins, weekly_hours, days_off, bookings from anon;
revoke all on services from anon; grant select on services to anon;

create function public.is_admin() returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from admins where user_id=auth.uid()) $$;

create policy admin_all on bookings for all to authenticated using(is_admin()) with check(is_admin());
create policy admin_all on services for all to authenticated using(is_admin()) with check(is_admin());
create policy admin_all on weekly_hours for all to authenticated using(is_admin()) with check(is_admin());
create policy admin_all on days_off for all to authenticated using(is_admin()) with check(is_admin());
create policy public_read on services for select to anon using(active);

-- Horários livres levando em conta a DURAÇÃO dos serviços.
-- Um horário só aparece se o serviço escolhido cabe nele sem encostar em nenhum atendimento já marcado.
-- Devolve só horas, nunca dados de clientes. As clientes podem marcar até 1 ano à frente.
create function public.available_slots(p_day date, p_service int default null) returns table(at_time time)
language sql stable security definer set search_path=public as $$
  with hoje as (select (now() at time zone 'America/Sao_Paulo') as agora),
  dur as (select coalesce((select duration_min from services where id = p_service), 1) as minutos),
  ocupado as (
    select b.at_time as ini, b.at_time + make_interval(mins => s.duration_min) as fim
    from bookings b join services s on s.id = b.service_id
    where b.day = p_day
      and (b.status = 'confirmado' or (b.status = 'pendente' and b.created_at > now() - interval '12 hours'))
  )
  select w.at_time from weekly_hours w, hoje, dur
  where w.weekday = extract(dow from p_day)::int
    and p_day between hoje.agora::date and hoje.agora::date + 365
    and (p_day > hoje.agora::date or w.at_time > hoje.agora::time)
    and not exists (select 1 from days_off d where d.day = p_day)
    and not exists (select 1 from ocupado o
                    where w.at_time < o.fim and w.at_time + make_interval(mins => dur.minutos) > o.ini)
  order by 1 $$;

-- Dias que abrem para agendamento (para o calendário das clientes): só dias da semana com horário e folgas
create function public.calendar_info() returns jsonb
language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'hoje', (now() at time zone 'America/Sao_Paulo')::date,
    'limite', (now() at time zone 'America/Sao_Paulo')::date + 365,
    'dias_semana', coalesce((select jsonb_agg(distinct weekday) from weekly_hours), '[]'::jsonb),
    'folgas', coalesce((select jsonb_agg(day) from days_off
                        where day between (now() at time zone 'America/Sao_Paulo')::date
                                      and (now() at time zone 'America/Sao_Paulo')::date + 365), '[]'::jsonb)
  ) $$;

create function public.create_booking(p_service int,p_day date,p_time time,p_name text,p_phone text,p_consent boolean)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_phone text := regexp_replace(coalesce(p_phone,''),'\D','','g');
begin
  if not coalesce(p_consent,false) then raise exception 'consent_required'; end if;
  if char_length(trim(coalesce(p_name,''))) not between 2 and 80 or v_phone !~ '^[0-9]{10,11}$' then raise exception 'invalid_data'; end if;
  if not exists(select 1 from services where id=p_service and active) then raise exception 'invalid_data'; end if;
  -- Uma reserva por vez no mesmo dia: evita duas clientes pegarem horários que se sobrepõem ao mesmo tempo
  perform pg_advisory_xact_lock(hashtext('agenda:' || p_day::text));
  if not exists(select 1 from available_slots(p_day, p_service) a where a.at_time=p_time) then raise exception 'slot_taken'; end if;
  if (select count(*) from bookings where client_phone=v_phone and status='pendente' and created_at>now()-interval '12 hours')>=2 then raise exception 'too_many'; end if;
  update bookings set status='expirado' where day=p_day and at_time=p_time and status='pendente' and created_at<=now()-interval '12 hours';
  insert into bookings(service_id,day,at_time,client_name,client_phone) values(p_service,p_day,p_time,trim(p_name),v_phone) returning id into v_id;
  return v_id;
exception when unique_violation then raise exception 'slot_taken';
end $$;
revoke all on function available_slots(date, int), calendar_info(), create_booking(int,date,time,text,text,boolean) from public;
grant execute on function available_slots(date, int), calendar_info(), create_booking(int,date,time,text,text,boolean) to anon, authenticated;

-- LGPD: anonimiza atendimentos encerrados há mais de 6 meses (rode mensalmente ou agende com pg_cron)
create function public.anonimizar_antigos() returns int language sql security definer set search_path=public as $$
  with u as (update bookings set client_name='Anonimizado', client_phone='00000000000'
    where status in ('atendido','cancelado','expirado') and day < current_date - 180 and client_name<>'Anonimizado' returning 1)
  select count(*)::int from u $$;
revoke all on function anonimizar_antigos() from public, anon, authenticated;

-- Dados iniciais (edite) e ADMIN: crie o usuário da sua mãe em Authentication > Users, depois:
-- insert into admins(user_id) select id from auth.users where email='EMAIL_DELA';
insert into services(name,price_cents,duration_min) values ('Mão',3500,60),('Pé',3500,60),('Mão e Pé Tradicional',6000,120),('Alongamento em Gel',10000,180),('Esmaltação em Gel',6000,120),('Blindagem',6000,120),('Esmaltação Comum',1000,20),('Manutenção',8000,120);
insert into weekly_hours(weekday,at_time) select d,t::time from generate_series(2,6) d, unnest(array['09:00','10:30','13:00','14:30']) t;
