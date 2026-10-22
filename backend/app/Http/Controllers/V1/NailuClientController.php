<?php
namespace App\Http\Controllers\V1;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Services\AuthService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;

class NailuClientController extends Controller
{
    private const TTL = 600;

    private function response(array $data)
    {
        return response()->json(['data' => $data])->header('Cache-Control', 'no-store, private');
    }

    public function start(Request $request)
    {
        $input = $request->validate([
            'platform' => 'required|in:android,windows,macos',
            'client_id' => 'required|regex:/\A[a-f0-9]{64}\z/'
        ]);
        $key = 'nailu:device:client:' . hash('sha256', $input['client_id']);
        return Cache::lock($key . ':lock', 10)->block(3, function () use ($key, $input) {
            if (Cache::has($key)) abort(429, '请稍后重新发起授权');
            $device = bin2hex(random_bytes(32));
            $code = strtoupper(bin2hex(random_bytes(6)));
            $code = implode('-', str_split($code, 4));
            $hash = hash('sha256', $device);
            $expires = time() + self::TTL;
            Cache::put('nailu:device:' . $hash, [
                'platform' => $input['platform'], 'user_code' => $code,
                'expires_at' => $expires, 'status' => 'pending', 'last_poll' => 0
            ], self::TTL);
            Cache::put('nailu:device:code:' . $code, $hash, self::TTL);
            Cache::put($key, true, 10);
            return $this->response([
                'device_code' => $device, 'user_code' => $code,
                'verification_uri' => 'https://nailu.pro/#/client-auth?user_code=' . $code,
                'expires_in' => self::TTL, 'interval' => 5
            ]);
        });
    }

    private function publicCode(Request $request): string
    {
        $input = $request->validate(['user_code' => 'required|regex:/\A[A-F0-9]{4}-[A-F0-9]{4}-[A-F0-9]{4}\z/']);
        $hash = Cache::get('nailu:device:code:' . $input['user_code']);
        if (!is_string($hash)) abort(410, '授权已过期或已使用，请在客户端重新登录');
        return $hash;
    }

    private function pending(string $hash): array
    {
        $data = Cache::get('nailu:device:' . $hash);
        if (!is_array($data) || $data['expires_at'] <= time() || $data['status'] === 'consumed') {
            abort(410, '授权已过期或已使用，请在客户端重新登录');
        }
        return $data;
    }

    public function details(Request $request)
    {
        $data = $this->pending($this->publicCode($request));
        return $this->response(array_intersect_key($data, array_flip(['platform', 'user_code', 'expires_at', 'status'])));
    }

    public function approve(Request $request)
    {
        $hash = $this->publicCode($request);
        return Cache::lock('nailu:device:lock:' . $hash, 10)->block(3, function () use ($hash, $request) {
            $data = $this->pending($hash);
            if ($data['status'] !== 'pending') abort(409, '授权已确认');
            $user = User::find((int) $request->input('user.id'));
            if (!$user || $user->banned) abort(403, '账户无法授权');
            $data['status'] = 'approved';
            $data['user_id'] = $user->id;
            Cache::put('nailu:device:' . $hash, $data, max(1, $data['expires_at'] - time()));
            return $this->response(['status' => 'approved']);
        });
    }

    protected function issueSession(int $userId, Request $request): string
    {
        $user = User::find($userId);
        if (!$user || $user->banned) abort(403, '账户无法授权');
        return (new AuthService($user))->generateAuthData($request)['auth_data'];
    }

    public function poll(Request $request)
    {
        $input = $request->validate(['device_code' => 'required|regex:/\A[a-f0-9]{64}\z/']);
        $hash = hash('sha256', $input['device_code']);
        return Cache::lock('nailu:device:lock:' . $hash, 10)->block(3, function () use ($hash, $request) {
            $data = $this->pending($hash);
            if (time() - $data['last_poll'] < 4) abort(429, '请按间隔轮询授权');
            $data['last_poll'] = time();
            if ($data['status'] === 'approved') {
                $token = $this->issueSession($data['user_id'], $request);
                $data['status'] = 'consumed';
                unset($data['user_id']);
                Cache::put('nailu:device:' . $hash, $data, max(1, $data['expires_at'] - time()));
                Cache::forget('nailu:device:code:' . $data['user_code']);
                return $this->response(['status' => 'approved', 'auth_data' => $token]);
            }
            Cache::put('nailu:device:' . $hash, $data, max(1, $data['expires_at'] - time()));
            return $this->response(['status' => 'pending']);
        });
    }
}
