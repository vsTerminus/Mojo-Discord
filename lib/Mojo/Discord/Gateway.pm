package Mojo::Discord::Gateway;
use feature 'say';
our $VERSION = '0.001';

use Moo;
use strictures 2;

extends 'Mojo::Discord';

use Mojo::UserAgent;
use JSON::MaybeXS;
use Mojo::IOLoop;
use Mojo::Discord::User;
use Mojo::Discord::Guild;
use Compress::Zlib;
use Encode::Guess;
use Data::Dumper;

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
        'TYPING_START'          => \&dispatch_typing_start,
        'MESSAGE_CREATE'        => \&dispatch_message_create,
        'MESSAGE_UPDATE'        => \&dispatch_message_update,
        'MESSAGE_DELETE'        => \&dispatch_message_delete,
        'GUILD_CREATE'          => \&dispatch_guild_create,
        'GUILD_UPDATE'          => \&dispatch_guild_update,
        'GUILD_DELETE'          => \&dispatch_guild_delete,
        'GUILD_MEMBER_ADD'      => \&dispatch_guild_member_add,
        'GUILD_MEMBER_UPDATE'   => \&dispatch_guild_member_update,
        'GUILD_MEMBER_REMOVE'   => \&dispatch_guild_member_remove,
        'GUILD_MEMBERS_CHUNK'   => \&dispatch_guild_members_chunk,
        'GUILD_EMOJIS_UPDATE'   => \&dispatch_guild_emojis_update,
        'GUILD_ROLE_CREATE'     => \&dispatch_guild_role_create,
        'GUILD_ROLE_UPDATE'     => \&dispatch_guild_role_update,
        'GUILD_ROLE_DELETE'     => \&dispatch_guild_role_delete,
        'USER_SETTINGS_UPDATE'  => \&dispatch_user_settings_update,
        'USER_UPDATE'           => \&dispatch_user_update,
        'CHANNEL_CREATE'        => \&dispatch_channel_create,
        'CHANNEL_MODIFY'        => \&dispatch_channel_modify,
        'CHANNEL_DELETE'        => \&dispatch_channel_delete,
        'PRESENCE_UPDATE'       => \&dispatch_presence_update,
        'WEBHOOKS_UPDATE'       => \&dispatch_webhooks_update,
        # More as needed
    }
});

# Websocket Close codes defined in RFC 6455, section 11.7.
# Also includes some Discord-specific codes from the Discord API Reference Docs (Starting at 4000)
has close => ( is => 'ro', default => sub {
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
        '4001'  => 'Unknown Opcode',
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
        '4007' => 'Invalid Sequence',
        '4009' => 'Session Timeout',
        '4010' => 'Invalid Shard'
    } 
});

has token               => ( is => 'ro' );
has name                => ( is => 'rw', required => 1 );
has url                 => ( is => 'rw', required => 1 );
has version             => ( is => 'ro', required => 1 );
has callbacks           => ( is => 'rw' );
has verbose             => ( is => 'rw' );
has reconnect           => ( is => 'rw' );
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
has heartbeat_check     => ( is => 'rw', default => 0 );
has connected           => ( is => 'rw', default => 0 );
has base_url            => ( is => 'ro', default => 'https://discordapp.com/api' );
has gateway_url         => ( is => 'rw', default => sub { shift->base_url . '/gateway' });
has gateway_version     => ( is => 'ro', default => 6 );
has gateway_encoding    => ( is => 'ro', default => 'json' );
has agent               => ( is => 'rw' );
has allow_resume        => ( is => 'rw', default => 1 );
has ua                  => ( is => 'rw', default => sub { Mojo::UserAgent->new } );
has guilds              => ( is => 'rw', default => sub { {} } );
has channels            => ( is => 'rw', default => sub { {} } );
has users               => ( is => 'rw', default => sub { {} } );

sub BUILD
{ 
    my $self = shift;
    
    $self->agent( $self->name . ' (' . $self->url . ',' . $self->version . ')' );
    
    $self->ua->transactor->name($self->agent);
    $self->ua->inactivity_timeout(120);
    $self->ua->connect_timeout(5);
    $self->ua->on(start => sub {
       my ($ua, $tx) = @_;
       $tx->req->headers->authorization($self->token);
    });
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
        say Dumper($tx->res->error);
        die("Could not retrieve Gateway URL from '$url'");
    }

    return $tx->res->json->{'url'}; # Return the URL field from the JSON response
}

# This sub is used for sending messages to the gateway.
# It takes an OP code, optional Sequence and Type, and a Data hashref to pass in.
# The arguments are put together into a hashref and then JSON encoded for delivery over the websocket.
sub send_op
{
    my ($self, $op, $d, $s, $t) = @_;

    my $tx = $self->tx;

    if ( !defined $tx ) 
    {
        say localtime(time) . " (send_op) \$tx is undefined. Closing connection with Code 4009: Timeout";
        $self->on_finish($tx, 4009, "Connection Timeout");
        return;
    }
    elsif ( $self->heartbeat_check > 1 ) 
    {
        say localtime(time) . " (send_op) Failed heartbeat check. Closing connection with Code 4009: Heartbeat Failure";
        $self->on_finish($tx, 4009, "Timeout: Heartbeat Failure");
        return;
    } 

    my $package = {
        'op' => $op,
        'd' => $d
    };

    $package->{'s'} = $s if defined $s;
    $package->{'t'} = $t if defined $t;

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

    say localtime(time) . " " . $json if $self->verbose;

    $tx->send($json);
}

# This is pretty much just a stub for connect that calls it with the reconnect parameter, triggering a RESUME instead of an IDENT after connecting.
sub gw_resume
{
    my ($self) = @_;

    $self->gw_connect($self->gateway(), 1);
}

# This sub establishes a connection to the Discord Gateway web socket
# WS URL must be passed in.
# Optionally pass in a boolean $reconnect (1 or 0) to tell connect whether to send an IDENTIFY or a RESUME
sub gw_connect
{
    my ($self, $url, $reconnect) = @_;

    my $ua = $self->ua;

    # Add URL Params 
    $url .= "?v=" . $self->gateway_version . "&encoding=" . $self->gateway_encoding;

    say localtime(time) . ' Connecting to ' . $url if $self->verbose;

    $ua->websocket($url => sub {
        my ($ua, $tx) = @_;
        unless ($tx->is_websocket)
        {
            $self->on_finish(-1, 'Websocket Handshake Failed');
#            $self->{'tx'} = undef;
#            say localtime(time) . ' WebSocket handshake failed!';
            return;
        }
    
        say localtime(time) . ' WebSocket Connection Established.' if $self->verbose;
        $self->heartbeat_check(0); # Always make sure this is set to 0 on a new connection.
        $self->tx($tx);
    
        # If this is a new connection, send OP 2 IDENTIFY
        # If we are reconnecting, send OP 6 RESUME
        (defined $reconnect and $reconnect and $self->allow_resume) ? send_resume($self, $tx) : send_ident($self, $tx);
    
        # Reset the state of allow_resume now that we have reconnected.
        $self->allow_resume(1);
    
        # This should fire if the websocket closes for any reason.
        $tx->on(finish => sub {
            my ($tx, $code, $reason) = @_;
            $self->on_finish($tx, $code, $reason);
        }); 
    
        $tx->on(json => sub {
            my ($tx, $msg) = @_;
            $self->on_json($tx, $msg);
        });
    
        # This is the main loop - It handles all incoming messages from the server.
        $tx->on(message => sub {
            my ($tx, $msg) = @_;
            $self->on_message($tx, $msg);
        });        
    });
}

# For manually disconnecting the connection
sub gw_disconnect
{
    my ($self, $reason) = @_;

    $reason = "No reason specified." unless defined $reason;

    my $tx = $self->tx;
    say localtime(time) . " (gw_disconnect) Closing Websocket: $reason" if $self->verbose;
    defined $tx ? $tx->finish : $self->on_finish($tx, 9001, $reason);
}

# Finish the $tx if the connection is closed
sub on_finish
{
    my ($self, $tx, $code, $reason) = @_;
    my $callbacks = $self->callbacks;
    my %close = $self->close;

    $reason = $close{$code} if ( defined $code and (!defined $reason or length $reason == 0) and exists $close{$code} );
    $reason = "Unknown" unless defined $reason and length $reason > 0;
    say localtime(time) . " (on_finish) Websocket Connection Closed with Code $code ($reason)" if $self->verbose;

    $self->connected(0);

    if ( !defined $tx )
    {
        say localtime(time) . " (on_finish) \$tx is unexpectedly undefined." if $self->verbose;
    }
    else
    {
        $tx->finish;
    }


    # Remove the heartbeat timer loop
    # The problem seems to be removing this if $tx goes away on its own.
    # Without being able to call $tx->finish it seems like Mojo::IOLoop->remove doesn't work completely.
    if ( !defined $self->heartbeat_loop)
    {
        say localtime(time) . " (on_finish) Heartbeat Loop variable is unexpectedly undefined.";
    }
    else
    {
        say localtime(time) . " Removing Heartbeat Timer" if $self->verbose;
        Mojo::IOLoop->remove($self->heartbeat_loop) if defined $self->heartbeat_loop;
        undef $self->{'heartbeat_loop'};
    }


    # Send the code and reason to the on_finish callback, if the user defined one.
    $callbacks->{'FINISH'}->({'code' => $code, 'reason' => $reason}) if exists $callbacks->{'FINISH'};
    
    say "Is finished? " . $tx->is_finished if $self->verbose;

    undef $tx;
    $self->tx(undef);

    # Block reconnect for specific codes.
    my %no_resume = $self->no_resume;
    #$self->allow_resume(0) if exists $no_resume->{$code};

    # If configured to reconnect on disconnect automatically, do so.
    if ( $self->reconnect )
    {
        say localtime(time) . " Automatic reconnect is enabled." if $self->verbose;

        if ( $self->allow_resume )
        {
            say localtime(time) . " Reconnecting and resuming previous session in 10 seconds..." if $self->verbose;
            Mojo::IOLoop->timer(10 => sub { $self->gw_connect($self->gateway(), 1) });
        }
        else
        {
            say localtime(time) . " Reconnecting and starting a new session in 10 seconds..." if $self->verbose;
            Mojo::IOLoop->timer(10 => sub { $self->gw_connect($self->gateway()) });
        }
    }
    else
    {
        say localtime(time) . " Automatic Reconnect is disabled." if $self->verbose;
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

    say localtime(time) . " " . $op_msg if ($self->verbose);
            
    $self->s($s) if defined $s;    # Update the latest Sequence Number.

    # Call the relevant handler
    if ( exists $self->handlers->{$op} )
    {
        $self->handlers->{$op}->($self, $tx, $hash);
    }
    # Else - unhandled event
    else
    {
        #say Dumper($hash);
        say localtime(time) . ": Unhandled Event: OP $op" if $self->verbose;
    }
}

sub dispatch
{
    my ($self, $type, $data) = @_;

    if ( exists $self->dispatches->{$type} )
    {
        $self->dispatches->{$type}->($self, $data);
    }
    else
    {
        say localtime(time) . ": Unhandled Dispatch Event: $type" if $self->verbose;
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

    say localtime(time) . " OP 2 SEQ 0 IDENTIFY" if $self->verbose;
    send_op($self, $op, $d);
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

    say localtime(time) . " OP $op SEQ $s RESUME" if $self->verbose;
    send_op($self, $op, $d);
}

# Pass a hashref to a callback function if it exists
sub callback
{
    my ($self, $event, $hash) = @_;
    my $callbacks = $self->callbacks;

    if ( !defined $event )
    {
        say localtime(time) . ": No event defined for callback";
    }
    elsif ( exists $callbacks->{$event} )
    {
        $callbacks->{$event}->($hash);
    }
    else
    {
        say localtime(time) . ": No callback defined for event '$event'" if $self->verbose;
    }
}

sub on_dispatch # OPCODE 0
{
    my ($self, $tx, $hash) = @_;

    my $t = $hash->{'t'};   # Type
    my $d = $hash->{'d'};   # Data

    # Track different information depending on the Dispatch Type
    $self->dispatch($t, $d);

    # Now send the same information to any user-specified Callbacks
    $self->callback($t, $d);
}

sub dispatch_typing_start
{
    
}

sub dispatch_message_create
{
    
}

sub dispatch_message_update
{
}

sub dispatch_message_delete
{
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

    say "Joined a Guild:";
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
        
        say "\tHas Channel: " . $channel->id . " -> " . $channel->name;
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
        say "\tHas Role: " . $role->id . " -> " . $role->name;
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
        say "\tHas Presence: " . $presence->id . " -> " . $presence->status;
    }
}

sub _set_guild_emojis
{
    my ($self, $guild, $hash) = @_;
    
    foreach my $emoji_hash (@{$hash->{'emojis'}})
    {
        my $emoji = $guild->add_emoji($emoji_hash);
        say "\tHas Emoji: " . $emoji->id . " -> " . $emoji->name;
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
        
        say "\tHas Member: " . $member->id . " -> " . $user->username;
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
}

# We receive this when someone makes changes to their guild configuration.
# It contains a partial guild payload.
# We can reuse basically all of the same functions used to create a guild.
# The only diffrence is we start by looking up the existing guild object 
# instead of creating a new one.
sub dispatch_guild_update
{
    my ($self, $hash) = @_;

    #say Dumper($hash);
    say "Guild Update:";

    my $gid = $hash->{'id'}; # Guild ID
    my $guild = $self->guilds->{$gid}; # Guild object

    # Populate the updated info
    $self->_update_guild($guild, $hash);
}

sub dispatch_guild_delete
{
    my ($self, $hash) = @_;

    say Dumper($hash);

    # Probably just passes an ID, then find and delete that guild object.
}

sub dispatch_guild_member_add
{
    my ($self, $hash) = @_;

    say Dumper($hash);

    # Should be able to just call self->set_members.... or guild->add_member
}

sub dispatch_guild_member_update
{
    my ($self, $hash) = @_;

    say Dumper($hash);

}

sub dispatch_guild_member_remove
{
    my ($self, $hash) = @_;

    say Dumper($hash);
}

sub dispatch_guild_members_chunk
{
    my ($self, $hash) = @_;

    say Dumper($hash);
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
sub dispatch_webhooks_update{}

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
#    $self->users($id => $user);
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
    gw_disconnect($self, "Invalid Session.");
    $self->callback($t, $d);
}


sub on_hello
{
    my ($self, $tx, $hash) = @_;

    $self->connected(1);

    # The Hello packet gives us our heartbeat interval, so we can start sending those.
    $self->heartbeat_interval( $hash->{'d'}{'heartbeat_interval'} / 1000 );
    $self->heartbeat_loop( Mojo::IOLoop->recurring( $self->heartbeat_interval,
        sub {
            my $op = 1;
            my $d = $self->s;
            say localtime(time) . " OP 1 SEQ " . $self->s . " HEARTBEAT" if $self->verbose;
            $self->heartbeat_check($self->heartbeat_check+1);
            send_op($self, $op, $d);
        }
    ));
}

sub on_heartbeat_ack
{
    my ($self, $tx, $hash) = @_;

    say localtime(time) . " OP 11 SEQ " . $self->s . " HEARTBEAT ACK" if $self->verbose;
    $self->heartbeat_check($self->heartbeat_check-1);
}

__PACKAGE__->meta->make_immutable;

1;
