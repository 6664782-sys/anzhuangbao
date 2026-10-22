<?php
try {
    require '/www/wwwroot/nailu.pro/vendor/autoload.php';
    $app = require '/www/wwwroot/nailu.pro/bootstrap/app.php';
    $app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
    $user = App\Models\User::where('is_admin', 1)->where('banned', 0)->firstOrFail();
    $service = new App\Services\AuthService($user);
    $issued = [];
    function callApi($path, $body = null, $token = null) {
        $ch = curl_init('https://nailu.pro/api/v1/'.$path);
        $headers=['Accept: application/json','Content-Type: application/json'];
        if ($token) $headers[]='Authorization: '.$token;
        curl_setopt_array($ch,[CURLOPT_RETURNTRANSFER=>true,CURLOPT_TIMEOUT=>15,CURLOPT_RESOLVE=>['nailu.pro:443:127.0.0.1'],CURLOPT_HTTPHEADER=>$headers]);
        if ($body!==null) { curl_setopt($ch,CURLOPT_POST,true); curl_setopt($ch,CURLOPT_POSTFIELDS,json_encode($body)); }
        $result=curl_exec($ch); $status=curl_getinfo($ch,CURLINFO_HTTP_CODE);
        if ($result===false) throw new RuntimeException('HTTP transport failed');
        curl_close($ch);
        return [$status,json_decode($result,true)];
    }
    function check($condition,$message) { if (!$condition) throw new RuntimeException($message); }
    try {
        $web=$service->generateAuthData(Illuminate\Http\Request::create('/nailu-client-smoke','POST'))['auth_data'];
        $issued[]=$web;
        [$status,$r]=callApi('guest/nailu/client/start',['platform'=>'windows','client_id'=>bin2hex(random_bytes(32))]);
        check($status===200,'Start failed'); $device=$r['data'];
        [$status,$r]=callApi('guest/nailu/client/poll',['device_code'=>$device['device_code']]);
        check($status===200&&$r['data']['status']==='pending','Unapproved must remain pending');
        [$status,$r]=callApi('user/nailu/client/details?user_code='.$device['user_code']);
        check($status===403,'Unauthenticated confirmation not blocked');
        [$status,$r]=callApi('user/nailu/client/approve',['user_code'=>$device['user_code']],$web);
        check($status===200,'Authenticated approval failed');
        sleep(5);
        [$status,$r]=callApi('guest/nailu/client/poll',['device_code'=>$device['device_code']]);
        check($status===200&&$r['data']['status']==='approved','Authorized polling failed');
        $native=$r['data']['auth_data']; $issued[]=$native;
        [$status,$r]=callApi('user/getSubscribe',null,$native);
        check($status===200&&isset($r['data']['subscribe_url']),'Subscription unavailable');
        [$status,$r]=callApi('guest/nailu/client/poll',['device_code'=>$device['device_code']]);
        check($status===410,'Device secret replay not blocked');
        echo "NAILU_HTTP_AUTH_SUBSCRIPTION_PASSED\n";
    } finally {
        foreach($issued as $token) {
            $parts=explode('.',$token);
            $data=json_decode(base64_decode(strtr($parts[1],'-_','+/')),true);
            $service->removeSession($data['session']);
            Illuminate\Support\Facades\Cache::forget($token);
        }
    }
} catch (Throwable $e) {
    fwrite(STDERR,get_class($e).': '.$e->getMessage()."\n");
    exit(1);
}
