<?php
if (PHP_SAPI !== 'cli') { http_response_code(404); exit; }
require '/www/wwwroot/nailu.pro/vendor/autoload.php';
$app = require '/www/wwwroot/nailu.pro/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
$user = App\Models\User::where('is_admin', 1)->where('banned', 0)->firstOrFail();
$service = new App\Services\AuthService($user);
$issued = [];
function portalCheck($condition, $message) { if (!$condition) throw new RuntimeException($message); }
function portalCall($path, $body = null, $token = null) {
    $ch = curl_init('https://nailu.pro/api/v1/' . $path);
    $headers = ['Accept: application/json', 'Content-Type: application/json'];
    if ($token) $headers[] = 'Authorization: ' . $token;
    curl_setopt_array($ch, [CURLOPT_RETURNTRANSFER=>true, CURLOPT_TIMEOUT=>20,
        CURLOPT_RESOLVE=>['nailu.pro:443:127.0.0.1'], CURLOPT_HTTPHEADER=>$headers]);
    if ($body !== null) { curl_setopt($ch, CURLOPT_POST, true); curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($body)); }
    $raw = curl_exec($ch); $status = curl_getinfo($ch, CURLINFO_HTTP_CODE); curl_close($ch);
    if ($raw === false) throw new RuntimeException('Transport failed');
    return [$status, json_decode($raw, true)];
}
try {
    [$status] = portalCall('user/getQuickLoginUrl', ['redirect'=>'plans']);
    portalCheck($status === 403, 'Anonymous portal session was not rejected');
    $native = $service->generateAuthData(Illuminate\Http\Request::create('/nailu-portal-smoke', 'POST'))['auth_data'];
    $issued[] = $native;
    [$status, $result] = portalCall('user/getQuickLoginUrl', ['redirect'=>'plans'], $native);
    portalCheck($status === 200 && is_string($result['data']), 'Portal URL failed');
    $uri = parse_url($result['data']);
    portalCheck($uri['scheme'] === 'https' && $uri['host'] === 'nailu.pro', 'Wrong portal origin');
    parse_str(explode('?', $uri['fragment'], 2)[1], $params);
    portalCheck($params['redirect'] === 'plans' && !empty($params['verify']), 'Missing portal verification');
    [$status, $result] = portalCall('passport/auth/token2Login?verify=' . rawurlencode($params['verify']));
    portalCheck($status === 200 && is_string($result['data']['auth_data']), 'Portal exchange failed');
    $web = $result['data']['auth_data']; $issued[] = $web;
    [$status] = portalCall('passport/auth/token2Login?verify=' . rawurlencode($params['verify']));
    portalCheck($status !== 200, 'One-time portal token replayed');
    foreach (['user/plan/fetch', 'user/order/fetch', 'user/order/getPaymentMethod'] as $path) {
        [$status, $result] = portalCall($path, null, $web);
        portalCheck($status === 200 && is_array($result['data']), 'Portal service failed: ' . $path);
    }
    echo "NAILU_PORTAL_PLANS_ORDERS_PAYMENT_METHODS_PASSED\n";
} catch (Throwable $error) {
    fwrite(STDERR, get_class($error) . ': ' . $error->getMessage() . "\n");
    $failed = true;
} finally {
    foreach ($issued as $token) {
        $parts = explode('.', $token);
        $payload = json_decode(base64_decode(strtr($parts[1], '-_', '+/')), true);
        $service->removeSession($payload['session']);
        Illuminate\Support\Facades\Cache::forget($token);
    }
}
exit(empty($failed) ? 0 : 1);
