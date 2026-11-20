/* Terminal v15.1: PIN kutusu pencerenin icinde (iPhone ana ekran uygulamasi prompt gostermiyor) */
(function(){
  const sheet = document.querySelector('#mTerm .sheet'), row = document.querySelector('#mTerm .trow');
  const pr = document.createElement('div'); pr.className = 'trow'; pr.id = 'tPinRow'; pr.style.display = 'none';
  pr.innerHTML = '<input type="password" id="tPinIn" placeholder="Terminal PIN" autocomplete="off" autocapitalize="off" autocorrect="off" spellcheck="false"><button class="pri" id="tPinSave">PIN kaydet</button>';
  sheet.insertBefore(pr, row);
})();
function pinGet(){ try{ return localStorage.getItem(PINK) || ''; }catch(e){ return window.__pin || ''; } }
function pinSet(v){ window.__pin = v; try{ if (v) localStorage.setItem(PINK, v); else localStorage.removeItem(PINK); }catch(e){} }
function showPinRow(){ $('tPinRow').style.display = ''; $('tPinIn').value = ''; setTimeout(() => $('tPinIn').focus(), 50); }
window.getPin = function(force){ if (force){ showPinRow(); return null; } return pinGet() || null; };
window.tRun = async function(text){
  text = (text || '').trim();
  if (!tDev) return;
  if (!text){ tLine('Komut kutusu boş.', 'd'); return; }
  if (tBusy){ tLine('Önceki komutun cevabı bekleniyor…', 'd'); return; }
  const pin = pinGet();
  if (!pin){ showPinRow(); tLine('Önce PIN\'i aşağıya yazıp "PIN kaydet"e bas, sonra tekrar Çalıştır.', 'e'); return; }
  if (!window.crypto || !crypto.subtle){ tLine('Bu tarayıcı imza işlemini desteklemiyor (crypto.subtle yok).', 'e'); return; }
  tBusy = true; $('tRun').disabled = true;
  tHist.unshift(text); tHi = -1; $('tIn').value = '';
  tLine('> ' + text, 'c');
  try{
    const n = rid() + rid(), ts = Date.now(), r = rid();
    const sig = await sign(pin, tDev, `${n}|${ts}|${text}`);
    await cmd(tDev, {t:'sh', cmd: text, ts, n, sig, rid: r});
    tLine('gönderildi, cevap bekleniyor…', 'd');
    const res = await waitRes(tDev, r, 80);
    const o = $('tOut'); if (o.lastChild && o.lastChild.textContent === 'gönderildi, cevap bekleniyor…\n') o.lastChild.remove();
    if (!res) tLine('Yanıt yok (laptop uykuda ya da komut çok uzun sürdü).', 'e');
    else if (res.err){ tLine(res.err, 'e'); if (/PIN/.test(res.err)){ pinSet(''); showPinRow(); } }
    else { if (res.out) tLine(res.out); if (res.cwd) tLine(res.cwd + (res.code ? '  (kod ' + res.code + ')' : ''), 'd'); }
  }catch(e){ tLine('Hata: ' + (e && e.message || e), 'e'); }
  tBusy = false; $('tRun').disabled = false;
};
$('tPin').onclick = showPinRow;
$('tPinSave').onclick = () => {
  const v = $('tPinIn').value.trim(); if (!v){ tLine('PIN boş olamaz.', 'e'); return; }
  pinSet(v); $('tPinRow').style.display = 'none'; tLine('PIN kaydedildi.', 'd');
  if ($('tIn').value.trim()) tRun($('tIn').value);
};
$('tPinIn').addEventListener('keydown', e => { if (e.key === 'Enter'){ e.preventDefault(); $('tPinSave').click(); } });
const _openTerm = window.openTerm;
window.openTerm = function(id){ _openTerm(id); if (!pinGet() && (infoData[id] || {}).sh) showPinRow(); };
