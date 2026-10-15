// Sprawdza klucz API App Store Connect (ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8): podpisuje token JWT (ES256) i pyta
// o aplikację ASC_APP_ID. Wypisuje tylko kod odpowiedzi i opis błędu — nigdy wartości sekretów.
// Użycie w CI (Node 18+): node scripts/ci/check-asc-key.js
'use strict';
const crypto = require('node:crypto');
const https = require('node:https');

const { ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, ASC_APP_ID } = process.env;

function fail(message) {
  console.log(`::error title=Klucz API App Store Connect::${message}`);
  process.exit(1);
}

let pem = ASC_KEY_P8 || '';
if (!pem.includes('BEGIN PRIVATE KEY')) {
  pem = Buffer.from(pem, 'base64').toString('utf8');
}
if (!pem.includes('BEGIN PRIVATE KEY')) fail('ASC_KEY_P8 nie zawiera klucza prywatnego .p8 (PEM albo base64 PEM).');

const b64url = (input) => Buffer.from(input).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const header = { alg: 'ES256', kid: ASC_KEY_ID.trim(), typ: 'JWT' };
const payload = { iss: ASC_ISSUER_ID.trim(), iat: now, exp: now + 600, aud: 'appstoreconnect-v1' };
const signingInput = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`;
const signature = crypto.sign('sha256', Buffer.from(signingInput), { key: pem, dsaEncoding: 'ieee-p1363' });
const token = `${signingInput}.${signature.toString('base64url')}`;

// Wskazówki bez ujawniania wartości: długości i znaki niedrukowalne.
const hints = [];
if (ASC_KEY_ID !== ASC_KEY_ID.trim()) hints.push('ASC_KEY_ID ma spacje lub znak nowej linii na brzegach');
if (ASC_ISSUER_ID !== ASC_ISSUER_ID.trim()) hints.push('ASC_ISSUER_ID ma spacje lub znak nowej linii na brzegach');
if (!/^[A-Z0-9]{10}$/.test(ASC_KEY_ID.trim())) hints.push(`ASC_KEY_ID ma ${ASC_KEY_ID.trim().length} znaków (oczekiwano 10 znaków A–Z i cyfr)`);
if (!/^[0-9a-f-]{36}$/i.test(ASC_ISSUER_ID.trim())) hints.push(`ASC_ISSUER_ID ma ${ASC_ISSUER_ID.trim().length} znaków (oczekiwano UUID, 36 znaków)`);
for (const hint of hints) console.log(`Wskazówka: ${hint}`);

const request = https.request(
  {
    host: 'api.appstoreconnect.apple.com',
    path: `/v1/apps/${encodeURIComponent((ASC_APP_ID || '').trim())}?fields[apps]=bundleId`,
    headers: { Authorization: `Bearer ${token}` },
  },
  (response) => {
    let body = '';
    response.on('data', (chunk) => (body += chunk));
    response.on('end', () => {
      if (response.statusCode === 200) {
        const bundleId = JSON.parse(body).data.attributes.bundleId;
        console.log(`Klucz API działa. Aplikacja ${ASC_APP_ID.trim()}: ${bundleId}`);
        return;
      }
      let detail = '';
      try {
        detail = JSON.parse(body).errors.map((e) => `${e.code}: ${e.title}`).join('; ');
      } catch {
        detail = body.slice(0, 200);
      }
      fail(`App Store Connect odpowiedział ${response.statusCode} (${detail}).`);
    });
  },
);
request.on('error', (error) => fail(`Brak połączenia z App Store Connect: ${error.message}`));
request.end();
