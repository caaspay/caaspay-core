#!/usr/bin/env perl
use strict;
use warnings;

use IO::Async::Loop;
use Future::AsyncAwait;
use Syntax::Keyword::Try;
use Net::Async::Redis;

use Socket qw(unpack_sockaddr_in inet_ntoa);
use Log::Any qw($log);
use Log::Any::Adapter qw(Stdout), log_level => 'info';
use IO::Async::Resolver;

my $loop = IO::Async::Loop->new;

my $idx = 0;
my @ip;
while($idx < 6) {
    try {
        my (@addr) = await $loop->resolver->getaddrinfo(
            host    => "support-redis-main-$idx",
            service => "6379",
            protocol => 6,
        ) or last;
        for my $addr (@addr) {
            my $ip = inet_ntoa(''. unpack_sockaddr_in($addr->{addr}));
            $log->infof('Have Redis node at %s - %s', $ip, $addr);
            push @ip, $ip;
        }
        ++$idx;
    } catch($e) {
        last if $e =~ /Name or service not known/i;
        die 'Unexpected error in lookup - ' . $e;
    }
}

$log->infof('Have a total of %d Redis nodes', 0 + @ip);

for my $node (@ip) {
    try {
        $loop->add(
            my $redis = Net::Async::Redis->new(
                host => $node,
            )
        );
        await $redis->connect;
        # We'll expect this to return ERR if we provide an invalid node,
        # although it may not immediately fail if the node exists and
        # was not originally part of the cluster
        for my $target (@ip) {
            await $redis->cluster_meet($target => 6379);
        }
    } catch($e) {
        $log->errorf('Failed to join %s to the cluster: %s', $node, $e);
    }
}

$log->infof('All nodes have now joined.');
