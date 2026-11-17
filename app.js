// Shared code for every page. Needs config.js and the Supabase library loaded first.
/* global supabase, SUPABASE_URL, SUPABASE_KEY */

const sb = supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
const MONTHS = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

// ---------- Formatting ----------
function esc(s) {
  return String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
function fmtRM(n) {
  const v = Number(n || 0);
  return 'RM ' + v.toLocaleString('en-MY', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}
// '2026-11-16' -> '16 Nov 2026'
function fmtDate(iso) {
  if (!iso) return '';
  const [y, m, d] = String(iso).slice(0, 10).split('-').map(Number);
  return d + ' ' + MONTHS[m - 1] + ' ' + y;
}
// timestamp -> '17 Nov 2026, 8:05 am'
function fmtDateTime(ts) {
  if (!ts) return '';
  const t = new Date(ts);
  let h = t.getHours();
  const ampm = h >= 12 ? 'pm' : 'am';
  h = h % 12 || 12;
  return t.getDate() + ' ' + MONTHS[t.getMonth()] + ' ' + t.getFullYear() + ', ' + h + ':' + String(t.getMinutes()).padStart(2, '0') + ' ' + ampm;
}
function isoOf(dateObj) {
  return dateObj.getFullYear() + '-' + String(dateObj.getMonth() + 1).padStart(2, '0') + '-' + String(dateObj.getDate()).padStart(2, '0');
}
function todayISO() { return isoOf(new Date()); }
function addDays(iso, n) {
  const [y, m, d] = iso.split('-').map(Number);
  return isoOf(new Date(y, m - 1, d + n));
}
function yesterdayISO() { return addDays(todayISO(), -1); }

// ---------- Messages ----------
function friendlyError(err) {
  const m = (err && (err.message || err.error_description || String(err))) || '';
  if (/Invalid login credentials/i.test(m)) return 'Wrong email or password. Please try again.';
  if (/Email not confirmed/i.test(m)) return 'Please confirm your email first. Check your inbox for the link from Supabase.';
  if (/already registered/i.test(m)) return 'This email already has an account. Please sign in instead.';
  if (/Password should be/i.test(m)) return 'Password is too short. Please use at least 6 characters.';
  if (/rate limit/i.test(m)) return 'Too many tries. Please wait a few minutes and try again.';
  if (/Failed to fetch|NetworkError/i.test(m)) return 'Cannot reach the server. Please check your internet and try again.';
  if (/row-level security|permission denied/i.test(m)) return 'You are not allowed to do this.';
  if (/JWT|session/i.test(m)) return 'Your sign-in has expired. Please sign in again.';
  // Messages we wrote ourselves in the database are already friendly.
  return m || 'Something went wrong. Please try again.';
}
function showMsg(el, text, type) {
  if (!el) return;
  if (!text) { el.innerHTML = ''; return; }
  el.innerHTML = '<div class="msg ' + (type || 'info') + '">' + esc(text) + '</div>';
}

// ---------- Sign-in and role check ----------
let CURRENT = null; // { user, profile }

async function getProfile() {
  const { data: { session } } = await sb.auth.getSession();
  if (!session) return null;
  const { data, error } = await sb.from('profiles').select('*').eq('id', session.user.id).maybeSingle();
  if (error) throw error;
  return { user: session.user, profile: data };
}

// Call at the top of every page. Sends people who are not allowed back to index.html.
// (The real protection is Row Level Security in the database.)
async function requirePage(allowedRoles, activeNav) {
  let me = null;
  try { me = await getProfile(); } catch (e) { me = null; }
  if (!me || !me.profile || !me.profile.active || !allowedRoles.includes(me.profile.role)) {
    const denied = me && me.profile && me.profile.active ? '?denied=1' : '';
    window.location.replace('index.html' + denied);
    throw new Error('redirecting');
  }
  CURRENT = me;
  renderTopbar(activeNav);
  return me.profile;
}

function renderTopbar(activeNav) {
  const p = CURRENT.profile;
  const links = [
    { href: 'dashboard.html', label: 'Dashboard', roles: ['owner', 'manager', 'staff'] },
    { href: 'upload.html', label: 'Upload file', roles: ['owner', 'manager'] },
    { href: 'history.html', label: 'History', roles: ['owner', 'manager'] },
    { href: 'settings.html', label: 'Settings', roles: ['owner'] },
  ].filter(l => l.roles.includes(p.role));
  const roleName = { owner: 'Owner', manager: 'Manager', staff: 'Staff' }[p.role];
  const bar = document.createElement('header');
  bar.className = 'topbar';
  bar.innerHTML =
    '<div class="brand">Metatronik Sales</div>' +
    '<nav>' + links.map(l => '<a href="' + l.href + '"' + (l.href === activeNav ? ' class="active"' : '') + '>' + l.label + '</a>').join('') + '</nav>' +
    '<div class="who"><span>' + esc(p.full_name || p.email) + ' · ' + roleName + '</span>' +
    '<button class="secondary small" id="signOutBtn">Sign out</button></div>';
  document.body.prepend(bar);
  document.getElementById('signOutBtn').onclick = signOut;
}

async function signOut() {
  await sb.auth.signOut();
  window.location.replace('index.html');
}

// ---------- Settings ----------
async function getSettings() {
  const { data, error } = await sb.from('settings').select('key,value');
  if (error) throw error;
  const s = {};
  (data || []).forEach(r => { s[r.key] = r.value; });
  return {
    upload_deadline: s.upload_deadline || '08:00',
    owner_whatsapp: s.owner_whatsapp || '',
    chart_days: Math.min(60, Math.max(7, parseInt(s.chart_days, 10) || 14)),
  };
}

// Has the deadline time (e.g. '08:00') passed today?
function deadlinePassed(deadline) {
  const [h, m] = String(deadline || '08:00').split(':').map(Number);
  const now = new Date();
  return now.getHours() * 60 + now.getMinutes() >= (h || 0) * 60 + (m || 0);
}
function fmtTime(hhmm) {
  const [h, m] = String(hhmm || '08:00').split(':').map(Number);
  return ((h % 12) || 12) + ':' + String(m || 0).padStart(2, '0') + ' ' + (h >= 12 ? 'pm' : 'am');
}

// WhatsApp link with the message already typed. A person presses send.
function whatsappLink(number, text) {
  const digits = String(number || '').replace(/\D/g, '');
  return 'https://wa.me/' + digits + '?text=' + encodeURIComponent(text);
}
