package Mojo::Discord::Gateway;
use feature 'say';
our $VERSION = '0.001';

use Moo;
use strictures 2;

extends 'Mojo::Discord';
with 'Role::EventEmitter';

use Mojo::UserAgent;
use JSON::MaybeXS;
use Mojo::IOLoop;
use Mojo::Discord::User;
use Mojo::Discord::Guild;
use Mojo::Discord::REST;
use Compress::Zlib;
use Encode::Guess;
use Time::Duration;

use namespace::clean;

has handlers => ( is => 'ro', default => sub {
        {
            '0'     => \&on_dispatch,
            '9'     => \&on_invalid_session,
            '10'    => \&on_hello,
            '11'    => \&on_heartbeat_ack,
        } 
    }
);

has dispatches => ( is => 'ro', default => sub {
    {
        'TYPING_START'                 => \&dispatch_typing_start,
        'MESSAGE_CREATE'               => \&dispatch_message_create,
        'MESSAGE_UPDATE'               => \&dispatch_message_update,
        'MESSAGE_DELETE'               => \&dispatch_message_delete,
        'MESSAGE_REACTION_ADD'         => \&dispatch_message_reaction_add,
        'MESSAGE_REACTION_REMOVE'      => \&dispatch_message_reaction_remove,
        'MESSAGE_REACTION_REMOVE_ALL'  => \&dispatch_message_reaction_remove_all,
        'GUILD_CREATE'                 => \&dispatch_guild_create,
        'GUILD_UPDATE'                 => \&dispatch_guild_update,
        'GUILD_DELETE'                 => \&dispatch_guild_delete,
        'GUILD_MEMBER_ADD'             => \&dispatch_guild_member_add,
        'GUILD_MEMBER_UPDATE'          => \&dispatch_guild_member_update,
        'GUILD_MEMBER_REMOVE'          => \&dispatch_guild_member_remove,
        'GUILD_MEMBERS_CHUNK'          => \&dispatch_guild_members_chunk,
        'GUILD_EMOJIS_UPDATE'          => \&dispatch_guild_emojis_update,
        'GUILD_ROLE_CREATE'            => \&dispatch_guild_role_create,
        'GUILD_ROLE_UPDATE'            => \&dispatch_guild_role_update,
        'GUILD_ROLE_DELETE'            => \&dispatch_guild_role_delete,
        'USER_SETTINGS_UPDATE'         => \&dispatch_user_settings_update,
        'USER_UPDATE'                  => \&dispatch_user_update,
        'CHANNEL_CREATE'               => \&dispatch_channel_create,
        'CHANNEL_MODIFY'               => \&dispatch_channel_modify,
        'CHANNEL_DELETE'               => \&dispatch_channel_delete,
        'PRESENCE_UPDATE'              => \&dispatch_presence_update,
        'WEBHOOKS_UPDATE'              => \&dispatch_webhooks_update,
        'READY'                        => \&dispatch_ready,
        'SESSIONS_REPLACE'             => \&dispatch_sessions_replace,
        # More as needed
    }
});

# Websocket Close codes defined in RFC 6455, section 11.7.
# Also includes some Discord-specific codes from the Discord API Reference Docs (Starting at 4000)
has close_codes => ( is => 'ro', default => sub {
    {
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
        '4001'  => 'Invalid Opcode or Payload',
        '4002'  => 'Decode Error',
        '4003'  => 'Not Authenticated',
        '4004'  => 'Authentication Failed',
        '4005'  => 'Already Authenticated',
        '4007'  => 'Invalid Sequence',
        '4008'  => 'Rate Limited',
        '4009'  => 'Session Timeout',
        '4010'  => 'Invalid Shard'
    }
});

# Prevent sending a reconnect following certain codes.
# This always requires a new session to be established if these codes are encountered.
# Not sure if 1000 and 1001 require this, but I don't think it hurts to include them.
has no_resume => ( is => 'ro', default => sub {
    {
        '1000' => 'Normal Closure',
        '1001' => 'Going Away',
        '1009' => 'Message Too Big',
        '1011' => 'Internal Server Err',
        '1012' => 'Service Restart',
        '4003' => 'Not Authenticated',
        '4007' => 'Invalid Sequence',
        '4009' => 'Session Timeout',
        '4010' => 'Invalid Shard'
    } 
});

has token               => ( is => 'ro' );
has name                => ( is => 'rw', required => 1 );
has url                 => ( is => 'rw', required => 1 );
has version             => ( is => 'ro', required => 1 );
has auto_reconnect      => ( is => 'rw' );
has id                  => ( is => 'rw' );
has username            => ( is => 'rw' );
has avatar              => ( is => 'rw' );
has discriminator       => ( is => 'rw' );
has session_id          => ( is => 'rw' );
has s                   => ( is => 'rw' );
has websocket_url       => ( is => 'rw' );
has tx                  => ( is => 'rw' );
has heartbeat_interval  => ( is => 'rw' );
has heartbeat_loop      => ( is => 'rw' );
has heartbeat           => ( is => 'rw', default => 2 );
has base_url            => ( is => 'ro', default => 'https://discord.com/api' );
has gateway_url         => ( is => 'rw', default => sub { shift->base_url . '/gateway' });
has gateway_version     => ( is => 'ro', default => 6 );
has gateway_encoding    => ( is => 'ro', default => 'json' );
has max_websocket_size  => ( is => 'ro', default => 1048576 ); # Should this maybe be a config.ini value??
has agent               => ( is => 'lazy', builder => sub { my $self = shift; $self->name . ' (' . $self->url . ',' . $self->version . ')' } );
has allow_resume        => ( is => 'rw', default => 1 );
has reconnect_timer     => ( is => 'rw', default => 10 );
has last_connected      => ( is => 'rw', default => 0 );
has last_disconnect     => ( is => 'rw', default => 0 );
has ua                  => ( is => 'lazy', builder => sub { 
    my $self = shift;

    my $ua = Mojo::UserAgent->new->with_roles('+Queued');

    $ua->transactor->name($self->agent);
    $ua->inactivity_timeout(120);
    $ua->connect_timeout(5);
    $ua->max_active(1);

    $ua->on(start => sub {
       my ($ua, $tx) = @_;
       $tx->req->headers->authorization($self->token);
    });

    return $ua;
});
has guilds              => ( is => 'rw', default => sub { {} } );
has channels            => ( is => 'rw', default => sub { {} } );
has users               => ( is => 'rw', default => sub { {} } );
has webhooks            => ( is => 'rw', default => sub { {} } );
has rest                => ( is => 'rw' );
has log                 => ( is => 'ro' );

# This updates the client status
# Takes a hashref with bare minimum 'name' specified. That is the name of the currently playing game or song or whatever.
# Type is
# 0 = Playing
# 1 = Streaming
# 2 = Listening to
# 3 = Watching
sub status_update
{
    my ($self, $param) = @_;

    my $op = 3;
    my $d = {};

    $d->{'afk'} = $param->{'afk'} // 0;
    $d->{'since'} = $param->{'since'} // undef;
    $d->{'status'} = $param->{'status'} // "online";
    
    $d->{'game'}{'name'} = $param->{'name'} // undef;
    $d->{'game'}{'type'} = $param->{'type'} // 0;
    $d->{'game'}{'details'} = $param->{'details'} // undef;
    $d->{'game'}{'state'} = $param->{'state'} // undef;

    $self->send_op($op, $d);
}

# This retrieves and returns Gateway URL for connecting to Discord. 
sub gateway
{
    my $self = shift;
    my $url = $self->gateway_url;
    my $ua = $self->ua;
    my $tx = $ua->get($url);    # Fetch the Gateway WS URL

    # Store the URL in $self
    if (defined $tx and defined $tx->res->json and defined $tx->res->json->{'url'})
    {
        $self->websocket_url($tx->res->json->{'url'});
    }
    else
    {
        $self->log->error("[Gateway.pm] [gateway] Could not retrieve Gateway URL from '$url'");
        $self->log->debug(Data::Dumper->Dump([$tx->res->error], ['error']));
        return undef; 
    }

    $self->log->debug("[Gateway.pm] [gateway] Gateway URL: " . $tx->res->json->{'url'});
    return $tx->res->json->{'url'}; # Return the URL field from the JSON response
}

# Check that we have a valid connection to Discord, return boolean
sub connected
{
    my $self = shift;
    my $log = $self->log;
    my $tx = $self->tx;

    unless ( defined $tx )
    {
        $log->debug('[Gateway.pm] [connected] $tx is not defined');
        return 0;
    }

    unless ( $tx->is_websocket )
    {
        $log->debug('[Gateway.pm] [connected] $tx is not a websocket');
        return 0;
    }

    if ( $tx->error )
    {
        $log->debug('[Gateway.pm] [connected] $tx has an error: ' . Data::Dumper->Dump([$tx->error], ['error']));
        return 0;
    }

    if ( $tx->is_finished )
    {
        $log->debug('[Gateway.pm] [connected] $tx is finished');
        return 0;
    }

    unless ( $self->heartbeat )
    {
        $log->debug('[Gateway.pm] [connected] Heartbeat not present (' . $self->heartbeat . ')');
        return 0;
    }

    # If all of the above passes, we should have confidence that we are connected to Discord and can send packets.
    return 1;
}

# This sub is used for sending messages to the gateway.
# It takes an OP code, optional Sequence and Type, and a Data hashref to pass in.
# The arguments are put together into a hashref and then JSON encoded for delivery over the websocket.
sub send_op
{
    my ($self, $op, $d, $s, $t) = @_;

    die ("Cannot send OP - Client is not connected") unless $self->connected();

     my $package = {
        'op' => int($op), # Ensure JSON::MaybeXS encodes this as an integer, not a string. Discord will reject string opcodes.
        'd' => $d
    };

    $package->{'s'} = $s if defined $s;
    $package->{'t'} = $t if defined $t;

    $self->connected;

    my $tx = $self->tx;

    # Seems Discord parses JSON incorrectly when it contains unicode
    # JSON::MaybeXS works with the ascii option to escape unicode characters.
    my $json = JSON::MaybeXS->new(
        utf8 => 1, 
        ascii => 1, 
        canonical => 1, 
        allow_nonref => 1, 
        allow_unknown => 1, 
        allow_blessed => 1, 
        convert_blessed => 1
        )->encode($package);

    $self->log->debug("[Gateway.pm] [send_op] Sent: $json");
    $tx->send($json);
}

# This is pretty much just a stub for connect that calls it with the reconnect parameter, triggering a RESUME instead of an IDENT after connecting.
sub gw_resume
{
    my ($self) = @_;

    $self->log->info('[Gateway.pm] [gw_resume] Reconnecting');
    $self->gw_connect('resume' => 1);
};

# This sub establishes a connection to the Discord Gateway web socket
# WS URL must be passed in.
# Optionally pass in a boolean $reconnect (1 or 0) to tell connect whether to send an IDENTIFY or a RESUME
sub gw_connect
{
    my ($self, %args) = @_;
    my $resume = $args{'resume'} // 0;
    $self->log->debug('[Gateway.pm] [gw_connect] Resume? ' . $resume);

    my $url = $self->gateway();
    $self->reconnect() unless defined $url;

    $url .= "?v=" . $self->gateway_version . "&encoding=" . $self->gateway_encoding;
    $self->log->debug('[Gateway.pm] [gw_connect] Connecting to ' . $url);

    $self->ua->websocket($url => { 'Sec-WebSocket-Extensions' => 'permessage-deflate' } => sub
    {
        my ($ua, $tx) = @_;
        $self->tx($tx);

        unless ($self->connected)
        {
            $self->log->error('[Gateway.pm] [gw_connect] Websocket Handshake Failed');
            $self->log->debug('[Gateway.pm] [gw_connect] ' . Data::Dumper->Dump([$tx], ['tx']));
            $self->on_finish('Websocket Handshake Failed');
            return;
        }

        # Large servers send large packets of information listing their channels and other attributes.
        # By default Mojo sets a max message length of 256KiB, and anything larger triggers it to close the
        # connection with code 1009 - Message Too Long.
        # We can up the length here or by setting the MOJO_MAX_WEBSOCKET_SIZE environment variable.
        $tx->max_websocket_size($self->max_websocket_size);
        
        $self->log->info('[Gateway.pm] [gw_connect] WebSocket Connection Established');
        $self->heartbeat(2); # Always make sure this is set to 2 on a new connection.
        
        # If this is a new connection, send OP 2 IDENTIFY
        # If we are reconnecting, send OP 6 RESUME
        ($resume and $self->auto_reconnect and $self->allow_resume ) ? 
            send_resume($self, $tx) : send_ident($self, $tx);
        
        # Reset the state of allow_resume now that we have reconnected.
        $self->allow_resume(1);

        # This should fire if the websocket closes for any reason.
        $self->tx->on(finish => sub {
            my ($tx, $code, $reason) = @_;
            $self->on_finish($code, $reason);
        }); 
        
        $self->tx->on(json => sub {
            my ($tx, $msg) = @_;
            $self->on_json($tx, $msg);
        });
        
        # This is the main loop - It handles all incoming messages from the server.
        $self->tx->on(message => sub {
            my ($tx, $msg) = @_;
            $self->on_message($tx, $msg);
        });
    });
};

# For manually disconnecting the connection
sub gw_disconnect
{
    my ($self, $reason) = @_;

    $reason = "No reason specified." unless defined $reason;

    my $tx = $self->tx;
    $self->log->info('[Gateway.pm] [gw_disconnect] Closing websocket with reason: ' . $reason);
    $tx->finish;
}

# Finish the $tx if the connection is closed
sub on_finish
{
    my ($self, $code, $reason) = @_;
    my $close = $self->close_codes; # Close codes

    # Track the time we disconnected so we can calculate the connection uptime
    $self->last_disconnect(time);

    unless (defined $self->tx)
    {
        $self->log->fatal('[Gateway.pm] [on_finish] $tx is undefined');
        die('on_finish has undefined $tx - Cannot recover');
    }

    $reason = $close->{$code} if ( defined $code and (!defined $reason or length $reason == 0) and exists $close->{$code} );
    $reason = "Unknown" unless defined $reason and length $reason > 0;
    $self->log->info('[Gateway.pm] [on_finish] Websocket connection closed with Code ' . Data::Dumper->Dump([$code], ['code']) . ' (' . $reason . ')');

    $self->log->debug('[Gateway.pm] [on_finish] Removing heartbeat timer');
    Mojo::IOLoop->remove($self->heartbeat_loop) if defined $self->heartbeat_loop;
    $self->heartbeat_loop(undef);;

    # Block reconnect for specific codes.
    my $no_resume = $self->no_resume;
    $self->allow_resume(0) if exists $no_resume->{$code};

    $self->reconnect();
}

sub reconnect
{
    my $self = shift;

    # If configured to reconnect on disconnect automatically, do so.
    if ( $self->auto_reconnect )
    {
        $self->log->debug('[Gateway.pm] [reconnect] Automatic reconnect is enabled.');

        if ( $self->allow_resume )
        {
            $self->log->info('[Gateway.pm] [reconnect] Reconnecting and resuming previous session.');
            Mojo::IOLoop->timer($self->reconnect_timer => sub { $self->gw_connect('resume' => 1) });
        }
        else
        {
            $self->log->info('[Gateway.pm] [reconnect] Reconnecting and starting a new session.');
            Mojo::IOLoop->timer($self->reconnect_timer => sub { $self->gw_connect('resume' => 0) });
        }

        $self->reconnect_timer( $self->reconnect_timer*2 ); # Double the timer each time we attempt to reconnect.
        $self->log->debug("[Gateway.pm] [reconnect] Reconnect timer increased to " . $self->reconnect_timer . " seconds");
    }
    else
    {
        $self->log->info('[Gateway.pm] [reconnect] Automatic reconnect is disabled.');
    }
}

# This one handles the Websocket Event, not the Discord Gateway Event.
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
    
            $self->handle_event($tx, $hash);
        }
    }
}

# This one is easy. $msg comes in as a perl hash already, so all we do is pass it on to handle_event as-is.
sub on_json
{
    my ($self, $tx, $msg) = @_;

    $self->handle_event($tx, $msg) if defined $msg;
}

# on_message and on_json are just going to pass perl hashes to this function, which will store the sequence number, optionally print some info, and emit an event
sub handle_event
{
    my ($self, $tx, $hash) = @_;

    my $op = $hash->{'op'};
    my $t = $hash->{'t'} if defined $hash->{'t'};
    my $s = $hash->{'s'} if defined $hash->{'s'};

    my $op_msg = "OP " . $op; 
    $op_msg .= " SEQ " . $s if defined $s;
    $op_msg .= " " . $t if defined $t;

    $self->s($s) if defined $s;    # Update the latest Sequence Number.

    if ( exists $self->handlers->{$op} )
    {
        $self->handlers->{$op}->($self, $tx, $hash);
    }
    else
    {
        $self->log->warn('[Gateway.pm] [handle_event] Unhandled Event: ' . $op_msg);
    }
}

# Dispatch sends events to the client's listener functions if defined
sub dispatch
{
    my ($self, $type, $data) = @_;

    if ( exists $self->dispatches->{$type} )
    {
        $self->dispatches->{$type}->($self, $data);
    }
    else
    {
        $self->log->debug('[Gateway.pm] [dispatch] Unhandled dispatch event: ' . $type);
    }
}

# This has to be sent after connecting in order to receive a READY Packet.
sub send_ident
{
    my ($self, $tx) = @_;

    my $op = 2;
    my $d = {
        "token" => $self->token, 
        "properties" => { 
            '$os' => $^O, 
            '$browser' => $self->name, 
            '$device' => $self->name, 
            '$referrer' => "", 
            '$referring_domain' => ""
        }, 
        "compress" => \1, 
        "large_threshold" => 50
    };

    $self->log->debug('[Gateway.pm] [send_ident] Sending OP $op SEQ 0 IDENTIFY');
    $self->send_op($op, $d);
}

# This has to be sent after reconnecting
sub send_resume
{
    my ($self, $tx) = @_;

    my $op = 6;
    my $s = $self->s;
    my $d = {
        "token"         => $self->token,
        "session_id"    => $self->session_id,
        "seq"           => $self->s
    };

    $self->log->debug('[Gateway.pm] [send_resume] Sending OP $op SEQ $s RESUME');
    $self->send_op($op, $d);
}

sub on_dispatch # OPCODE 0
{
    my ($self, $tx, $hash) = @_;

    my $t = $hash->{'t'};   # Type
    my $d = $hash->{'d'};   # Data

    $self->dispatch($t, $d); # Library's own handlers
    $self->emit($t, $d);     # Event emitter for client
}

sub dispatch_ready
{
    my ($self, $hash) = @_;

    # Capture the session ID so we can RESUME if we lose connection
    $self->session_id($hash->{'session_id'});
    $self->log->debug('[Gateway.pm] [dispatch_ready] Session ID: ' . $self->session_id);

    # Reset reconnect timer if the bot had been connected for at least a minute
    my $elapsed = $self->last_disconnect - $self->last_connected;
    $self->log->debug('[Gateway.pm] [dispatch_ready] Last connection uptime: ' . duration($elapsed));
    if ( $elapsed >= 60 )
    {
        $self->reconnect_timer(10);
        $self->last_connected(time);
    }

    $self->log->info('[Gateway.pm] [dispatch_ready] Discord gateway is ready');
}

sub dispatch_typing_start
{
}

sub dispatch_message_create
{
   my ($self, $hash) = @_;
   my $id = $hash->{'author'}{'id'};
   # Update what we know about people when they talk.
   $self->add_user($hash->{'author'}) unless exists $self->users->{id};
}

sub dispatch_message_update
{
}

sub dispatch_message_delete
{
}

sub dispatch_message_reaction_add
{
}

sub dispatch_message_reaction_remove
{
}

sub dispatch_message_reaction_remove_all
{
}

sub dispatch_sessions_replace
{
    my ($self, $hash) = @_;

    $self->log->debug('SESSIONS_REPLACE payload:');
    $self->log->debug(Data::Dumper->Dump([$hash], ['hash']));
}

# Create the new Guild object and return it
# Takes a Discord Guild hash
# returns a Mojo::Discord::Guild object.
#
# The _create_guild function doesn't actually do much work on its own.
# It really just creates the new Guild object and passes it to _update_guild
# to be populated.
sub _create_guild
{
    my ($self, $hash) = @_;

    my $guild = Mojo::Discord::Guild->new();
    $self->_update_guild($guild, $hash);

    return $guild;
}

# Break out the parts of the provided hash from discord and
# add/update the passed-in guild object with it.
sub _update_guild
{
    my ($self, $guild, $hash) = @_;

    $self->_set_guild_top_level($guild, $hash);
    $self->_set_guild_channels($guild, $hash);
    $self->_set_guild_roles($guild, $hash);
    $self->_set_guild_presences($guild, $hash);
    $self->_set_guild_emojis($guild, $hash);
    $self->_set_guild_members($guild, $hash);
    # TO-DO: features and voice states
}

# Set top level simple guild attributes. 
# You can pass in the entire guild hash safely as
# complex attributes (ie, channels and roles) will be ignored.
sub _set_guild_top_level
{
    my ($self, $guild, $hash) = @_;

    $guild->set_attributes($hash);
}

# This sub adds the channels found in the discord guild hash to the specified guild.
# Takes a Mojo::Discord::Guild object and a discord guild hash
sub _set_guild_channels
{
    my ($self, $guild, $hash) = @_;

    foreach my $channel_hash (@{$hash->{'channels'}})
    {
        # Add the channel
        my $channel = $guild->add_channel($channel_hash);
   
        # Channels requires an extra step
        # Since messages only give you the channel ID we need an easy way to figure out which Guild that channel belongs to
        # so we can look up roles and permissions and stuff without having to iterate through every guild entry every time.
        # Here we will build a "channels" hashref that links Channel IDs to Guild IDs.
        # This way we can do just about any operation with only a channel ID to go on.
        # Create a link from the channel ID to the Guild ID
        $self->channels->{$channel->id} = $guild->id;
    }
}

# Adds roles to a guild object
# Takes a Mojo::Discord::Guild object and a discord guild perl hash.
sub _set_guild_roles
{
    my ($self, $guild, $hash) = @_;

    foreach my $role_hash (@{$hash->{'roles'}})
    {
        my $role = $guild->add_role($role_hash);
    }
}

sub _set_guild_presences
{
    my ($self, $guild, $hash) = @_;

    foreach my $presence_hash (@{$hash->{'presences'}})
    {
        # Presences don't have an id, so we'll use the user ID as the presence ID.
        $presence_hash->{'id'} = $presence_hash->{'user'}->{'id'};

        my $presence = $guild->add_presence($presence_hash);
    }
}

sub _set_guild_emojis
{
    my ($self, $guild, $hash) = @_;
    
    foreach my $emoji_hash (@{$hash->{'emojis'}})
    {
        my $emoji = $guild->add_emoji($emoji_hash);
    }
}

sub _set_guild_members
{
    my ($self, $guild, $hash) = @_;
    
    foreach my $member_hash (@{$hash->{'members'}})
    {
        # Like presences, there is no "member ID" so we'll use the user id instead.
        $member_hash->{'id'} = $member_hash->{'user'}->{'id'};
        my $member = $guild->add_member($member_hash);

        # Now we also want to add the user, but this is not a property of the guild; It's a top level entity.
        my $user_hash = $member_hash->{'user'};
        my $user = $self->add_user($user_hash);
        
    }
}

# We receive this whenever we join a new guild
# but also when we connect and start a new session.
# It includes pretty well everything the server knows about the guild in question.
# This sub creates and stores a Mojo::Discord::Guild object with all of that information.
sub dispatch_guild_create
{
    my ($self, $hash) = @_;
   
    # Parse the hash and create a Mojo::Discord::Guild object
    my $guild = $self->_create_guild($hash);

    # Store it in our guilds hash.
    $self->guilds->{$guild->id} = $guild;

    # To-Do:
    # Check current permissions to see whether or not I can fetch the entire guild's list of webhooks
    # or if I have to go channel by channel
    # (or if I have no webhook access at all)
    # For now, let's just assume we have guild level permission.

    # Get and store this guild's webhooks
    $self->rest->get_guild_webhooks($guild->id, sub
    {
        my $json = shift;
        $self->_set_guild_webhooks($json);
    });
}

sub _set_guild_webhooks
{
    my ($self, $json) = @_;

    if ( ref $json ne 'ARRAY' )
    {
        say "\tCannot query guild webhooks: " . $json->{'message'} . " (" . $json->{'code'} . ")";
        return;
    }

    # This returns an array of hooks, so we have to look at the channel_id field and build our own arrays.
    foreach my $hook (@$json)
    {
        my $cid = $hook->{'channel_id'};
        push @{$self->webhooks->{$cid}}, $hook;
        #say "\tHas Webhook: " . $cid . " -> " . $hook->{'name'};
    }
}

# We receive this when someone makes changes to their guild configuration.
# It contains a partial guild payload.
# We can reuse basically all of the same functions used to create a guild.
# The only diffrence is we start by looking up the existing guild object 
# instead of creating a new one.
sub dispatch_guild_update
{
    my ($self, $hash) = @_;

    my $gid = $hash->{'id'}; # Guild ID
    my $guild = $self->guilds->{$gid}; # Guild object

    # Populate the updated info
    $self->_update_guild($guild, $hash);
}

sub dispatch_guild_delete
{
    my ($self, $hash) = @_;

    # say Dumper($hash);

    # Probably just passes an ID, then find and delete that guild object.
}

sub dispatch_guild_member_add
{
    my ($self, $hash) = @_;

    # say Dumper($hash);

    # Should be able to just call self->set_members.... or guild->add_member
}

sub dispatch_guild_member_update
{
    my ($self, $hash) = @_;

    # say Dumper($hash);

}

sub dispatch_guild_member_remove
{
    my ($self, $hash) = @_;

    # say Dumper($hash);
}

sub dispatch_guild_members_chunk
{
    my ($self, $hash) = @_;

    #  say Dumper($hash);
} 

sub dispatch_guild_emojis_update{}
sub dispatch_guild_role_create{}
sub dispatch_guild_role_update{}
sub dispatch_guild_role_delete{}
sub dispatch_user_settings_update{}
sub dispatch_user_update{}
sub dispatch_channel_create{}
sub dispatch_channel_modify{}
sub dispatch_channel_delete{}
sub dispatch_presence_update{}

sub dispatch_webhooks_update
{
    my ($self, $hash) = @_;

    my $rest = $self->rest;
    my $channel = $hash->{'channel_id'};

    # Delete the current list of webhooks for this channel
    delete $self->webhooks->{$channel};

    # And request the most up to date ones from the REST interface.
    $rest->get_channel_webhooks($channel, sub
    {
        # Store them as-is.
        $self->webhooks->{$channel} = shift;
    });
}

# There is no dispatch event for this. Rather, discord makes you aware of new users
# through various guild events. Any time we are made aware of a potentially new user
# we should call this function.
sub add_user
{
    my ($self, $args) = @_;

    die("Cannot add a user without an ID.\nDied ") unless defined $args->{'id'};

    my $id = $args->{'id'};
    my $user = Mojo::Discord::User->new($args);

    # Make the bot aware of this user.
    $self->users->{$id} = $user;

    # Return the new user object to the caller.
    return $user;
}

sub on_invalid_session
{
    my ($self, $tx, $hash) = @_;
    my $t = $hash->{'t'};   # Type
    my $d = $hash->{'d'};   # Data
 
    $self->allow_resume(0); # Have to establish a new session for this.
    $self->gw_disconnect("Invalid Session.");
}

sub on_hello
{
    my ($self, $tx, $hash) = @_;

    # The Hello packet gives us our heartbeat interval, so we can start sending those.
    $self->heartbeat_interval( $hash->{'d'}{'heartbeat_interval'} / 1000 );
    $self->heartbeat_loop( Mojo::IOLoop->recurring( $self->heartbeat_interval,
        sub {
            my $op = 1;
            my $d = $self->s;
            $self->log->debug('[Gateway.pm] [on_hello] Sending OP ' . $op . ' SEQ ' . $self->s . ' HEARTBEAT');
            $self->heartbeat($self->heartbeat-1);
            $self->send_op($op, $d);
        }
    ));
}

sub on_heartbeat_ack
{
    my ($self, $tx, $hash) = @_;

    $self->log->debug('[Gateway.pm] [on_heartbeat_ack] Received OP 11 SEQ ' . $self->s . ' HEARTBEAT ACK');
    $self->heartbeat($self->heartbeat+1);
}

1;
