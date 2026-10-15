// Wypisuje token JWT (ES256, ważny 15 minut) dla API App Store Connect na podstawie ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8.
// Użycie: TOKEN="$(node scripts/ci/asc-jwt.js)"
'use strict';
const crypto = require('node:crypto');

const { ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 } = process.env;
let pem = ASC_KEY_P8 || '';
if (!pem.includes('BEGIN PRIVATE KEY')) pem = Buffer.from(pem, 'base64').toString('utf8');
if (!pem.includes('BEGIN PRIVATE KEY')) {
  console.error('ASC_KEY_P8 nie zawiera klucza prywatnego .p8');
  process.exit(1);
}
const b64url = (input) => Buffer.from(input).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const header = { alg: 'ES256', kid: ASC_KEY_ID.trim(), typ: 'JWT' };
const payload = { iss: ASC_ISSUER_ID.trim(), iat: now, exp: now + 900, aud: 'appstoreconnect-v1' };
const input = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`;
const signature = crypto.sign('sha256', Buffer.from(input), { key: pem, dsaEncoding: 'ieee-p1363' });
const token = `${input}.${signature.toString('base64url')}`;
process.stdout.write(token + '\n');
