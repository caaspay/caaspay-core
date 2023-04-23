package Service::Control::Authentication::Login;

use Myriad::Service;


async method startup() {
    $log->warnf('Started');
}

async method test_rpc : RPC (%args) {
    $log->warnf('Method TEST_RPC: %s', \%args);
    return { success => 1 };
}

1;
