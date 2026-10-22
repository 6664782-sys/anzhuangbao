<?php
namespace App\Http\Routes\V1;

use Illuminate\Contracts\Routing\Registrar;

class NailuClientRoute
{
    public function map(Registrar $router)
    {
        $router->group(['prefix' => 'guest/nailu/client'], function ($router) {
            $router->post('/start', 'V1\\NailuClientController@start');
            $router->post('/poll', 'V1\\NailuClientController@poll');
        });
        $router->group(['prefix' => 'user/nailu/client', 'middleware' => 'user'], function ($router) {
            $router->get('/details', 'V1\\NailuClientController@details');
            $router->post('/approve', 'V1\\NailuClientController@approve');
        });
    }
}
