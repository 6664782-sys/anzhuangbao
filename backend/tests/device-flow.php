<?php
try {
    require '/www/wwwroot/nailu.pro/vendor/autoload.php';
    $app = require '/www/wwwroot/nailu.pro/bootstrap/app.php';
    $app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
    require $argv[1];
    config(['cache.default' => 'array']);
    class TestNailuClientController extends App\Http\Controllers\V1\NailuClientController {
        protected function issueSession(int $userId, Illuminate\Http\Request $request): string { return 'test-session-not-a-real-token'; }
    }
    function expectTrue($value, $message) { if (!$value) throw new RuntimeException($message); }
    function req($data) { return Illuminate\Http\Request::create('/', 'POST', $data); }
    function expectStatus($status, $action) {
        try { $action(); throw new RuntimeException('Expected rejection: '.$status); }
        catch (Symfony\Component\HttpKernel\Exception\HttpException $e) { expectTrue($e->getStatusCode()===$status, 'Wrong rejection'); }
    }
    $c = new TestNailuClientController;
    $client = ['platform'=>'windows', 'client_id'=>str_repeat('a',64)];
    $start = $c->start(req($client))->getData(true)['data'];
    expectTrue(strlen($start['device_code'])===64, 'Missing device secret');
    expectTrue(strpos($start['verification_uri'], $start['device_code'])===false, 'Secret in URL');
    expectStatus(429, fn()=>$c->start(req($client)));
    $poll = ['device_code'=>$start['device_code']];
    expectTrue($c->poll(req($poll))->getData(true)['data']['status']==='pending', 'Must require explicit approval');
    expectStatus(429, fn()=>$c->poll(req($poll)));
    $details=$c->details(req(['user_code'=>$start['user_code']]))->getData(true)['data'];
    expectTrue(!isset($details['device_code'])&&!isset($details['auth_data'])&&!isset($details['user_id']), 'Private data exposed');
    $hash=hash('sha256',$start['device_code']);
    $key='nailu:device:'.$hash;
    $data=Illuminate\Support\Facades\Cache::get($key);
    $data['status']='approved'; $data['user_id']=1; $data['last_poll']=0;
    Illuminate\Support\Facades\Cache::put($key,$data,600);
    $result=$c->poll(req($poll))->getData(true)['data'];
    expectTrue($result['auth_data']==='test-session-not-a-real-token', 'Approved session missing');
    expectTrue(!isset($result['token'])&&!isset($result['is_admin']), 'Account secrets exposed');
    expectStatus(410,fn()=>$c->poll(req($poll)));
    expectStatus(410,fn()=>$c->details(req(['user_code'=>$start['user_code']])));
    $data['expires_at']=time()-1; $data['status']='pending';
    Illuminate\Support\Facades\Cache::put($key,$data,600);
    expectStatus(410,fn()=>$c->poll(req($poll)));
    echo "NAILU_DEVICE_FLOW_TESTS_PASSED\n";
} catch (Throwable $e) {
    fwrite(STDERR, get_class($e).': '.$e->getMessage()."\n");
    exit(1);
}
