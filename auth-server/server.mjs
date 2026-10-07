import { createServer } from 'node:http';
import { randomBytes } from 'node:crypto';

const clientId = process.env.IG_CLIENT_ID;
const clientSecret = process.env.IG_CLIENT_SECRET;
const redirectURI = process.env.IG_REDIRECT_URI;
const callbackScheme = 'quietreels';
const port = Number(process.env.PORT || 8787);
const host = process.env.HOST || '127.0.0.1';

if (!clientId || !clientSecret || !redirectURI ||
    new URL(redirectURI).protocol !== 'https:') {
  throw new Error('Set IG_CLIENT_ID, IG_CLIENT_SECRET, and an HTTPS IG_REDIRECT_URI.');
}

const pendingStates = new Map();
const pendingTickets = new Map();
const ttl = 5 * 60 * 1000;

function fresh() { return randomBytes(32).toString('base64url'); }
function clean() {
  const now = Date.now();
  for (const [key, value] of pendingStates) if (value.expires < now) pendingStates.delete(key);
  for (const [key, value] of pendingTickets) if (value.expires < now) pendingTickets.delete(key);
}
function json(response, status, body) {
  response.writeHead(status, { 'Content-Type': 'application/json',
    'Cache-Control': 'no-store', 'Pragma': 'no-cache' });
  response.end(JSON.stringify(body));
}
function redirect(response, location) {
  response.writeHead(302, { Location: location, 'Cache-Control': 'no-store',
    'Referrer-Policy': 'no-referrer' });
  response.end();
}
async function body(request) {
  let text = '';
  for await (const chunk of request) {
    text += chunk;
    if (text.length > 4096) throw new Error('Request is too large.');
  }
  return JSON.parse(text);
}
async function exchange(code) {
  const form = new URLSearchParams({ client_id: clientId,
    client_secret: clientSecret, grant_type: 'authorization_code',
    redirect_uri: redirectURI, code });
  const shortResponse = await fetch('https://api.instagram.com/oauth/access_token', {
    method: 'POST', body: form,
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' }
  });
  const shortBody = await shortResponse.json();
  const candidates = shortBody.access_token ? [shortBody.access_token] :
    (Array.isArray(shortBody.data) ? shortBody.data.map(item => item.access_token) : []);
  const shortToken = candidates.length === 1 ? candidates[0] : null;
  if (!shortResponse.ok || !shortToken) {
    throw new Error(shortBody.error_message || shortBody.error?.message ||
      'Instagram rejected the authorization code.');
  }
  const longURL = new URL('https://graph.instagram.com/access_token');
  longURL.searchParams.set('grant_type', 'ig_exchange_token');
  longURL.searchParams.set('client_secret', clientSecret);
  longURL.searchParams.set('access_token', shortToken);
  const longResponse = await fetch(longURL);
  const longBody = await longResponse.json();
  if (!longResponse.ok || !longBody.access_token || !longBody.expires_in) {
    throw new Error(longBody.error?.message || 'Instagram did not return a long-lived token.');
  }
  return { access_token: longBody.access_token, expires_in: longBody.expires_in };
}

createServer(async (request, response) => {
  clean();
  const url = new URL(request.url, redirectURI);
  try {
    if (request.method === 'GET' && url.pathname === '/health') {
      return json(response, 200, { ok: true });
    }
    if (request.method === 'GET' && url.pathname === '/auth/start') {
      const nonce = url.searchParams.get('nonce');
      if (!nonce || !/^[a-fA-F0-9-]{36}$/.test(nonce)) {
        return json(response, 400, { error: 'Missing app nonce.' });
      }
      const state = fresh();
      pendingStates.set(state, { expires: Date.now() + ttl, nonce });
      const authorize = new URL('https://www.instagram.com/oauth/authorize');
      authorize.searchParams.set('client_id', clientId);
      authorize.searchParams.set('redirect_uri', redirectURI);
      authorize.searchParams.set('response_type', 'code');
      authorize.searchParams.set('scope', 'instagram_business_basic');
      authorize.searchParams.set('state', state);
      return redirect(response, authorize.href);
    }
    if (request.method === 'GET' && url.pathname === new URL(redirectURI).pathname) {
      const state = url.searchParams.get('state');
      const code = url.searchParams.get('code');
      const pending = pendingStates.get(state);
      pendingStates.delete(state);
      if (!state || !code || !pending || pending.expires < Date.now()) {
        return json(response, 400, { error: 'Instagram sign-in was canceled or expired.' });
      }
      const ticket = fresh();
      pendingTickets.set(ticket, { code, expires: Date.now() + ttl });
      return redirect(response, `${callbackScheme}://oauth?ticket=${ticket}&nonce=${pending.nonce}`);
    }
    if (request.method === 'POST' && url.pathname === '/auth/redeem') {
      const { ticket } = await body(request);
      const pending = pendingTickets.get(ticket);
      pendingTickets.delete(ticket);
      if (!pending || pending.expires < Date.now()) {
        return json(response, 400, { error: 'Sign-in ticket expired. Try again.' });
      }
      const token = await exchange(pending.code);
      return json(response, 200, token);
    }
    json(response, 404, { error: 'Not found.' });
  } catch (error) {
    // Never log authorization codes, tokens, or request URLs.
    json(response, 400, { error: error.message || 'Authentication failed.' });
  }
}).listen(port, host, () => {
  console.log(`Instagram auth service listening on ${host}:${port}`);
});
