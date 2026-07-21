create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Keep-alive: o plano free pausa o projeto apos 7 dias sem "user database
-- activity". Este job faz, todo dia, uma chamada HTTPS real a propria API
-- REST do projeto -- que chega ao PostgREST como requisicao de usuario e
-- por isso zera o contador de inatividade.
-- Um pg_cron puro (so SQL interno) nao serviria: seria atividade de
-- sistema, nao requisicao de usuario.
select cron.unschedule('keepalive-supabase')
  where exists (select 1 from cron.job where jobname = 'keepalive-supabase');

select cron.schedule(
  'keepalive-supabase',
  '17 9 * * *',              -- todo dia as 09:17 UTC (06:17 em Brasilia)
  $job$
  select net.http_post(
    url     := 'https://vribvelmuhwdcoxcermd.supabase.co/rest/v1/rpc/ig_total',
    headers := jsonb_build_object(
                 'Content-Type', 'application/json',
                 'apikey',        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZyaWJ2ZWxtdWh3ZGNveGNlcm1kIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ1OTQ0ODYsImV4cCI6MjEwMDE3MDQ4Nn0.-u4V9Cg1x-uCcGjBnlOQBvDy7jyFb68nfPLFsFTEKG4',
                 'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZyaWJ2ZWxtdWh3ZGNveGNlcm1kIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ1OTQ0ODYsImV4cCI6MjEwMDE3MDQ4Nn0.-u4V9Cg1x-uCcGjBnlOQBvDy7jyFb68nfPLFsFTEKG4'
               ),
    body    := jsonb_build_object('p_campaign', 'virada-coordenacao-2026')
  );
  $job$
);
