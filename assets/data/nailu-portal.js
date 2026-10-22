(() => {
  if (location.origin !== 'https://nailu.pro' || new URLSearchParams(location.search).get('nailu_client') !== '1') return;
  let state = null;
  const send = value => {
    state = value;
    if (window.flutter_inappwebview?.callHandler) window.flutter_inappwebview.callHandler('nailuPortal', value);
  };
  window.addEventListener('flutterInAppWebViewPlatformReady', () => { if (state) send(state); });
  const params = new URLSearchParams(location.hash.split('?')[1] || '');
  const verify = params.get('verify');
  if (verify) {
    const routes = new Set(['plans','orders','profile','tickets','notices','invite','gift','help','devices','traffic','nodes','diagnostics']);
    const route = params.get('redirect') || 'plans';
    if (!/^(?:[a-f0-9]{32}|[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12})$/i.test(verify) || !routes.has(route)) { send('error'); return; }
    fetch('/api/v1/passport/auth/token2Login?verify=' + encodeURIComponent(verify), {
      headers: {Accept: 'application/json'}, cache: 'no-store', credentials: 'same-origin'
    }).then(async response => {
      if (!response.ok) throw new Error('Login rejected');
      const data = (await response.json()).data;
      if (!data || typeof data.auth_data !== 'string' || !data.auth_data) throw new Error('Invalid response');
      localStorage.removeItem('nailu_auth');
      sessionStorage.setItem('nailu_auth', data.auth_data);
      location.replace('/?nailu_client=1#/' + route);
    }).catch(() => send('error'));
    return;
  }
  const ready = () => {
    const style = document.createElement('style');
    style.textContent = '.sidebar,.topbar{display:none!important}.main{margin-left:0!important;padding-top:20px!important;min-height:100vh!important}body{padding-left:0!important}.modal{max-height:92vh!important}';
    document.head.append(style);
    send('ready');
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', ready, {once:true});
  else ready();
})();
