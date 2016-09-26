package Net::Discord::Gateway;

use v5.10;
use warnings;
use strict;

use Mojo::UserAgent;
use Mojo::JSON qw(decode_json encode_json);
use Mojo::IOLoop;
use Compress::Zlib;
use Encode::Guess;

my %handlers = (
    '0' => { 'MESSAGE_CREATE'   => { func => \&on_message_create  },
             'READY'            => { func => \&on_ready           }},
    '9'                         => { func => \&on_invalid_session  },
    '10'                        => { func => \&on_hello },
    '11'                        => { func => \&on_heartbeat_ack },
);

# Websocket Close codes defined in RFC 6455, section 11.7.
# Also includes some Discord-specific codes from the Discord API Reference Docs (Starting at 4000)
my %close = (
    '1000'  => 'Normal Closure',
    '1001'  => 'Going Away',
    '1002'  => 'Protocol Error',
    '1003'  => 'Unsupported Data',
    '1005'  => 'No Status Received',
    '1006'  => 'Abnormal Closure',
    '1007'  => 'Invalid Frame Payload Data',
    '1008'  => 'Policy Violation',
    '1009'  => 'Message Too Big',
    '1010'  => 'Mandatory Extension',
    '1011'  => 'Internal Server Err',
    '1012'  => 'Service Restart',
    '1013'  => 'Try Again Later',
    '1015'  => 'TLS Handshake',
    '4000'  => 'Unknown Error',
    '4001'  => 'Unknown Opcode',
    '4002'  => 'Decode Error',
    '4003'  => 'Not Authenticated',
    '4004'  => 'Authentication Failed',
    '4005'  => 'Already Authenticated',
    '4007'  => 'Invalid Sequence',
    '4008'  => 'Rate Limited',
    '4009'  => 'Session Timeout',
    '4010'  => 'Invalid Shard'
);

# Prevent sending a reconnect following certain codes.
# This always requires a new session to be established if these codes are encountered.
# Not sure if 1000 and 1001 require this, but I don't think it hurts to include them.
my %no_resume = ( 
    '1000' => 'Normal Closure',
    '1001' => 'Going Away',
    '1009' => 'Message Too Big',
    '1011' => 'Internal Server Err',
    '1012' => 'Service Restart',
    '4007' => 'Invalid Sequence',
    '4009' => 'Session Timeout',
    '4010' => 'Invalid Shard'
);

# Requires the Bearer Token to be passed in, along with the application's name, URL, and version.
sub new
{
    my ($class, %params) = @_;
    my $self = {};

    die("Net::Discord::Gateway requires an application name.") unless defined $params{'name'};
    die("Net::Discord::Gateway requires an application URL.") unless defined $params{'url'};
    die("Net::Discord::Gateway requires an application version.") unless defined $params{'version'};

    # Store the name, url, version, and callbacks
    $self->{'token'}            = $params{'token'};
    $self->{'name'}             = $params{'name'};
    $self->{'url'}              = $params{'url'};
    $self->{'version'}          = $params{'version'};
    $self->{'callbacks'}        = $params{'callbacks'} if ( defined $params{'callbacks'} ); 
    $self->{'verbose'}          = ( defined $params{'verbose'} ? $params{'verbose'} : 0 );

    # API vars - Will need to be updated if the API changes
    $self->{'base_url'}         = 'https://discordapp.com/api';
    $self->{'gateway_url'}      = $self->{'base_url'} . '/gateway';
    $self->{'gateway_version'}  = 6;
    $self->{'gateway_encoding'} = 'json';

    # Other Vars
    $self->{'agent'}            = $self->{'name'} . ' (' . $self->{'url'} . ',' . $self->{'version'} . ')';
    $self->{'reconnect'}        = $params{'reconnect'} if exists $params{'reconnect'};
    $self->{'allow_resume'}  = 1; # Certain disconnect reasons will change this to a 0, forcing a new connection instead of a resume on reconnect.
    $self->{'heartbeat_check'};   # Defaults to 0. Add 1 every time we send a heartbeat, subtract one every time we receive a heartbeat ack.
                                    # This way we know very easily if something is wrong and can reconnect.

    my $ua = Mojo::UserAgent->new;

    # Make sure the token is added to every request automatically.
    $ua->on(start => sub {
        my ($ua, $tx) = @_;
        $tx->req->headers->authorization($self->{'token'});
    });

    $ua->transactor->name($self->{'agent'});    # Set the UserAgent for what Discord expects
    $ua->inactivity_timeout(120);   # Set the timeout to 2 minutes, well above what the Discord server expects for a heartbeat.
    $ua->connect_timeout(5);

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
    my $d = {};
    $d->{'idle_since'} = ( defined $idle ? $idle : undef );
    $d->{'game'}{'name'} = $game if defined $game;

    send_op($self, $op, $d);
}

# This retrieves and returns Gateway URL for connecting to Discord. 
sub gateway
{
    my $self = shift;
    my $url = $self->{'gateway_url'};
    my $ua = $self->{'ua'};
    my $tx = $ua->get($url);    # Fetch the Gateway WS URL

    # Store the URL in $self
    $self->{'websocket_url'} = $tx->res->json->{'url'};

    return $tx->res->json->{'url'}; # Return the URL field from the JSON response
}

# This sub is used for sending messages to the gateway.
# It takes an OP code, optional Sequence and Type, and a Data hashref to pass in.
# The arguments are put together into a hashref and then JSON encoded for delivery over the websocket.
sub send_op
{
    my ($self, $op, $d, $s, $t) = @_;

    my $tx = $self->{'tx'};

    if ( !defined $tx or $self->{'heartbeat_check'} > 1 ) 
    {
        gw_disconnect($self, "Connection does not exist.");
        say localtime(time) . " Websocket not connected. Attempting to establish a new connection..." if $self->{'verbose'};
        on_finish($self, $tx, 4009, "Timeout: Failed heartbeat check");
        return;
    } 

    my $package = {
        'op' => $op,
        'd' => $d
    };

    $package->{'s'} = $s if defined $s;
    $package->{'t'} = $t if defined $t;

    my $json = encode_json($package);

    say localtime(time) . " " . $json if $self->{'verbose'};

    $tx->send($json);
}

# This is pretty much just a stub for connect that calls it with the reconnect parameter, triggering a RESUME instead of an IDENT after connecting.
sub gw_resume
{
    my ($self) = @_;

    my $url = gateway($self);

    gw_connect($self, $url, 1);
}

# This sub establishes a connection to the Discord Gateway web socket
# WS URL must be passed in.
# Optionally pass in a boolean $reconnect (1 or 0) to tell connect whether to send an IDENTIFY or a RESUME
sub gw_connect
{
    my ($self, $url, $reconnect) = @_;

    my $ua = $self->{'ua'};

    # Add URL Params 
    $url .= "?v=" . $self->{'gateway_version'} . "&encoding=" . $self->{'gateway_encoding'};
    say localtime(time) . ' Connecting to ' . $url;

    do { 

        $ua->websocket($url => sub {
            my ($ua, $tx) = @_;
    
            unless ($tx->is_websocket)
            {
                $self->{'tx'} = undef;
                say localtime(time) . ' WebSocket handshake failed!';
                return;
            }
    
            say localtime(time) . ' WebSocket Connection Established.' if $self->{'verbose'};
            $self->{'heartbeat_check'} = 0; # Always make sure this is set to 0 on a new connection.
    
            $self->{'tx'} = $tx;
    
            # If this is a new connection, send OP 2 IDENTIFY
            # If we are reconnecting, send OP 6 RESUME
            (defined $reconnect and $reconnect and $self->{'allow_resume'}) ? send_resume($self, $tx) : send_ident($self, $tx);
    
            # Reset the state of allow_resume now that we have reconnected.
            $self->{'allow_resume'} = 1;
    
            # This should fire if the websocket closes for any reason.
            $tx->on(finish => sub {
                my ($tx, $code, $reason) = @_;
                on_finish($self, $tx, $code, $reason);
            }); 
    
            $tx->on(json => sub {
                my ($tx, $msg) = @_;
                on_json($self, $tx, $msg);
            });
    
            # This is the main loop - It handles all incoming messages from the server.
            $tx->on(message => sub {
                my ($tx, $msg) = @_;
                on_message($self, $tx, $msg);
            });        
        });

    } while ( $reconnect and !defined $self->{'tx'} );
}

# For manually disconnecting the connection
sub gw_disconnect
{
    my ($self, $reason) = @_;

    $reason = "No reason specified." unless defined $reason;

    my $tx = $self->{'tx'};
    say localtime(time) . " Closing Websocket: $reason" if $self->{'verbose'};
    defined $tx ? $tx->finish : on_finish($self, $tx, $reason);
}

# Finish the $tx if the connection is closed
sub on_finish
{
    my ($self, $tx, $code, $reason) = @_;
    my $callbacks = $self->{'callbacks'};

    $reason = $close{$code} if ( defined $code and (!defined $reason or length $reason == 0) and exists $close{$code} );
    $reason = "Unknown" unless defined $reason and length $reason > 0;
    say localtime(time) . " Websocket Connection Closed with Code $code ($reason)";
    $tx->finish if defined $tx;
    undef $tx;
    undef $self->{'tx'};

    # Remove the heartbeat timer loop
    Mojo::IOLoop->remove($self->{'heartbeat_loop'});
    undef $self->{'heartbeat_loop'};

    # Send the code and reason to the on_finish callback, if the user defined one.
    $callbacks->{'on_finish'}->({'code' => $code, 'reason' => $reason}) if exists $callbacks->{'on_finish'};

    # Block reconnect for specific codes.
    $self->{'allow_resume'} = 0 if exists $no_resume{$code};

    # If configured to reconnect on disconnect automatically, do so.
    if ( $self->{'reconnect'} )
    {
        if ( $self->{'allow_resume'} )
        {
            say localtime(time) . " Reconnecting and resuming previous session..." if $self->{'verbose'};
            Mojo::IOLoop->timer(10 => sub { gw_resume($self) });
        }
        else
        {
            say localtime(time) . " Reconnecting and starting a new session..." if $self->{'verbose'};
            Mojo::IOLoop->timer(10 => sub { gw_connect($self, gateway($self)) });
        }
    }
    else
    {
        say localtime(time) . " Automatic Reconnect is disabled." if $self->{'verbose'};
    }
}

# Not to be confused with on_create_message, this one handles the Websocket Event, not the Discord Gateway Event.
# on_json and on_message both receive the same events, but on_json gets nothing if the event is compressed
# So we only handle uncompressed events, letting on_message handle the compressed ones.
# Reason being, Compress::Zlib doesn't like wide chars in the uncompress call, but the on_json event handles them fine.
sub on_message 
{
    my ($self, $tx, $msg) = @_;

    my $decode = guess_encoding($msg);
    if ( ref($decode) ne 'Encode::utf8' )
    {
        # If the message is compressed with zlib, uncompress it first.
        my $uncompressed = uncompress($msg);
        if ( defined $uncompressed )
        {
            # This message was compressed! We should handle it, because on_json won't be able to.
             
            # Decode the JSON message into a perl structure
            my $hash = decode_json($uncompressed);
    
            handle_event($self, $tx, $hash);
        }
    }
}

# This one is easy. $msg comes in as a perl hash already, so all we do is pass it on to handle_event as-is.
sub on_json
{
    my ($self, $tx, $msg) = @_;

    handle_event($self, $tx, $msg) if defined $msg;
}

# on_message and on_json are just going to pass perl hashes to this function, which will store the sequence number, optionally print some info, and then pass the data hash on to the callback function.
sub handle_event
{
    my ($self, $tx, $hash) = @_;

    my $op = $hash->{'op'};
    my $t = $hash->{'t'} if defined $hash->{'t'};
    my $s = $hash->{'s'} if defined $hash->{'s'};

    my $op_msg = "OP " . $op; 
    $op_msg .= " SEQ " . $s if defined $s;
    $op_msg .= " " . $t if defined $t;

    say localtime(time) . " " . $op_msg if ($self->{'verbose'});
            
    $self->{'s'} = $s if defined $s;    # Update the latest Sequence Number.

    # Call the relevant handler
    if ( defined $t and exists $handlers{$op}{$t} )
    {
        $handlers{$op}{$t}->{'func'}->($self, $tx, $hash);    # Call the handler function
    }
    elsif ( !defined $t and exists $handlers{$op} )
    {
        $handlers{$op}->{'func'}->($self, $tx, $hash);
    }
    # Else - unhandled event
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
        "compress" => \1, 
        "large_threshold" => 50
    };

    say localtime(time) . " OP 2 SEQ 0 IDENTIFY" if $self->{'verbose'};
    send_op($self, $op, $d);
}

# This has to be sent after reconnecting
sub send_resume
{
    my ($self, $tx) = @_;

    my $op = 6;
    my $s = $self->{'s'};
    my $d = {
        "token"         => $self->{'token'},
        "session_id"    => $self->{'session_id'},
        "seq"           => $self->{'s'}
    };

    say localtime(time) . " OP $op SEQ $s RESUME" if $self->{'verbose'};
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
    $self->{'session_id'} = $hash->{'d'}{'session_id'};

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

    $self->{'allow_resume'} = 0; # Have to establish a new session for this.
    gw_disconnect($self, "Invalid Session.");
}

sub on_hello
{
    my ($self, $tx, $hash) = @_;

    # The Hello packet gives us our heartbeat interval, so we can start sending those.
    $self->{'heartbeat_interval'} = $hash->{'d'}{'heartbeat_interval'} / 1000;
    $self->{'heartbeat_loop'} = Mojo::IOLoop->recurring( $self->{'heartbeat_interval'},
        sub {
            my $op = 1;
            my $d = $self->{'s'};
            say localtime(time) . " OP 1 SEQ " . $self->{'s'} . " HEARTBEAT" if $self->{'verbose'};
            $self->{'heartbeat_check'}++;
            send_op($self, $op, $d);
        }
    );


}

sub on_heartbeat_ack
{
    my ($self, $tx, $hash) = @_;

    say localtime(time) . " OP 11 SEQ " . $self->{'s'} . " HEARTBEAT ACK";
    $self->{'heartbeat_check'}--;
}

1;
