// Wysyła plik .ipa do App Store Connect przez API „build uploads” (REST, ten sam token JWT co dla zwykłego API).
// Powód: xcodebuild/altool nie uwierzytelniają się kluczem API w usłudze dostarczania (błąd 3004), a REST działa — research R19.
// Użycie: node scripts/ci/upload-build.js <plik.ipa> <wersja> <numer kompilacji>
// Środowisko: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, ASC_APP_ID. Wypisuje tylko stany i opisy błędów, nigdy sekretów.
'use strict';
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const [ipaPath, version, buildNumber] = process.argv.slice(2);
const { ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8, ASC_APP_ID } = process.env;
const API = 'https://api.appstoreconnect.apple.com';

function fail(message) {
  console.log(`::error title=Wysyłka do App Store Connect::${message}`);
  process.exit(1);
}
if (!ipaPath || !version || !buildNumber) fail('Użycie: upload-build.js <plik.ipa> <wersja> <numer kompilacji>');

let pem = ASC_KEY_P8 || '';
if (!pem.includes('BEGIN PRIVATE KEY')) pem = Buffer.from(pem, 'base64').toString('utf8');

function token() {
  const b64url = (input) => Buffer.from(input).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: 'ES256', kid: ASC_KEY_ID.trim(), typ: 'JWT' };
  const payload = { iss: ASC_ISSUER_ID.trim(), iat: now, exp: now + 1200, aud: 'appstoreconnect-v1' };
  const input = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`;
  const signature = crypto.sign('sha256', Buffer.from(input), { key: pem, dsaEncoding: 'ieee-p1363' });
  return `${input}.${signature.toString('base64url')}`;
}

async function api(method, route, body) {
  const response = await fetch(`${API}${route}`, {
    method,
    headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await response.text();
  if (!response.ok) {
    let detail = text.slice(0, 400);
    try {
      detail = JSON.parse(text).errors.map((e) => `${e.code}: ${e.title} — ${e.detail}`).join('; ');
    } catch {
      /* zostaje surowy tekst */
    }
    fail(`${method} ${route} → ${response.status}: ${detail}`);
  }
  return text ? JSON.parse(text) : {};
}

// Po wysyłce: czeka (do 10 min) aż kompilacja pojawi się w TestFlight i wypisuje jej stan dla testerów wewnętrznych.
// Nie przerywa przebiegu — wysyłka się udała; ostrzega, gdy stan wymaga działania właściciela (np. zgodność eksportowa).
async function reportTestFlightState() {
  for (let attempt = 0; attempt < 40; attempt++) {
    const builds = await api(
      'GET',
      `/v1/builds?filter[app]=${ASC_APP_ID.trim()}&filter[version]=${buildNumber}&filter[preReleaseVersion.version]=${version}&limit=1`,
    );
    const build = builds.data[0];
    if (build) {
      const processing = build.attributes.processingState;
      let internal = 'brak danych';
      try {
        const detail = await api('GET', `/v1/builds/${build.id}/buildBetaDetail`);
        internal = detail.data.attributes.internalBuildState;
      } catch {
        /* stan testerów bywa jeszcze niedostępny */
      }
      console.log(`TestFlight: przetwarzanie ${processing}, stan dla testerów wewnętrznych ${internal}`);
      if (processing === 'VALID') {
        if (internal === 'MISSING_EXPORT_COMPLIANCE') {
          console.log('::warning title=TestFlight::Kompilacja czeka na deklarację zgodności eksportowej (szyfrowanie) w App Store Connect.');
        }
        return;
      }
      if (processing === 'FAILED' || processing === 'INVALID') fail(`Kompilacja w TestFlight ma stan ${processing}.`);
    } else {
      console.log('TestFlight: kompilacja jeszcze niewidoczna');
    }
    await new Promise((resolve) => setTimeout(resolve, 15000));
  }
  console.log('::warning title=TestFlight::Kompilacja nie osiągnęła stanu VALID w 10 minut — sprawdź App Store Connect.');
}

async function main() {
  const file = fs.readFileSync(ipaPath);
  const md5 = crypto.createHash('md5').update(file).digest('hex');
  console.log(`Plik ${path.basename(ipaPath)}: ${file.length} bajtów, wersja ${version}, kompilacja ${buildNumber}`);

  const upload = await api('POST', '/v1/buildUploads', {
    data: {
      type: 'buildUploads',
      attributes: { cfBundleShortVersionString: version, cfBundleVersion: buildNumber, platform: 'IOS' },
      relationships: { app: { data: { type: 'apps', id: ASC_APP_ID.trim() } } },
    },
  });
  const uploadId = upload.data.id;
  console.log(`Utworzono wysyłkę ${uploadId}`);

  const created = await api('POST', '/v1/buildUploadFiles', {
    data: {
      type: 'buildUploadFiles',
      attributes: {
        fileName: path.basename(ipaPath),
        fileSize: file.length,
        assetType: 'ASSET',
        uti: 'com.apple.ipa',
      },
      relationships: { buildUpload: { data: { type: 'buildUploads', id: uploadId } } },
    },
  });
  const fileId = created.data.id;
  const operations = created.data.attributes.uploadOperations || [];
  console.log(`Plik zarejestrowany, operacji przesyłania: ${operations.length}`);

  for (const [index, operation] of operations.entries()) {
    const headers = {};
    for (const header of operation.requestHeaders || []) headers[header.name] = header.value;
    const chunk = file.subarray(operation.offset, operation.offset + operation.length);
    const response = await fetch(operation.url, { method: operation.method, headers, body: chunk });
    if (!response.ok) fail(`Przesyłanie części ${index + 1}/${operations.length} → ${response.status}`);
  }
  console.log('Wszystkie części przesłane');

  await api('PATCH', `/v1/buildUploadFiles/${fileId}`, {
    data: {
      type: 'buildUploadFiles',
      id: fileId,
      attributes: {
        uploaded: true,
        sourceFileChecksums: { file: { hash: md5, algorithm: 'MD5' } },
      },
    },
  });
  console.log('Plik oznaczony jako przesłany');

  for (let attempt = 0; attempt < 30; attempt++) {
    const state = (await api('GET', `/v1/buildUploads/${uploadId}`)).data.attributes.state || {};
    console.log(`Stan: ${state.state || 'nieznany'}`);
    if (state.state === 'COMPLETE') {
      console.log('Wysyłka zakończona — kompilacja przetwarzana w TestFlight.');
      await reportTestFlightState();
      return;
    }
    if (state.state === 'FAILED') {
      const errors = (state.errors || []).map((e) => `${e.code}: ${e.description}`).join('; ');
      fail(`Przetwarzanie nie powiodło się: ${errors}`);
    }
    await new Promise((resolve) => setTimeout(resolve, 10000));
  }
  fail('Przetwarzanie wysyłki trwa dłużej niż 5 minut — sprawdź App Store Connect.');
}

main().catch((error) => fail(error.message));
