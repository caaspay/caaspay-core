package CodeNSmoke::Service::SpotifyGrinder::API;

use Myriad::Service;
use CodeNSmoke::Server::REST;


has $ryu;
has $http_server;
has $routes;
has $redis;

async method diagnostics ($level) {
    return 'ok';
}

async method startup {
    my $redis_uri = URI->new($ENV{'MYRIAD_TRANSPORT_REDIS'});
    $self->add_child(
        $redis = Net::Async::Redis::Cluster->new()
    );
    await $redis->bootstrap(
        host => $redis_uri->host,
        port => $redis_uri->port
    );
    $self->add_child(
        $ryu = Ryu::Async->new()
    );
    $self->add_child(
        $http_server = CodeNSmoke::Server::REST->new(listen_port => 80, redis => $redis)
    );
    $routes = {
        api => { health => {auth => 0} },
        home => { request => {auth => 0}, login => {auth => 0}, callback => {auth => 0}, logout => {auth => 1}, test_m => {auth => 0}  },
    };
    my $sink = $ryu->sink(label => "http_requests_sink");
    $sink->source->map(
        $self->$curry::weak(async method ($incoming_req) {
            my $req = delete $incoming_req->{request};
            $log->debugf('Incoming request to http_requests_sink | %s', $incoming_req);
            try {
                my $service_response = await $self->request_service($incoming_req);
                if ( exists $service_response->{error} ) {
                    $http_server->reply_fail($req, $service_response->{error});
                } else {
		    my $session = delete $service_response->{session};
                    $http_server->reply_success($req, $service_response, $session);
                }
            } catch ($e) {
                $log->warnf('Outgoing failed reply to HTTP request %s', $e);
                $http_server->reply_fail($req, $e);
            }
        }
    ))->resolve->completed;

    await $http_server->start($sink);
}

async method request_service ($incoming_req) {
    # In fact hash can be passed as it is, however it is kept for clarity.
    my ($service, $method, $param, $args, $type, $session) = @$incoming_req{qw(service method params body type session)};
    my $service_to_call = $api->service_by_name("codensmoke.service.spotifygrinder.$service");
    my $response;
    unless ( exists $routes->{$service}{$method} ) {
        $response = { error => { error_text => 'Not Found', error_code => 404}};
	return $response
    }
    if ( $routes->{$service}{$method}{auth} and !defined $session ) {
        $response = { error => { error_text => 'Need Login', error_code => 302}};
	return $response
    }
    try {
        $response = await $service_to_call->call_rpc($method, timeout => 10, param => $param, args => $args, type => $type, session => $session);
    } catch ($e) {
        $log->warnf('Error getting response %s', $e);
        $response = { error => { error_text => 'Could not get response'} };
    }
    return $response;
}

async method health : RPC (%args) {
    # In here we can check on all services health
    # and report which specific API calls health checks.

    $log->infof('Message received to health: %s', \%args);

    return { api_health => 'up', services_health => {'user' => 'up'} };
}

1;
