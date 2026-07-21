// ══════════════════════════════════════════════════════════════════════
// WEBHOOK DE VENDA — Supabase Edge Function (não precisa de servidor).
//
// A plataforma de pagamento chama esta URL a cada venda. Quando a compra
// é aprovada e veio com sck=<codigo do indicador>, gravamos um lead em
// referral_leads — o trigger do schema.sql soma +1 ponto ao indicador.
//
// COMO PUBLICAR
//   supabase functions deploy webhook-hotmart --no-verify-jwt
//   supabase secrets set HOTMART_HOTTOK=xxxxx CAMPAIGN_ID=campanha-2026
//
// URL para configurar na Hotmart (Ferramentas → Webhook):
//   https://<ref-do-projeto>.supabase.co/functions/v1/webhook-hotmart
//   Eventos: Compra aprovada / Compra completa.
//
// O --no-verify-jwt é obrigatório: quem chama é a Hotmart, não um usuário
// logado. A autenticação é feita pelo hottok, logo abaixo.
// ══════════════════════════════════════════════════════════════════════

const SUPABASE_URL  = Deno.env.get('SUPABASE_URL')!;
const SERVICE_KEY   = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const HOTTOK        = Deno.env.get('HOTMART_HOTTOK') ?? '';
const CAMPAIGN_ID   = Deno.env.get('CAMPAIGN_ID') ?? 'campanha';

const H = {
  'apikey': SERVICE_KEY,
  'Authorization': `Bearer ${SERVICE_KEY}`,
  'Content-Type': 'application/json',
};

Deno.serve(async (req) => {
  const body = await req.json().catch(() => ({} as any));

  // ── Autenticação ──
  // Webhook 2.0 manda no header X-HOTMART-HOTTOK; versões antigas no corpo.
  const hottok = req.headers.get('x-hotmart-hottok') ?? body?.hottok ?? '';
  if (!HOTTOK || hottok !== HOTTOK) {
    return json({ error: 'unauthorized' }, 401);
  }

  // ── Só contamos vendas efetivamente aprovadas ──
  const evento = body?.event ?? body?.status ?? '';
  const aprovado = ['PURCHASE_APPROVED', 'PURCHASE_COMPLETE', 'APPROVED', 'COMPLETE'].includes(evento);

  if (aprovado) {
    const data     = body?.data ?? {};
    const purchase = data?.purchase ?? {};
    const tracking = purchase?.tracking ?? {};
    const origin   = purchase?.origin ?? {};
    const buyer    = data?.buyer ?? {};

    // O campo do sck varia conforme o tipo de link. Lemos todos os
    // lugares conhecidos, na ordem em que costumam aparecer.
    let sck = String(
      origin?.sck ?? tracking?.source_sck ?? purchase?.sckPaymentLink ??
      origin?.src ?? tracking?.sck ?? tracking?.source ??
      purchase?.sck ?? body?.sck ?? ''
    ).trim();

    if (sck === 'sckPaymentLinkTest') sck = '';  // valor do teste da Hotmart

    const transaction = purchase?.transaction ?? data?.transaction ?? body?.transaction ?? null;

    if (sck) {
      await registrarIndicacao(sck, transaction, buyer?.name ?? null, buyer?.email ?? null);
    } else {
      console.log(`venda aprovada sem sck (transaction=${transaction}) — ignorada`);
    }
  }

  // Sempre 200: assim a plataforma não fica reenviando vendas que não
  // são de indicação.
  return json({ status: 'ok' }, 200);
});

async function registrarIndicacao(
  sck: string, transaction: string | null, nome: string | null, email: string | null,
) {
  // 1. Acha o indicador dono do código (codigo é único).
  const refs = await get(`/referrers?codigo=eq.${encodeURIComponent(sck)}&select=id,campaign_id&limit=1`);
  if (!refs?.[0]?.id) {
    console.log(`sck '${sck}' não corresponde a nenhum indicador`);
    return;
  }

  // 2. Idempotência — a mesma transação nunca conta dois pontos.
  //    (o índice único em referral_leads.transaction também garante isso)
  if (transaction) {
    const ja = await get(`/referral_leads?transaction=eq.${encodeURIComponent(transaction)}&select=id&limit=1`);
    if (ja?.length) {
      console.log(`transação ${transaction} já registrada — ignorada`);
      return;
    }
  }

  // 3. Insere o lead — o trigger soma +1 ponto ao indicador.
  const r = await fetch(`${SUPABASE_URL}/rest/v1/referral_leads`, {
    method: 'POST',
    headers: H,
    body: JSON.stringify({
      referrer_id: refs[0].id,
      campaign_id: refs[0].campaign_id ?? CAMPAIGN_ID,
      codigo: sck,
      nome, email, transaction,
    }),
  });
  if (!r.ok) console.error('erro ao inserir lead:', r.status, await r.text());
  else console.log(`+1 ponto para o indicador ${refs[0].id} (sck=${sck})`);
}

async function get(path: string) {
  const r = await fetch(`${SUPABASE_URL}/rest/v1${path}`, { headers: H });
  return r.ok ? await r.json() : [];
}

function json(obj: unknown, status: number) {
  return new Response(JSON.stringify(obj), {
    status, headers: { 'Content-Type': 'application/json' },
  });
}
