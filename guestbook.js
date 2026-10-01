const guestbook = document.getElementById('guestbook');
const config = window.GUESTBOOK_CONFIG;
const ready = config && /^https:\/\/[a-z0-9-]+\.supabase\.co\/?$/i.test(config.url)
  && /^(sb_publishable_|eyJ)/.test(config.publishableKey);

if (guestbook && ready) {
  guestbook.hidden = false;
  const navigationLink = document.querySelector('.guestbook-nav');
  if (navigationLink) navigationLink.hidden = false;
  const form = document.getElementById('guestbook-form');
  const nameField = document.getElementById('guestbook-name');
  const messageField = document.getElementById('guestbook-message');
  const trapField = document.getElementById('guestbook-website');
  const status = document.getElementById('guestbook-status');
  const list = document.getElementById('guestbook-list');
  const submit = form.querySelector('button[type="submit"]');
  const endpoint = `${config.url.replace(/\/$/, '')}/rest/v1/guestbook_entries`;
  const headers = { apikey: config.publishableKey };

  async function loadEntries() {
    list.replaceChildren();
    const note = document.createElement('p');
    note.className = 'guestbook-empty';
    note.textContent = '방명록을 불러오는 중입니다.';
    list.append(note);
    try {
      const response = await fetch(`${endpoint}?select=name,message,created_at&order=created_at.desc&limit=12`, { headers });
      if (!response.ok) throw new Error('Guestbook read failed');
      const entries = await response.json();
      list.replaceChildren();
      if (!entries.length) {
        note.textContent = '아직 공개된 방명록이 없습니다.';
        list.append(note);
        return;
      }
      const dateFormat = new Intl.DateTimeFormat('ko-KR', { year: 'numeric', month: 'short', day: 'numeric' });
      entries.forEach(entry => {
        const article = document.createElement('article');
        const header = document.createElement('div');
        const name = document.createElement('strong');
        const date = document.createElement('time');
        const message = document.createElement('p');
        name.textContent = entry.name;
        date.dateTime = entry.created_at;
        date.textContent = dateFormat.format(new Date(entry.created_at));
        message.textContent = entry.message;
        header.append(name, date);
        article.append(header, message);
        list.append(article);
      });
    } catch {
      note.textContent = '방명록을 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.';
      list.replaceChildren(note);
    }
  }

  form.addEventListener('submit', async event => {
    event.preventDefault();
    const name = nameField.value.trim();
    const message = messageField.value.trim();
    if (trapField.value || !name || !message || name.length > 30 || message.length > 500) {
      status.textContent = '이름과 글의 길이를 확인해 주세요.';
      return;
    }
    submit.disabled = true;
    status.textContent = '방명록을 보내는 중입니다.';
    try {
      const response = await fetch(endpoint, {
        method: 'POST',
        headers: { ...headers, 'Content-Type': 'application/json', Prefer: 'return=minimal' },
        body: JSON.stringify({ name, message })
      });
      if (!response.ok) throw new Error('Guestbook write failed');
      form.reset();
      status.textContent = '접수됐습니다. 확인 후 공개됩니다.';
    } catch {
      status.textContent = '저장하지 못했습니다. 잠시 후 다시 시도해 주세요.';
    } finally {
      submit.disabled = false;
    }
  });

  loadEntries();
}
