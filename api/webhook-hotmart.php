<?php
// ══════════════════════════════════════════════════════════════════════
// WEBHOOK DE VENDA — versão PHP (alternativa à Edge Function).
//
// Use este arquivo só se o cliente já tem uma hospedagem com PHP e
// prefere não usar a Supabase CLI. Faz exatamente o mesmo que
// supabase/functions/webhook-hotmart/index.ts.
//
// 1. Preencha as três constantes abaixo (ou defina como variáveis de
//    ambiente, que têm prioridade).
// 2. Suba o arquivo para, por exemplo, /api/webhook-hotmart.php
// 3. Na Hotmart (Ferramentas → Webhook), aponte para a URL pública dele
//    nos eventos "Compra aprovada" e "Compra completa".
//
// ATENÇÃO: a SERVICE KEY dá acesso total ao banco. Este arquivo NUNCA
// pode ficar dentro de uma pasta pública que sirva o código-fonte .php
// como texto, nem ser commitado num repositório público.
// ══════════════════════════════════════════════════════════════════════

define('SUPABASE_URL',         getenv('SUPABASE_URL')         ?: 'https://xxxxxxxx.supabase.co');
define('SUPABASE_SERVICE_KEY', getenv('SUPABASE_SERVICE_KEY') ?: 'COLE_AQUI_A_SERVICE_ROLE_KEY');
define('HOTMART_HOTTOK',       getenv('HOTMART_HOTTOK')       ?: 'COLE_AQUI_O_HOTTOK');

$raw   = file_get_contents('php://input');
$event = json_decode($raw, true) ?: [];

// ---- Autenticação (hottok) ----
$hottok = $_SERVER['HTTP_X_HOTMART_HOTTOK'] ?? ($event['hottok'] ?? '');
if (!HOTMART_HOTTOK || !hash_equals(HOTMART_HOTTOK, (string) $hottok)) {
  http_response_code(401);
  echo json_encode(['error' => 'unauthorized']);
  exit;
}

// ---- Só contamos vendas efetivamente aprovadas ----
$type     = $event['event'] ?? ($event['status'] ?? '');
$aprovado = in_array($type, ['PURCHASE_APPROVED', 'PURCHASE_COMPLETE', 'APPROVED', 'COMPLETE'], true);

if ($aprovado) {
  $data     = $event['data'] ?? [];
  $purchase = $data['purchase'] ?? [];
  $tracking = $purchase['tracking'] ?? [];
  $origin   = $purchase['origin'] ?? [];
  $buyer    = $data['buyer'] ?? [];

  // O campo do sck varia conforme o tipo de link — lemos todos os
  // lugares conhecidos, na ordem em que costumam aparecer.
  $sck = $origin['sck']
      ?? $tracking['source_sck']
      ?? $purchase['sckPaymentLink']
      ?? $origin['src']
      ?? $tracking['sck']
      ?? $tracking['source']
      ?? $purchase['sck']
      ?? $event['sck']
      ?? '';
  $sck = trim((string) $sck);
  if ($sck === 'sckPaymentLinkTest') $sck = '';  // valor do teste da Hotmart

  $transaction = $purchase['transaction'] ?? ($data['transaction'] ?? ($event['transaction'] ?? null));
  $nome  = $buyer['name']  ?? ($data['buyer_name']  ?? null);
  $email = $buyer['email'] ?? ($data['buyer_email'] ?? null);

  if ($sck !== '') {
    registrar_indicacao($sck, $transaction, $nome, $email);
  } else {
    error_log("webhook: venda aprovada sem sck (transaction={$transaction}) — ignorada");
  }
}

// Sempre 200 para a plataforma não reenviar vendas que não são de indicação.
http_response_code(200);
echo json_encode(['status' => 'ok']);

// ══════════════════════════════════════════════════════════════════════
function registrar_indicacao($sck, $transaction, $nome, $email) {
  // 1. Acha o indicador dono do código (codigo é único).
  $refs = supa_get('/rest/v1/referrers?codigo=eq.' . rawurlencode($sck) . '&select=id,campaign_id&limit=1');
  if (empty($refs[0]['id'])) {
    error_log("webhook: sck '{$sck}' não corresponde a nenhum indicador");
    return;
  }

  // 2. Idempotência — a mesma transação nunca conta dois pontos.
  if ($transaction) {
    $ja = supa_get('/rest/v1/referral_leads?transaction=eq.' . rawurlencode($transaction) . '&select=id&limit=1');
    if (!empty($ja)) {
      error_log("webhook: transação {$transaction} já registrada — ignorada");
      return;
    }
  }

  // 3. Insere o lead — o trigger soma +1 ponto ao indicador.
  supa_post('/rest/v1/referral_leads', json_encode([
    'referrer_id' => $refs[0]['id'],
    'campaign_id' => $refs[0]['campaign_id'],
    'codigo'      => $sck,
    'nome'        => $nome,
    'email'       => $email,
    'transaction' => $transaction,
  ]));
  error_log("webhook: +1 ponto para o indicador {$refs[0]['id']} (sck={$sck})");
}

function supa_headers() {
  return [
    'Content-Type: application/json',
    'apikey: ' . SUPABASE_SERVICE_KEY,
    'Authorization: Bearer ' . SUPABASE_SERVICE_KEY,
  ];
}

function supa_get($path) {
  $ch = curl_init(SUPABASE_URL . $path);
  curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_HTTPHEADER     => supa_headers(),
  ]);
  $r = curl_exec($ch);
  curl_close($ch);
  return json_decode($r, true) ?: [];
}

function supa_post($path, $body) {
  $ch = curl_init(SUPABASE_URL . $path);
  curl_setopt_array($ch, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_POST           => true,
    CURLOPT_POSTFIELDS     => $body,
    CURLOPT_HTTPHEADER     => supa_headers(),
  ]);
  $r    = curl_exec($ch);
  $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
  curl_close($ch);
  if ($code >= 400) error_log("Supabase POST error [{$code}]: {$r}");
}
