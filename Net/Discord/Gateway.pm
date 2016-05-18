package Net::Discord::Gateway;

use v5.10;
use warnings;
use strict;

use Mojo::UserAgent;
use Mojo::JSON qw(decode_json encode_json);
use Mojo::IOLoop;
use Compress::Zlib;
use Data::Dumper;

my %handlers = (
    'MESSAGE_CREATE'    => { func => \&on_message_create },
    'READY'             => { func => \&on_ready },
    '9'                 => { func => \&on_invalid_session },
);

# Requires the Bearer Token to be passed in, along with the application's name, URL, and version.
sub new
{
    my ($class, $params) = @_;
    my $self = {};

    die("Net::Discord::Gateway requires an application name.") unless defined $params->{'name'};
    die("Net::Discord::Gateway requires an application URL.") unless defined $params->{'url'};
    die("Net::Discord::Gateway requires an application version.") unless defined $params->{'version'};

    # Store the name, url, version, and callbacks
    $self->{'token'}    = $params->{'token'};
    $self->{'name'}     = $params->{'name'};
    $self->{'url'}      = $params->{'url'};
    $self->{'version'}  = $params->{'version'};
    $self->{'callbacks'} = $params->{'callbacks'} if ( defined $params->{'callbacks'} ); 

    # API vars - Will need to be updated if the API changes
    $self->{'base_url'}     = 'https://discordapp.com/api';
    $self->{'gateway_url'}   = $self->{'base_url'} . '/gateway';
    $self->{'gateway_version'} = 4;
    $self->{'gateway_encoding'} = 'json';

    # Other Vars
    $self->{'agent'}    = $self->{'name'} . ' (' . $self->{'url'} . ',' . $self->{'version'} . ')';

    my $ua = Mojo::UserAgent->new;

    # Make sure the token is added to every request automatically.
    $ua->on(start => sub {
        my ($ua, $tx) = @_;
        $tx->req->headers->authorization($self->{'token'});
    });


    $ua->transactor->name($self->{'agent'});    # Set the UserAgent for what Discord expects
    $ua->inactivity_timeout(120);   # Set the timeout to 2 minutes, well above what the Discord server expects for a heartbeat.

    $self->{'ua'} = $ua; # Store this ua

    bless $self, $class;
    return $self;
}

sub username
{
    my $self = shift;
    return $self->{'username'};
}

# This updates the client status
# Takes a hashref with 'idle_since' and/or 'game' present.
# idle_since should be the epoch time in ms, game is a text string.
sub status_update
{
    my ($self, $param) = @_;

    my $idle = $param->{'idle_since'} if defined $param->{'idle_since'};
    my $game = $param->{'game'} if defined $param->{'game'};
    my $op = 3;
    my $d = {
        'idle_since' => (defined $idle ? $idle : undef),
        'game' => {
            'name' => (defined $game ? $game : undef)
        }
    };

    send_op($self, $op, $d);
}

# This retrieves and returns Gateway URL for connecting to Discord. 
sub gateway
{
    my $self = shift;
    my $url = $self->{'gateway_url'};
    my $ua = $self->{'ua'};
    my $tx = $ua->get($url);    # Fetch the Gateway WS URL

    return $tx->res->json->{'url'}; # Return the URL field from the JSON response
}

# This sub is used for sending messages to the gateway.
# It takes an OP code, optional Sequence and Type, and a Data hashref to pass in.
# The arguments are put together into a hashref and then JSON encoded for delivery over the websocket.
sub send_op
{
    my ($self, $op, $d, $s, $t) = @_;

    my $tx = $self->{'tx'};

    my $package = {
        'op' => $op,
        'd' => $d
    };

    $package->{'s'} = $s if defined $s;
    $package->{'t'} = $t if defined $t;

    my $json = encode_json($package);

    say $json;

    $tx->send($json);
}

# This sub establishes a connection to the Discord Gateway web socket
# WS URL must be passed in.
sub connect
{
    my ($self, $url) = @_;

    my $ua = $self->{'ua'};

    # Add URL Params 
    $url .= "?v=" . $self->{'gateway_version'} . "&encoding=" . $self->{'gateway_encoding'};


    $ua->websocket($url => sub {
        my ($ua, $tx) = @_;
        say 'WebSocket handshake failed!' and return unless $tx->is_websocket;
        say 'WebSocket Connection Established.';

        $self->{'tx'} = $tx;

        # First thing we have to do is identify ourselves.
        send_ident($self, $tx);

        # This should fire if the websocket closes for any reason.
        $tx->on(finish => sub {
                    my ($tx, $code, $reason) = @_;
                    say "WebSocket closed with status $code.";
                    $tx->finish;
                    exit;
        });

        # This is the main loop - It handles all incoming messages from the server.
        $tx->on(message => sub {
            my ($tx, $msg) = @_;
            
            # If the message is compressed with zlib, uncompress it first.
            my $uncompressed = uncompress($msg);
            $msg = $uncompressed if defined $uncompressed;
            
            # Decode the JSON message into a perl structure
            my $hash = decode_json $msg;

            my $op_msg = "OP " . $hash->{'op'};
        
            $op_msg .= " SEQ " . $hash->{'s'} if defined $hash->{'s'};
            $op_msg .= " " . $hash->{'t'} if defined $hash->{'t'};

            say $op_msg;
            
            $self->{'s'} = $hash->{'s'} if defined $hash->{'s'};    # Update the latest Sequence Number.

            # Call the relevant handler
            if ( defined $hash->{'t'} and exists $handlers{$hash->{'t'}} )
            {
                $handlers{$hash->{'t'}}->{'func'}->($self, $tx, $hash);    # Call the handler function
            }
            elsif ( exists $handlers{$hash->{'op'}} )
            {
                $handlers{$hash->{'op'}}->{'func'}->($self, $tx, $hash);
            }
        });

    });

    # Start the IOLoop (Websocket connection)
    Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
}

# This has to be sent after connecting in order to receive a READY Packet.
sub send_ident
{
    my ($self, $tx) = @_;

    my $op = 2;
    my $d = {
        "token" => $self->{'token'}, 
        "properties" => { 
            '$os' => $^O, 
            '$browser' => $self->{'name'}, 
            '$device' => $self->{'name'}, 
            '$referrer' => "", 
            '$referring_domain' => ""
        }, 
        "compress" => "false", 
        "large_threshold" => 250
    };

    say "OP 2 SEQ 0 IDENTIFY";
    send_op($self, $op, $d);
}

# After sending an Ident packet we'll get this one in response.
# It contains the heartbeat interval and other useful info the user may want to store.
sub on_ready
{
    my ($self, $tx, $hash) = @_;
    my $callbacks = $self->{'callbacks'};

    # Store our user info just in case we need it later.
    $self->{'id'} = $hash->{'d'}{'user'}{'id'};
    $self->{'username'} = $hash->{'d'}{'user'}{'username'};
    $self->{'avatar'} = $hash->{'d'}{'user'}{'avatar'};
    $self->{'discriminator'} = $hash->{'d'}{'user'}{'discriminator'};

    # The ready packet gives us our heartbeat interval, so we can start sending those.
    $self->{'heartbeat_interval'} = $hash->{'d'}{'heartbeat_interval'} / 1000;
    Mojo::IOLoop->recurring( $self->{'heartbeat_interval'},
        sub {
            my $op = 1;
            my $d = $self->{'s'};
            say "OP 1 SEQ " . $self->{'s'} . " HEARTBEAT";
            send_op($self, $op, $d);
        }
    );

    $callbacks->{'on_ready'}->($hash->{'d'}) if exists $callbacks->{'on_ready'};
}

# Any messages sent will trigger this function.
# There's not much to do other than call the user's own callback function and pass in the data section of the incoming structure.
sub on_message_create
{
    my ($self, $tx, $hash) = @_;
    my $callbacks = $self->{'callbacks'};

    $callbacks->{'on_message_create'}->($hash->{'d'}) if exists $callbacks->{'on_message_create'};
}

sub on_invalid_session
{
    my ($self, $tx, $hash) = @_;

    say "Invalid Session.";

    $tx->finish;
    exit 1;
}

1;
