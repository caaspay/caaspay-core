package Control::Authentication::Login;

use Myriad::Service;


async method startup() {
    my $s = $api->service_by_name('test.service');
    try {
#        await $s->call_rpc('request', test_arg1 => 'ffff', test_arg2 => 'gggg');
    } catch ($err) {
        $log->warnf('RRR %s', $err);
    }
    $log->warnf('Started');
}

async method login : RPC (%args) {
    $log->warnf('Method TEST_RPC: %s', \%args);
    return { success => 1, name => \%args };
}


async method test: Batch()(){
    await $self->loop->delay_future(after => 60);
    my $s = $api->service_by_name('control.authentication.login');
    try {
        my $f = await $s->call_rpc('login', name => 'TTT', age => 4);
        $log->warnf('FFFFF %s', $f);
    } catch ($err) {
    }
    return [];
}

1;
