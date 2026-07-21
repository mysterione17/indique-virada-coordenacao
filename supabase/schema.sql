-- ══════════════════════════════════════════════════════════════════════
-- INDIQUE & GANHE — schema completo
-- Cole tudo isto no SQL Editor do Supabase do cliente e rode uma vez.
-- É idempotente: pode rodar de novo sem quebrar nada.
-- ══════════════════════════════════════════════════════════════════════

-- ── TABELAS ───────────────────────────────────────────────────────────

-- Quem indica.
create table if not exists public.referrers (
  id          uuid primary key default gen_random_uuid(),
  campaign_id text not null,
  nome        text not null,
  email       text not null,
  whatsapp    text,
  codigo      text not null unique,
  pontos      integer not null default 0,
  created_at  timestamptz not null default now()
);

-- Um mesmo e-mail só entra uma vez por campanha (case-insensitive).
create unique index if not exists referrers_campaign_email_uidx
  on public.referrers (campaign_id, lower(email));
create index if not exists referrers_campaign_pontos_idx
  on public.referrers (campaign_id, pontos desc);

-- Vendas atribuídas a um indicador (uma linha = 1 ponto).
create table if not exists public.referral_leads (
  id          uuid primary key default gen_random_uuid(),
  referrer_id uuid references public.referrers(id) on delete set null,
  campaign_id text not null,
  codigo      text,
  nome        text,
  email       text,
  transaction text,
  created_at  timestamptz not null default now()
);

-- Idempotência: a mesma transação nunca conta dois pontos.
create unique index if not exists referral_leads_transaction_uidx
  on public.referral_leads (transaction) where transaction is not null;
create index if not exists referral_leads_referrer_idx
  on public.referral_leads (referrer_id);

-- Cliques nos links de indicação (métrica de topo de funil).
create table if not exists public.referral_clicks (
  id          uuid primary key default gen_random_uuid(),
  campaign_id text not null,
  codigo      text,
  user_agent  text,
  created_at  timestamptz not null default now()
);

-- ── TRIGGER: cada lead soma +1 ponto ao indicador ─────────────────────
create or replace function public.bump_referrer_pontos()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if new.referrer_id is not null then
    update public.referrers set pontos = pontos + 1 where id = new.referrer_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_bump_referrer_pontos on public.referral_leads;
create trigger trg_bump_referrer_pontos
  after insert on public.referral_leads
  for each row execute function public.bump_referrer_pontos();

-- Função de trigger não deve ser chamável via /rest/v1/rpc.
revoke all on function public.bump_referrer_pontos() from public, anon, authenticated;

-- ══════════════════════════════════════════════════════════════════════
-- SEGURANÇA
--
-- A página é estática, então a chave anon fica visível no código-fonte.
-- Por isso NINGUÉM lê as tabelas direto: o site só chama as funções
-- abaixo, que devolvem apenas o que pode ser público. E-mail e WhatsApp
-- dos inscritos nunca saem em listagem.
-- O painel /admin lê as tabelas com um usuário autenticado de verdade.
-- ══════════════════════════════════════════════════════════════════════

alter table public.referrers       enable row level security;
alter table public.referral_leads  enable row level security;
alter table public.referral_clicks enable row level security;

-- Ninguém com a chave pública lê nada direto.
drop policy if exists "anon select referrers"   on public.referrers;
drop policy if exists "anon insert referrers"   on public.referrers;
drop policy if exists "anon select leads"       on public.referral_leads;
drop policy if exists "anon select clicks"      on public.referral_clicks;
drop policy if exists "anon insert clicks"      on public.referral_clicks;

-- Usuários logados (o dono da campanha, no /admin) leem tudo.
drop policy if exists "auth read referrers" on public.referrers;
create policy "auth read referrers" on public.referrers
  for select to authenticated using (true);

drop policy if exists "auth read leads" on public.referral_leads;
create policy "auth read leads" on public.referral_leads
  for select to authenticated using (true);

drop policy if exists "auth read clicks" on public.referral_clicks;
create policy "auth read clicks" on public.referral_clicks
  for select to authenticated using (true);

-- ── FUNÇÕES PÚBLICAS (o que a página estática pode chamar) ────────────

-- Cadastra o indicador, ou devolve o que já existe para aquele e-mail.
create or replace function public.ig_registrar(
  p_campaign text, p_nome text, p_email text, p_whatsapp text, p_codigo text
) returns table (id uuid, nome text, email text, codigo text, pontos integer)
language plpgsql security definer set search_path to 'public' as $$
declare v_row public.referrers%rowtype;
begin
  if coalesce(trim(p_nome),'') = '' or coalesce(trim(p_email),'') = '' then
    raise exception 'Nome e e-mail são obrigatórios.';
  end if;

  -- as colunas vão sempre qualificadas (r.), senão colidem com os
  -- parâmetros de saída da função (nome, email, codigo, pontos).
  select r.* into v_row from public.referrers r
   where r.campaign_id = p_campaign and lower(r.email) = lower(trim(p_email));

  if not found then
    insert into public.referrers (campaign_id, nome, email, whatsapp, codigo)
    values (p_campaign, trim(p_nome), lower(trim(p_email)), p_whatsapp, p_codigo)
    returning * into v_row;
  end if;

  return query select v_row.id, v_row.nome, v_row.email, v_row.codigo, v_row.pontos;
end;
$$;

-- "Login" pelo e-mail: devolve o cadastro daquele e-mail, se existir.
create or replace function public.ig_buscar(p_campaign text, p_email text)
returns table (id uuid, nome text, email text, codigo text, pontos integer)
language sql security definer set search_path to 'public' as $$
  select r.id, r.nome, r.email, r.codigo, r.pontos
    from public.referrers r
   where r.campaign_id = p_campaign
     and lower(r.email) = lower(trim(p_email));
$$;

-- Ranking público — só nome, código e pontos.
create or replace function public.ig_ranking(p_campaign text)
returns table (nome text, codigo text, pontos integer)
language sql security definer set search_path to 'public' as $$
  select r.nome, r.codigo, r.pontos
    from public.referrers r
   where r.campaign_id = p_campaign
   order by r.pontos desc, r.created_at asc
   limit 50;
$$;

-- Total de participantes da campanha.
create or replace function public.ig_total(p_campaign text)
returns integer
language sql security definer set search_path to 'public' as $$
  select count(*)::int from public.referrers where campaign_id = p_campaign;
$$;

-- Conversões de UM indicador (o id é um uuid, funciona como senha).
create or replace function public.ig_conversoes(p_referrer_id uuid)
returns table (nome text, created_at timestamptz)
language sql security definer set search_path to 'public' as $$
  select l.nome, l.created_at
    from public.referral_leads l
   where l.referrer_id = p_referrer_id
   order by l.created_at desc;
$$;

-- Nome de quem indicou, para personalizar a faixa de convite.
create or replace function public.ig_nome_por_codigo(p_campaign text, p_codigo text)
returns text
language sql security definer set search_path to 'public' as $$
  select r.nome from public.referrers r
   where r.campaign_id = p_campaign and r.codigo = p_codigo limit 1;
$$;

-- Registra um clique no link de indicação.
create or replace function public.ig_click(p_campaign text, p_codigo text, p_ua text)
returns void
language sql security definer set search_path to 'public' as $$
  insert into public.referral_clicks (campaign_id, codigo, user_agent)
  values (p_campaign, p_codigo, left(coalesce(p_ua,''), 400));
$$;

-- Só estas funções ficam expostas à chave pública.
revoke all on function public.ig_registrar(text,text,text,text,text)   from public, anon;
revoke all on function public.ig_buscar(text,text)                      from public, anon;
revoke all on function public.ig_ranking(text)                          from public, anon;
revoke all on function public.ig_total(text)                            from public, anon;
revoke all on function public.ig_conversoes(uuid)                       from public, anon;
revoke all on function public.ig_nome_por_codigo(text,text)             from public, anon;
revoke all on function public.ig_click(text,text,text)                  from public, anon;

grant execute on function public.ig_registrar(text,text,text,text,text) to anon, authenticated;
grant execute on function public.ig_buscar(text,text)                   to anon, authenticated;
grant execute on function public.ig_ranking(text)                       to anon, authenticated;
grant execute on function public.ig_total(text)                         to anon, authenticated;
grant execute on function public.ig_conversoes(uuid)                    to anon, authenticated;
grant execute on function public.ig_nome_por_codigo(text,text)          to anon, authenticated;
grant execute on function public.ig_click(text,text,text)               to anon, authenticated;
