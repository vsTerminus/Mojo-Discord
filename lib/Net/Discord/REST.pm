package Net::Discord::REST;

use v5.10;
use warnings;
use strict;

use Mojo::UserAgent;
use MIME::Base64;
use Data::Dumper;

sub new
{
    my ($class, %params) = @_;
    my $self = {};

    die("Net::Discord::REST requires a Token.") unless defined $params{'token'};
    die("Net::Discord::REST requires an application name.") unless defined $params{'name'};
    die("Net::Discord::REST requires an application URL.") unless defined $params{'url'};
    die("Net::Discord::REST requires an application version.") unless defined $params{'version'};

    # Store the token, application name, url, and version
    $self->{'token'}    = $params{'token'};

    
    # API Vars - Will need to be updated if the API changes
    $self->{'base_url'}     = 'https://discordapp.com/api';
    $self->{'name'}         = $params{'name'};
    $self->{'url'}          = $params{'url'};
    $self->{'version'}      = $params{'version'};
    
    # Other vars
    $self->{'agent'}        = $self->{'name'} . ' (' . $self->{'url'} . ',' . $self->{'version'} . ')';

    my $ua = Mojo::UserAgent->new;
    $ua->transactor->name($self->{'agent'});

    # Make sure the token is added to every request automatically.
    $ua->on(start => sub {
        my ($ua, $tx) = @_;
        $tx->req->headers->authorization("Bot " . $self->{'token'});
    });

    $self->{'ua'} = $ua;

    bless $self, $class;
    return $self;
}

# send_message will check if it is being passed a hashref or a string.
# This way it is simple to just send a message by passing in a string, but it can also support things like embeds and the TTS flag when needed.
sub send_message
{
    my ($self, $dest, $param, $callback) = @_;
  
    my $json;

    if ( ref $param eq ref {} ) # If hashref just pass it along as-is.
    {
        $json = $param;
    }
    elsif ( ref $param eq ref [] )
    {
        say localtime(time) . "Net::Discord::REST->send_message Received array. Expected hashref or string.";
        return -1;
    }
    else    # Scalar - Simple string message. Build a basic json object to send.
    {
        $json = {
            'content' => $param
        };
    }

    my $post_url = $self->{'base_url'} . "/channels/$dest/messages";
    $self->{'ua'}->post($post_url => {Accept => '*/*'} => json => $json => sub
    {
        my ($ua, $tx) = @_;

        $callback->($tx->res->body) if defined $callback;
    });
}

sub get_user
{
    my ($self, $id, $callback) = @_;
    
    my $url = $self->{'base_url'} . "/users/$id";
    $self->{'ua'}->get($url => sub 
    {
        my ($ua, $tx) = @_;
        
        $callback->($tx->res->json) if defined $callback;
    });
}

sub leave_guild
{
    my ($self, $user, $guild, $callback) = @_;
    
    my $url = $self->{'base_url'} . "/users/$user/guilds/$guild";
    say "URL: $url";
    $self->{'ua'}->delete($url => sub {
        my ($ua, $tx) = @_;
        $callback->($tx->res->body) if defined $callback;
    });
}

sub get_guilds
{
    my ($self, $user, $callback) = @_;

    my $url = $self->{'base_url'} . "/users/$user/guilds";

    say "URL: $url";

    return $self->{'ua'}->get($url => sub 
    {
        my ($ua, $tx) = @_;
        $callback->($tx->res->json) if defined $callback;
    });
}

# Tell the channel that the bot is "typing", aka thinking about a response.
sub start_typing
{
    my ($self, $dest, $callback) = @_;

    my $typing_url = $self->{'base_url'} . "/channels/$dest/typing";

    $self->{'ua'}->post($typing_url, sub 
    { 
        my ($ua, $tx) = @_;
        $callback->($tx->res->body) if defined $callback;
    });
}

# Create a new Webhook
sub create_webhook
{
    my ($self, $channel, $params, $callback) = @_;

    my $name = $params->{'name'};
    my $avatar_file = $params->{'avatar'};

    say ref $callback;

    # Check the name is valid (2-100 chars)
    if ( length $name < 2 or length $name > 100 )
    {
        die("create_webhook was passed an invalid webhook name. Field must be between 2 and 100 characters in length.");
    }

    my $base64;
    # First, convert the avatar file to base64.
    if ( defined $avatar_file and -f $avatar_file)
    {
        open(IMAGE, $avatar_file);
        my $raw_string = do{ local $/ = undef; <IMAGE>; };
        $base64 = encode_base64( $raw_string );
        close(IMAGE);
    }
    # else - no big deal, it's optional.

    # Next, create the JSON object.
    my $json = { 'name' => $name };

    # Add avatar base64 info to it if an avatar file if we can.
    my $type = ( $avatar_file =~ /.png$/ ? 'png' : 'jpeg' ) if defined $avatar_file;
    $json->{'avatar'} = "data:image/$type;base64," . $base64 if defined $base64;

    # Next, call the endpoint
    my $url = $self->{'base_url'} . "/channels/$channel/webhooks";
    $self->{'ua'}->post($url => json => $json => sub
    {
        my ($ua, $tx) = @_;
        $callback->($tx->res->json);# if defined $callback;
    });
}

sub send_webhook
{
    my ($self, $channel, $id, $token, $params, $callback) = @_;

    my $url = $self->{'base_url'} . "/webhooks/$id/$token";

    $self->{'ua'}->post($url => json => $params => sub
    {
        my ($ua, $tx) = @_;

        $callback->($tx->res->json) if defined $callback;
    });
}

sub get_channel_webhooks
{
    my ($self, $channel, $callback) = @_;

    die("get_channel_webhooks requires a channel ID") unless (defined $channel);

    my $url = $self->{'base_url'} . "/channels/$channel/webhooks";

    $self->{'ua'}->get($url => sub
    {
        my ($ua, $tx) = @_;

        $callback->($tx->res->json) if defined $callback;
    });
}

sub get_guild_webhooks
{
    my ($self, $guild, $callback) = @_;

    die("get_guild_webhooks requires a guild ID") unless (defined $guild);

    my $url = $self->{'base_url'} . "/guilds/$guild/webhooks";

    $self->{'ua'}->get($url => sub
    {
        my ($ua, $tx) = @_;

        $callback->($tx->res->json) if defined $callback;
    });
}

1;

