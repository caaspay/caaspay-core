package CodeNSmoke::Service::SpotifyGrinder::Home;

use Myriad::Service;
use Myriad::Util::UUID;
use Net::Async::Spotify;
use URI;

has $spotify;
has $redis;

async method startup() {
    my $redis_uri = URI->new($ENV{'MYRIAD_TRANSPORT_REDIS'});
    $self->add_child(
        $redis = Net::Async::Redis::Cluster->new()
    );
    await $redis->bootstrap(
        host => $redis_uri->host,
        port => $redis_uri->port
    );
    $self->add_child(
        $spotify = Net::Async::Spotify->new(
            client_id => $ENV{client_id},
	    client_secret => $ENV{client_secret},
            redirect_uri => URI->new('https://app.spotify-grinder.com/home/callback'),
	)
    );
    $log->infof('all good %s | %s', $spotify->client_id, $ENV{client_id});
}

async method authorize() {
    my %authorize = $spotify->authorize(scope => ['scopes'], show_dialog => 'false');
    my $uuid = Myriad::Util::UUID::uuid();
    await $redis->hset($uuid, 'state', $authorize{state});
    await $redis->expire($uuid, 300);
    return {session => { id => $uuid, set => 1 }, template => {login => {uri => encode_utf8($authorize{uri})}}};
}

async method request : RPC (%args) {
    try {
    my $r = await $self->authorize;
    $log->warnf('HHH %s', $r);
return $r;
} catch ($e) {
$log->warnf('Err: %s', $e);
}
}

async method callback : RPC (%args) {
    $log->warnf('CALLBACK %s', \%args);
    return { args => \%args ,success =>1 };
}

async method test_m : RPC (%args) {
	#my $count = await $redis->keys("*");
	my $count = await $redis->hgetall("aa3f5db5-e7d5-44ca-bc5d-e3fc9196a5ef");
    $log->warnf('fff %s | %s', \%args, $count);
    return {args => \%args, c => $count};

}

1;
