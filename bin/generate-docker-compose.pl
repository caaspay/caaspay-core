#!/usr/bin/env perl 
use strict;
use warnings;

=pod

Populates the C<docker-compose.yml> file with services from the C<service/> directory,
expecting them to be defined as C<type/system/service_name> with an optional C<config.yml>
configuration defining:

=over 4

=item * C<instances> - key-value set of instance names and any specific overrides

=back

=cut

use Template;
use Path::Tiny qw(cwd path);
use YAML::XS qw(LoadFile);
use Storable qw(dclone);
use List::MoreUtils qw(uniq indexes);
use Getopt::Long qw(GetOptions);
use Dotenv;
use Syntax::Keyword::Try;
use Log::Any qw($log);
use Hash::Merge;
use Text::Diff;
use Data::Dumper;

STDOUT->autoflush(1);

GetOptions(
    'e|environment=s'      => \( my $env = 'development' ),
    'c|credentials-type=s' => \( my $credentials_type = 'file' ),
    'd|credentials-dir=s'  => \( my $credentials_dir = 'container_files'),
    'v|env-dir=s'          => \( my $environmet_dir = 'container_envs'),
    'b|base-dir=s'         => \( my $base_dir = cwd),
    's|service=s@'         => \( my $services = [] ),
    't|service-type=s@'    => \( my $service_types = [] ),
    'y|service-system=s@'  => \( my $service_systems = [] ),
    'x|exclude=s@'         => \( my $excluded_services = [] ),
    'u|update-flag=s'      => \( my $update_flag = 'docker.restart_required' ),
    'l|log-level=s'        => \( my $log_level = 'info' ),
    'h|help'               => \my $help,
);

require Log::Any::Adapter;
Log::Any::Adapter->set( qw(Stdout), log_level => $log_level );


die <<"EOF" if ($help);
usage: $0 OPTIONS
These options are available:
  -e, --environment          for which type you are generating for. | production | (development) |
  -c, --credentials-type     where to load credentials from. | (file) | valut |
  -d, --credentials-dir      where to write credential files for containers. |(credentials)|
  -v, --env-dir              where to write containers .env files. |(container_envs)|
  -b, --base-dir             base directory of repository. | (current execution directory) |
  -s, --service              list of services intended to include.
  -t, --service-type         list of services types to include.
  -y, --service-system       list of services systems to include.
  -x, --exclude              list of services to exclude.
  -u, --update-flag          A flag file to be created by script indicating if a change happened on generated file.
  -l, --log-level            log level set for script.
  -h, --help                 Show this message.
EOF

my $merger = Hash::Merge->new('RIGHT_PRECEDENT');
my $support_helper_prefix = 'support_helper';
my $base_helper_prefix = 'base_helper';

# Allow both formats to list of service.
# comma separated list, or pass through multi option
$services = [ uniq map {split ',', $_ } @$services ];
$service_types = [ uniq map {split ',', $_ } @$service_types ];
$service_systems = [ uniq map {split ',', $_ } @$service_systems ];
$excluded_services = [ uniq map {split ',', $_} @$excluded_services ];

$log->infof('Services: %s', $services);
$log->infof('Services Types: %s', $service_types);
$log->infof('Services Systems: %s', $service_systems);
$log->infof('Excluded Services: %s', $excluded_services);

# Add environment to the to be used directories
$credentials_dir .= "_$env";
$environmet_dir .= "_$env";

# Used by script
my $empty_deployment_config = {
    helper => {},
    instance => {},
    setting => {},
    infra_config => {},
    service_config => {},
};
# Used by script and template
my $empty_service_config = {
    environment => {},
    volume => {},
    network  => [],
    docker_deployment => {},
    port => [],
    command => [],
    custom => {},
};

my $empty_credentials = {
    environment => {},
    file => [],
};

my $credentials = {};
my @all_services;
my $templates_var = {};
my $all_volumes = {};
my $all_networks = {};
my $updated_services = {};


=head1 METHODS

=head2 generate

kickstart generation process
Going over entire service directory
gettig config for all services
filter the needed ones
generate deployment configuration for services
generate docker compose deployment

=cut

sub generate {

    my $service_dir = path(join '/', $base_dir, 'service');
    $templates_var->{docker_compose} = [];

    my $config = {};
    my $key = handle_config($service_dir, $config);

    # It will populate @all_services var
    # [ {key => $key, dir => $service}, ... ]
    get_config({
            types => [grep { $_->is_dir } $service_dir->children],
            config => $config,
            key =>$key
        });

    # filter @all_services based on options passed
    filter();

    $log->debugf('Services: %s | Config: %s | Credentials: %s', Dumper(\@all_services), Dumper($config), Dumper($credentials));
    # It will populate $templates_var->{docker_compose}
    generate_services_config($config);

    # based on $templates_var->{docker_compose}
    generate_docker_compose();
}

=head2 handle_config

handle config.yaml file and credentials.yaml in directory
with all its different formats. both .yml and .yaml extension
also will parse evironment specific files.

=cut

sub handle_config {
    my ($dir, $config) = @_;
    my $key = $dir->relative($base_dir)->stringify;
    # config
    my @config_file = $dir->children(qr/^config\.yaml|^config\.yml/);
    die $log->warnf('More than one config file at the same level %s', $key) if @config_file > 1;
    my $file_content = $config_file[0] ? LoadFile($config_file[0]) : {};
    $config->{$key} = $merger->merge(dclone($empty_deployment_config), $file_content);
    # apply environment specific config if exist
    my @env_config_file = $dir->children(qr/$env-config\.yaml|$env-config\.yml/);
    my $env_config = $env_config_file[0] ? LoadFile($env_config_file[0]) : {};
    $config->{$key} = $merger->merge($config->{$key}, $env_config);
    # credentials
    my @cred_file = $dir->children(qr/^credentials\.yaml|^credentials\.yml/);
    my @env_cred_file = $dir->children(qr/$env-credentials\.yaml|$env-credentials\.yml/);
    die $log->warnf('More than one credential file at the same level %s', $key) if @cred_file > 1;
    my $cred  = $cred_file[0] ? LoadFile($cred_file[0]) : dclone($empty_credentials);
    my $env_cred = $env_cred_file[0] ? LoadFile($env_cred_file[0]) : dclone($empty_credentials);
    my $combined_cred = $merger->merge($cred, $env_cred);
    my $cred_level = $credentials;
    for my $lvl (split('/', $key)) {
        $cred_level->{$lvl} = dclone($empty_credentials) unless exists $cred_level->{$lvl};
        $cred_level = $cred_level->{$lvl};
    }
    my $cred_update = $merger->merge($cred_level, $combined_cred);
    $cred_level->{$_} = $cred_update->{$_} for keys %$cred_update;

    return $key;
}

=head2 get_config

loop over all services configurations starting with
Types, System, Service directories and extract their config

=cut

sub get_config {
    my $args = shift;
    my $dirs = $args->{types} // $args->{systems} // $args->{services};

    for my $dir (@$dirs) {
        die $log->warnf('%s | must be a directory', $dir) unless $dir->is_dir();
        my $key = handle_config($dir, $args->{config});
        if ( exists $args->{types} || exists $args->{systems} ) {
            my $type = exists $args->{types} ? 'systems' : 'services';
            get_config({
                    $type => [grep { $_->is_dir } $dir->children],
                    config => $args->{config},
                    key => $key
                });
        } elsif ( exists $args->{services} ) {
            push @all_services, {key => $key, dir => $dir};
        }
    }
}
=head2 filter

filters C<@all_services> based on passed options of services names, types, and systems

=cut

sub filter {
    my $filter_string = join '|', @$services, @$service_types, @$service_systems;
    my $exclude_filter_string = @$excluded_services ? join('|', @$excluded_services) : 'do_not_exclude';

    my @needed_idxs = indexes {
        (grep /($filter_string)/, $_->{key}) && !(grep /($exclude_filter_string)/, $_->{key}) 
    } @all_services;

    $log->warnf('@services count (before filter): %d', scalar @all_services);
    @all_services = @all_services[@needed_idxs];
    $log->warnf('@services (after filter): %d', scalar @all_services);
}

=head2 get_composite_config

process complete configuration for a component
by combining configurations from parent level
reaching to component config itself

=cut

sub get_composite_config {
    my ( $key, $config ) = @_;
    my @levels = split '/', $key;
    my $composite_config = dclone($empty_deployment_config);
    my $k;
    for my $lvl (@levels) {
        $k = $k ? join '/', $k, $lvl : $lvl;
        if ( exists $config->{$k} ) {
            $composite_config = $merger->merge($composite_config, dclone($config->{$k})); 
            # Allow us to unset parent settings
            $composite_config->{$_} = {} for grep { !$config->{$k}{$_} } keys $config->{$k}->%*;
        }
    }
    #configure_node_credentials([get_service_name($key)], $composite_config);
    return $composite_config;

}

=head2 get_service_name

returns service name from key provided (service path)

=cut

sub get_service_name {
    my $key = shift;
    my @levels = split '/', $key;
    shift @levels if $levels[0] eq 'service';
    return join '-', @levels;
}

=head2 get_network_name

returns network name form key provided (service path)

=cut

sub get_network_name {
    my $key = shift;
    my @levels = split '-', get_service_name($key);
    return join '-', $levels[0], $levels[1];
}

=head2 get_instance_nodes

returns list of nodes (instances) associated with service itself
form key provided (service path)

=cut

sub get_instance_nodes {
        my ($key, $global_config) = @_;
        my $config = get_composite_config($key, $global_config);
        my $name = get_service_name($key);
        my @instances = sort keys $config->{instance}->%*;
        my @nodes = map { join '-', $name, $_ } @instances;
        # in case single instance mode
        push @nodes, $name if !@nodes;
        return @nodes;
}

=head2 generate_services_config

process the complete configuration for all needed services
including invoking all helpers configured
and populating services deployment template vars

=cut

sub generate_services_config {
    my $config = shift;

    for my $svc (@all_services) {
        # Combine configuration from top level
        # reaching to service level
        my $svc_config = get_composite_config($svc->{key}, $config);
        # call main helper
        main_helper($svc->{dir}, dclone($config), $svc_config);
        # call service support helpers
        # then service base helpers
        for my $helper_type ($support_helper_prefix, $base_helper_prefix) {
            for my $helper_name ($svc_config->{setting}{helper_dependency}{$helper_type}->@*) {
                $log->tracef('Processing service helper: %s | %s | %s', $svc->{key}, $helper_type, $helper_name);
                my $helper = join '_', $helper_type, $helper_name;
                if (exists &{$helper}) {
                    my $helper_sub = \&{$helper};
                    # clone config before passing just in case
                    # added helpers modify them mistakenly
                    $helper_sub->($svc->{dir}, dclone($config), $svc_config);
                }
            }
        }

        $log->tracef('Service complete config: %s | %s', $svc->{key}, Dumper($svc_config));
        # Trigger instances logic
        for my $instance (get_instance_nodes($svc->{key}, $config)) {
            # multi level instance
            my @node = split '-', $instance;
            my $instance_config = exists $svc_config->{instance}{$node[-1]} ? $svc_config->{instance}{$node[-1]} : {};
            my $merged_config = $merger->merge($svc_config->{service_config}, $instance_config);
            # get everything ready for docker-compose generation
            $merged_config->{env_file} = wirte_env_file($instance, $merged_config->{environment});
            #wirte_env_file($instance, $merged_config->{environment});
            push $templates_var->{docker_compose}->@*, {
                service => $instance,
                config => $merged_config,
            };

        }

    }

}

=head2 configure_docker_deployment

Decides which config to use, it could be one of these:
- Dockerfile
- Image
- docker-compose yaml

=cut

sub configure_docker_deployment {
    my ($dir, $global_config, $config) = @_;

    # Check for related files if exists in directory
    if($dir->child('Dockerfile')->exists) {
        $config->{docker_deployment}{build} = $dir->relative($base_dir)->stringify;
    } elsif($dir->child('docker-compose.yml')->exists) {
        $config->{docker_deployment}{extends} = {
            file => $dir->child('docker-compose.yml')->relative($base_dir)->stringify,
            service => '',
        };
    }
}

=head2 configure_node_credentials

setup and prepare a particluar service credentials

=cut

sub configure_node_credentials {
    my ($instances, $config) = @_;
    for my $node (@$instances) {
        my @level = split '-', $node;
        my $cred_level = $credentials->{service};
        my $cred = dclone($empty_credentials);
        for my $lvl (@level) {
            if (exists $cred_level->{$lvl}) {
                for my $k (keys %$cred) {
                    $cred->{$k} = $merger->merge(
                        $cred->{$k},
                        $cred_level->{$lvl}{$k}
                    )
                    if exists $cred_level->{$lvl}{$k};
                }
            }
            $cred_level = $cred_level->{$lvl};
        }
        # at this point composed credetials for instance is ready
        # write files and add volume paths
        my $svc_config = dclone($empty_service_config);
        configure_credential_files($node, $cred->{file}, $svc_config) if $cred->{file}->@* > 0;
        $svc_config->{environment} = $merger->merge($svc_config->{environment}, $cred->{environment});
        # add environment
        if ( @$instances > 1 ) {
            # populate specific instance config when exists
            my @instance_name = split '-', $node;
            $config->{instance}{$instance_name[-1]} = $merger->merge(
                $config->{instance}{$instance_name[-1]},
                $svc_config,
            );
        } else {
            # populate service_config when single node
            $config->{service_config} = $merger->merge(
                $svc_config,
                $config->{service_config},
            );
        }
    }
}

=head2 configure_credential_files

Parse and write file contents from credentials
also make the volume available for deployment config

=cut

sub configure_credential_files {
    my ($node, $files, $config) = @_;
    my $credential_path = path(join '/', $base_dir, $credentials_dir);
    $credential_path->mkpath() unless $credential_path->is_dir();

    my $node_cred_path = $credential_path->child($node);
    $node_cred_path->mkpath() unless $node_cred_path->is_dir();
    # Write files content on disk
    for my $file (@$files) {
        my $path = $file->{container_path};
        my @file_name = split '/', $path;
        my $written_file = $node_cred_path->child($file_name[-1]);
        my $current_content = $written_file->exists ? $written_file->slurp_utf8 : '';
        if ( $current_content ne $file->{content} ) {
            $written_file->spew_utf8($file->{content});
            $written_file->chmod(0666);
            $log->warnf('Mounted credential file ( %s ) has been updated| service ( %s ) container must be restarted',
                $path, get_service_name($node));
            $updated_services->{get_service_name($node)} = 1;
        }
        # update service config to have the file included
        # map path to volume
        $config->{volume}{'./'.$written_file->relative($base_dir)->stringify} = $path;
        my @name = split '\.', $file_name[-1];
        # add file path as env variable
        $config->{environment}{join('_', 'file', $name[0])} = $path;
    }
}

=head2 wirte_env_file

this will populate a dedicated env file with
all passed environment variable as an env_file

=cut

sub wirte_env_file {
    my ($node, $env) = @_;

    my $env_dir = path(join '/', $base_dir, $environmet_dir);
    $env_dir->mkpath() unless $env_dir->is_dir();

    my $env_file = $env_dir->child("$node.env");
    my @env_content = map { $_ . '=' . $env->{$_} . "\n" } sort keys %$env;
    # TODO: detect env file changes and populate $updated_services
    $env_file->spew(@env_content);
    $env_file->chmod(0666);
    return './'.$env_file->relative($base_dir)->stringify;

}

=head2 write_pgservice_file

Parse and write pg_service.conf file contents
also make the volume available for deployment config

=cut

sub write_pgservice_file {
    my ($node, $pg_services, $config) = @_;
    my $credential_path = path(join '/', $base_dir, $credentials_dir);
    $credential_path->mkpath() unless $credential_path->is_dir();

    my $node_cred_path = $credential_path->child($node);
    $node_cred_path->mkpath() unless $node_cred_path->is_dir();
    my $pg_service_file = $node_cred_path->child('pg_service.conf');
    my $path = '/opt/.pg_service.conf';

    my $template_file = path(join '/', $base_dir, 'template', 'pg_service.conf.tt2');
    my $tt = Template->new({ABSOLUTE => 1});
    $tt->process(
        $template_file->stringify,
        {
            pg_service => $pg_services,
        },
        $pg_service_file->stringify
    ) or die $tt->error;

    $config->{volume}{'./'.$pg_service_file->relative($base_dir)->stringify} = $path;
    $config->{environment}{PGSERVICEFILE} = $path;
}

=head2 generate_docker_compose

generate docker compose file based on template
uses C<$templates_var{docker_compose}>

=cut

sub generate_docker_compose {
    # having relative path as hash key is breaking Template
    # convert volume hash to array for template
    for my $svc ($templates_var->{docker_compose}->@*) {
        $svc->{config}{volume} = [ map { "$_:".$svc->{config}{volume}{$_} } sort keys $svc->{config}{volume}->%* ];
        $svc->{config}{network} = [sort $svc->{config}{network}->@*];
    }
    my @services = sort { $a->{service} cmp $b->{service} } $templates_var->{docker_compose}->@*;
    my @all_networks = sort keys %$all_networks;
    my @all_volumes = sort keys %$all_volumes;
    $log->tracef('- %s', $_) for @services;
    $log->infof('%d total services defined', 0 + @services);
    $log->debugf('Services definitions passed to docker-compose: %s', Dumper(\@services));

    my $template_file = path(join '/', $base_dir, 'template', 'docker-compose.yml.tt2');
    my $compose_file = path(join '/', $base_dir, 'docker-compose.yml');
    my $prev_compose_file = path(join '/', $base_dir, 'previous_docker-compose.yml');
    my $update_flag_file = path(join '/', $base_dir, $update_flag);

    # Check docker-compose contents before rewriting it.
    my $compose_prev_content = $compose_file->exists ? $compose_file->slurp_utf8 : '';
    my $tt = Template->new({ABSOLUTE => 1});
    $tt->process(
        $template_file->stringify,
        {
            service_list => \@services,
            all_networks => \@all_networks,
            all_volumes => \@all_volumes,
        },
        $compose_file->stringify
    ) or die $tt->error;
    my $compose_cur_content = $compose_file->slurp_utf8;
    my $diff = diff \$compose_prev_content, \$compose_cur_content;
    my @required_restart = keys %$updated_services;
    if ( $diff or @required_restart ) {
        # TODO: populate flag file with exact services updated
        $update_flag_file->touch();
        $prev_compose_file->spew_utf8($compose_prev_content);
        $log->infof('docker-compose.yml file updates diff: %s', $diff);
    }
    $log->infof('done! checkout docker-compose.yml file');
}

=head1 Helpers

These helpers are custom functions
dedicated for a certain system/technology settings and config

=head2 main_helper

Helper used to setup the main configuration for services

=cut

sub main_helper {
    my ($dir, $global_config, $config) = @_;

    my $svc_config = dclone($empty_service_config);
    # include credentials
    my @instances = get_instance_nodes($dir->relative($base_dir)->stringify, $global_config);
    configure_node_credentials(\@instances, $config);
    # check deployment type
    configure_docker_deployment($dir, $global_config, $svc_config);
    # setup required networks
    # we can limit them depending on requirements
    # for now add all networks
    # add available services as environment variables
    my $networks = {};
    for my $svc (@all_services) {
        my @nodes = get_instance_nodes($svc->{key}, $global_config);
        my $network_name = get_network_name($svc->{key});
        $networks->{$network_name} = 1;
        for my $node (@nodes) {
            my $key = $node;
            $key =~ s/-/_/g;
            $svc_config->{environment}{"service_$key"} = $node;
        }
    }
    push $svc_config->{network}->@*, keys %$networks;
    $all_networks->{$_} = 1 for keys %$networks;
    $config->{service_config} = $merger->merge($svc_config, $config->{service_config});
}

=head2 Base

=head3 base_helper_myriad

Helper for Myriad services config

=cut

sub base_helper_myriad {
    my ($dir, $global_config, $config) = @_;

    my $svc_config = $merger->merge(dclone($empty_service_config), $config->{helper}{myriad});
    # get support helpers settings
    if ( exists $config->{setting}{redis}{which} ) {
        my $var_name;
        my $idx = 0;
        for my $redis ($config->{setting}{redis}{which}->@*) {
            $var_name = $var_name ? join('_', $var_name, $idx) : 'MYRIAD_TRANSPORT_REDIS';
            $svc_config->{environment}{$var_name} = $config->{infra_config}{redis}{$redis}{transport_uri};
            push $svc_config->{network}->@*, $config->{infra_config}{redis}{$redis}{network};
            $idx++;
        }
    }
    if ( exists $config->{infra_config}{datadog} ) {
        $svc_config->{environment}{MYRIAD_METRICS_HOST} = $config->{infra_config}{datadog}{datadog_agent_host};
        $svc_config->{environment}{MYRIAD_METRICS_ADAPTER} = 'DogStatsd';
    }
    if ( exists $config->{setting}{postgresql}{which} ) {
        my @pg_services;
        for my $postgresql ($config->{setting}{postgresql}{which}->@*) {
            my $v_name = join '_', 'postgresql', ($postgresql =~ /service\/support\/postgresql\/(\w*)/)[0];
            $svc_config->{environment}{"${v_name}_uri_$_"} = $config->{infra_config}{postgresql}{$postgresql}{postgresql_uri}{$_}
                for keys $config->{infra_config}{postgresql}{$postgresql}{postgresql_uri}->%*;
            $svc_config->{environment}{"${v_name}_db"} = $config->{infra_config}{postgresql}{$postgresql}{db_name};
            push $svc_config->{network}->@*, $config->{infra_config}{postgresql}{$postgresql}{network};
            push @pg_services, $config->{infra_config}{postgresql}{$postgresql}{service}->@*;
        }
        my $name = get_service_name($dir->relative($base_dir)->stringify);
        write_pgservice_file($name, \@pg_services, $svc_config);
    }
    # Set volume path
    $svc_config->{volume}{'./'.$dir->relative($base_dir)->stringify} = '/opt/app/';
    # Set command
    $svc_config->{command} = ['CodeNSmoke::Service::']
        if !$config->{service_config}{command}->@*;
    # set docker_deployment
    $svc_config->{docker_deployment}{image} = 'deriv/myriad:stable'
        unless exists $config->{service_config}{docker_deployment}{build};
    # Do not reset preset config
    $config->{service_config} = $merger->merge($svc_config, $config->{service_config});
}

=head3 base_helper_hapi

Helper for NodeJS Hapi services config

=cut

sub base_helper_hapi {
    my ($dir, $global_config, $config) = @_;

    my $svc_config = $merger->merge(dclone($empty_service_config), $config->{helper}{hapi});
    $svc_config->{environment}{NODE_ENV} = $env;
    # get support helpers settings
    if ( exists $config->{setting}{redis} && scalar $config->{setting}{redis}{which}->@* && exists $config->{infra_config}{redis}) {
        my $var_name;
        my $idx = 0;
        for my $redis ($config->{setting}{redis}{which}->@*) {
            $var_name = $var_name ? join('_', $var_name, $idx) : 'TRANSPORT_REDIS';
            $svc_config->{environment}{$var_name} = $config->{infra_config}{redis}{$redis}{transport_uri};
            $var_name .= '_NODES';
            $svc_config->{environment}{$var_name} = $config->{infra_config}{redis}{$redis}{redis_nodes};
            push $svc_config->{network}->@*, $config->{infra_config}{redis}{$redis}{network};
            $idx++;
        }
    }
    if ( exists $config->{setting}{mssql} && scalar $config->{setting}{mssql}{which}->@* ) {
        my $var_name;
        my $idx = 0;
        for my $mssql ($config->{setting}{mssql}{which}->@*) {
            $var_name = $var_name ? join('_', $var_name, $idx) : 'TRANSPORT_MSSQL';
            $svc_config->{environment}{$var_name} = $config->{infra_config}{mssql}{$mssql}{mssql_uri};
            $svc_config->{environment}{SA_PASSWORD} = $config->{infra_config}{mssql}{$mssql}{sa_password};
            $svc_config->{environment}{mssql_db_name} = $config->{infra_config}{mssql}{$mssql}{db_name};
            push $svc_config->{network}->@*, $config->{infra_config}{mssql}{$mssql}{network};
            $idx++;
        }
    }
    if ( exists $config->{infra_config}{datadog} ) {
        $svc_config->{environment}{METRICS_HOST} = $config->{infra_config}{datadog}{datadog_agent_host};
    }
    if ( exists $config->{infra_config}{mongodb} ) {
        $svc_config->{environment}{mongodb_uri} = $config->{infra_config}{mongodb}{mongodb_uri};
        push $svc_config->{network}->@*, $config->{infra_config}{mongodb}{network};
    }
    # Set specific environment
    my @instances = get_instance_nodes($dir->relative($base_dir)->stringify, $global_config);
    # there are more than 1 node
    if ( @instances > 1 ) {
        for my $key (@instances) {
            my @ins = split '-', $key;
            my $ins_conf = $config->{instance}{$ins[-1]};

            $ins_conf->{environment}{HOSTNAME} = $key;
            $ins_conf->{environment}{HOSTNAME_DFAPI} = $key;
        }
    # Single node redis
    } else {
        $svc_config->{environment}{HOSTNAME} = $instances[0];
        $svc_config->{environment}{HOSTNAME_DFAPI} = $instances[0];
    }
    # Set volume path
    $svc_config->{volume}{'./'.$dir->relative($base_dir)->stringify} = '/usr/src/app/';
    # Do not reset preset config
    $config->{service_config} = $merger->merge($svc_config, $config->{service_config});
}

=head2 Support

Consists of two parts:
infrastructure configurations
service configuration

=head3 support_helper_redis

Helper for Redis service config

=cut

sub support_helper_redis {
    my ($dir, $global_config, $config) = @_;
    # Check global config for available redis(es)
    for my $redis (grep /service\/support\/redis\/(\w*)/, keys %$global_config) {
        my $redis_config = get_composite_config($redis, $global_config);
        my $name = get_service_name($redis);
        my @instances = sort keys $redis_config->{instance}->%*;
        my @nodes = get_instance_nodes($redis, $global_config);
        # helper infrastructure setting
        # to be used by dependent services
        $config->{infra_config}{redis}{$redis} = {
            redis_nodes => join(' ', @nodes),
            transport_uri => "redis://$nodes[0]:6379",
            network => $name,
        };
        # helper service setting
        # to be used by helper services themselves
        if ($dir->relative($base_dir)->subsumes("$redis")) {
            $all_networks->{$name} = 1;
            my $svc_config = dclone($empty_service_config);
            $svc_config->{environment}{REDIS_NODES} = join(' ', @nodes);
            # Own specific network
            push $svc_config->{network}->@*, $name;
            # set settings on instances when
            # there are more than 1 node
            if ( @nodes > 1 ) {
                my $idx = 0;
                for my $key (@instances) {
                    my $node = $nodes[$idx];
                    $all_volumes->{"$node-data"} = 1;
                    my $clone = dclone($svc_config);
                    $clone->{volume}{"$node-data"} = '/bitnami';
                    $clone->{environment}{REDIS_CLUSTER_CREATOR} = 'yes' if $idx == 0;
                    $config->{instance}{$key} = $merger->merge($config->{instance}{$key}, $clone);
                    $idx++;
                }
            # Single node redis
            } else {
                my $node = $nodes[0];
                $all_volumes->{"$node-data"} = 1;
                $svc_config->{volume}{"$node-data"} = '/bitnami';
                $config->{service_config} = $merger->merge($config->{service_config}, $svc_config);
            }
        }

    }

}

=head3 support_helper_datadog

Helper for DataDog agent config

=cut

sub support_helper_datadog {
    my ($dir, $global_config, $config) = @_;
    # Check global config for available datadog agent(s)
    for my $datadog (grep /service\/support\/datadog\/(\w*)/, keys %$global_config) {
        my $datadog_config = get_composite_config($datadog, $global_config);
        my $name = get_service_name($datadog);
        my @nodes = get_instance_nodes($datadog, $global_config);
        # helper infrastructure setting
        # to be used by dependent services
        $config->{infra_config}{datadog} = {
            datadog_agent_nodes => join(' ', @nodes),
            datadog_agent_host => "$nodes[0]",
            specific_network => $name,
        };
        $all_networks->{$name} = 1;
        # helper service setting
        # to be used by helper services themselves
        if ($dir->relative($base_dir)->subsumes("$datadog")) {
            my $svc_config = dclone($empty_service_config);
            $svc_config->{environment}{DD_HOSTNAME} = $nodes[0];

            push $svc_config->{network}->@*, $name;
            my $node = $nodes[0];
            $config->{service_config} = $merger->merge($config->{service_config}, $svc_config);
        }

    }

}

=head3 support_helper_postgresql

Helper for PostgreSQL service config

=cut

sub support_helper_postgresql {
    my ($dir, $global_config, $config) = @_;
    # Check global config for available postgresql(es)
    for my $postgresql (grep /service\/support\/postgresql\/(\w*)/, keys %$global_config) {
        my $postgresql_config = get_composite_config($postgresql, $global_config);
        my $name = get_service_name($postgresql);
        my @db_name = split '-', $name;
        my @instances = sort keys $postgresql_config->{instance}->%*;
        my @nodes = get_instance_nodes($postgresql, $global_config);
        configure_node_credentials(\@nodes, $postgresql_config);
        # helper infrastructure setting
        # to be used by dependent services
        my $password = $postgresql_config->{instance}{0}{environment}{POSTGRESQL_PASSWORD};
        my $nodes_uris;
        my $pg_service = [];
        my $node;
        for my $type (qw/master replica/) {
            $node = shift @nodes;
            push @nodes, $node;
            $nodes_uris->{$type} = "postgresql://postgres:$password" . "@" . "$node:5432/$db_name[-1]";
            push @$pg_service, {name => join('_', $db_name[-1], $type), dbname => $db_name[-1], host => $node, password => $password};
        }
        @{$nodes_uris}{qw/master replica/} = map {"postgresql://postgres:$password" . "@" . "$_:5432/$db_name[-1]"} @nodes;
        $config->{infra_config}{postgresql}{$postgresql} = {
            postgresql_nodes => join(' ', @nodes),
            postgresql_uri => $nodes_uris,
            db_name => $db_name[-1],
            db_password => $config->{environment}{POSTGRESQL_PASSWORD},
            network => $name,
            service => $pg_service
        };
        $all_networks->{$name} = 1;
        # helper service setting
        # to be used by helper services themselves
        if ($dir->relative($base_dir)->subsumes("$postgresql")) {
            my $svc_config = dclone($empty_service_config);
            $svc_config->{environment}{REPMGR_PARTNER_NODES} = join(',', @nodes);
            $svc_config->{environment}{REPMGR_PRIMARY_HOST} = $nodes[0];
            $svc_config->{environment}{POSTGRESQL_DATABASE} = $db_name[-1];
            $svc_config->{environment}{REPMGR_NODE_NETWORK_NAME} = $nodes[0];

            push $svc_config->{network}->@*, $name;
            # set settings on instances when
            # there are more than 1 node
            if ( @nodes > 1 ) {
                my $idx = 0;
                for my $key (@instances) {
                    my $node = $nodes[$idx];
                    $all_volumes->{"$node-data"} = 1;
                    my $clone = dclone($svc_config);
                    $clone->{volume}{"$node-data"} = '/bitnami/postgresql';
                    $clone->{environment}{REPMGR_NODE_NAME} = $node;
                    $clone->{environment}{REPMGR_NODE_NETWORK_NAME} = $node;
                    $config->{instance}{$key} = $merger->merge($config->{instance}{$key}, $clone);
                    $idx++;
                }
            # Single node postgresql
            } else {
                my $node = $nodes[0];
                $all_volumes->{"$node-data"} = 1;
                $svc_config->{volume}{"$node-data"} = '/bitnami';
                $svc_config->{environment}{REPMGR_NODE_NAME} = $node;
                $config->{service_config} = $merger->merge($config->{service_config}, $svc_config);
            }
        }
    }
}

=head3 support_helper_mssql

Helper for MsSQL service config

=cut

sub support_helper_mssql {
    my ($dir, $global_config, $config) = @_;
    # Check global config for available mssql(es)
    for my $mssql (grep /service\/support\/mssql\/(\w*)/, keys %$global_config) {
        my $mssql_config = get_composite_config($mssql, $global_config);
        my $name = get_service_name($mssql);
        my @db_name = split '-', $name;
        my @instances = sort keys $mssql_config->{instance}->%*;
        my @nodes = get_instance_nodes($mssql, $global_config);
        configure_node_credentials(\@nodes, $mssql_config);
        # helper infrastructure setting
        # to be used by dependent services
        $config->{infra_config}{mssql}{$mssql} = {
            mssql_nodes => join(' ', @nodes),
            mssql_uri => "mssql://$nodes[0]:1433",
            db_name => $db_name[-1],
            sa_password => $mssql_config->{service_config}{environment}{SA_PASSWORD},
            network => $name,
        };
        $all_networks->{$name} = 1;
        # helper service setting
        # to be used by helper services themselves
        if ($dir->relative($base_dir)->subsumes("$mssql")) {
            my $svc_config = dclone($empty_service_config);
            $svc_config->{environment}{PARTNER_NODES} = join(',', @nodes);

            push $svc_config->{network}->@*, $name;
            my $node = $nodes[0];
            $all_volumes->{"$node-data"} = 1;
            $svc_config->{volume}{"$node-data"} = '/var/opt/mssql';
            $config->{service_config} = $merger->merge($config->{service_config}, $svc_config);
        }
    }
}

generate();
