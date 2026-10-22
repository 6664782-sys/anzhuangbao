const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(require('node:path').resolve(__dirname, '../../assets/data/nailu-portal.js'), 'utf8');
async function check(origin, route, verify = '0'.repeat(32)) {
  const calls = [], messages = [], saved = new Map(), redirects = [];
  const context = {
    URLSearchParams, Set,
    location: {origin, search:'?nailu_client=1', hash:'#/login?verify='+verify+'&redirect='+route,
      replace: value => redirects.push(value)},
    window: {addEventListener(){}, flutter_inappwebview: {callHandler: (_, value) => messages.push(value)}},
    localStorage: {removeItem: value => saved.delete(value)},
    sessionStorage: {setItem: (key,value) => saved.set(key,value)},
    fetch: async url => { calls.push(url); return {ok:true,json:async()=>({data:{auth_data:'portal-session'}})}; },
    document: {readyState:'loading',addEventListener(){}},
  };
  vm.runInNewContext(source, context);
  await new Promise(resolve => setImmediate(resolve));
  return {calls,messages,saved,redirects};
}
(async () => {
  const valid = await check('https://nailu.pro','plans');
  assert.equal(valid.calls.length,1);
  assert.equal(valid.saved.get('nailu_auth'),'portal-session');
  assert.deepEqual(valid.redirects,['/?nailu_client=1#/plans']);
  assert.deepEqual(valid.messages,[]);
  assert.equal((await check('https://nailu.pro','plans','00000000-0000-0000-0000-000000000001')).calls.length,1);
  const unsafe = await check('https://nailu.pro','https://attacker.example');
  assert.deepEqual(unsafe.calls,[]);
  assert.deepEqual(unsafe.messages,['error']);
  const foreign = await check('https://attacker.example','plans');
  assert.deepEqual(foreign.calls,[]);
  assert.equal(foreign.saved.size,0);
  console.log('NaiLu portal script checks passed');
})().catch(error => { console.error(error); process.exitCode=1; });
