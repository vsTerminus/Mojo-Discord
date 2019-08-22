package Mojo::Discord::REST;
use feature 'say';
our $VERSION = '0.001';

use Moo;
use strictures 2;

extends 'Mojo::Discord';

use Mojo::UserAgent;
use Mojo::Util qw(b64_encode);
use Data::Dumper;

use namespace::clean;

has 'token'         => ( is => 'ro' );
has 'name'          => ( is => 'rw', required => 1 );
has 'url'           => ( is => 'rw', required => 1 );
has 'version'       => ( is => 'ro', required => 1 );
has 'base_url'      => ( is => 'ro', default => 'https://discordapp.com/api' );
has 'agent'         => ( is => 'rw' );
has 'ua'            => ( is => 'rw', default => sub { Mojo::UserAgent->new } );

sub BUILD
{
    my $self = shift;

    $self->agent( $self->name . ' (' . $self->url . ',' . $self->version . ')' );

    $self->ua->transactor->name($self->agent);
    $self->ua->inactivity_timeout(120);
    $self->ua->connect_timeout(5);
    $self->ua->on(start => sub {
        my ($ua, $tx) = @_;
        $tx->req->headers->authorization("Bot " . $self->token);
    });
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
        say localtime(time) . "Mojo::Discord::REST->send_message Received array. Expected hashref or string.";
        return -1;
    }
    else    # Scalar - Simple string message. Build a basic json object to send.
    {
        $json = {
            'content' => $param
        };
    }

    my $post_url = $self->base_url . "/channels/$dest/messages";
    $self->ua->post($post_url => {Accept => '*/*'} => json => $json => sub
    {
        my ($ua, $tx) = @_;

        #say Dumper($tx->res->json);

        $callback->($tx->res->json) if defined $callback;
    });
}

sub edit_message
{
    my ($self, $dest, $msgid, $param, $callback) = @_;

    my $json;

    if ( ref $param eq ref {} ) # If hashref just pass it along as-is.
    {
        $json = $param;
    }
    elsif ( ref $param eq ref [] )
    {
        say localtime(time) . "Mojo::Discord::REST->send_message Received array. Expected hashref or string.";
        return -1;
    }
    else    # Scalar - Simple string message. Build a basic json object to send.
    {
        $json = {
            'content' => $param
        };
    }

    my $post_url = $self->base_url . "/channels/$dest/messages/$msgid";
    $self->ua->patch($post_url => {DNT => '1'} => json => $json => sub
    {
        my ($ua, $tx) = @_;

        #say Dumper($tx->res->json);

        $callback->($tx->res->json) if defined $callback;
    });
}

sub delete_message
{
    my ($self, $dest, $msgid, $param, $callback) = @_;

    my $json;

    if ( ref $param eq ref {} ) # If hashref just pass it along as-is.
    {
        $json = $param;
    }
    elsif ( ref $param eq ref [] )
    {
        say localtime(time) . "Mojo::Discord::REST->send_message Received array. Expected hashref or string.";
        return -1;
    }
    else    # Scalar - Simple string message. Build a basic json object to send.
    {
        $json = {
            #'content' => $param
        };
    }

    my $post_url = $self->base_url . "/channels/$dest/messages/$msgid";
    $self->ua->delete($post_url => {DNT => '1'} => json => $json => sub
    {
        my ($ua, $tx) = @_;

        #say Dumper($tx->res->json);

        $callback->($tx->res->json) if defined $callback;
    });
}

sub get_user
{
    my ($self, $id, $callback) = @_;

    my $url = $self->base_url . "/users/$id";
    $self->ua->get($url => sub
    {
        my ($ua, $tx) = @_;

        #say Dumper($tx->res->json);

        $callback->($tx->res->json) if defined $callback;
    });
}

sub leave_guild
{
    my ($self, $user, $guild, $callback) = @_;

    my $url = $self->base_url . "/users/$user/guilds/$guild";
    $self->ua->delete($url => sub {
        my ($ua, $tx) = @_;
        $callback->($tx->res->body) if defined $callback;
    });
}

sub get_guilds
{
    my ($self, $user, $callback) = @_;

    my $url = $self->base_url . "/users/$user/guilds";

    return $self->ua->get($url => sub
    {
        my ($ua, $tx) = @_;
        $callback->($tx->res->json) if defined $callback;
    });
}

# Tell the channel that the bot is "typing", aka thinking about a response.
sub start_typing
{
    my ($self, $dest, $callback) = @_;

    my $typing_url = $self->base_url . "/channels/$dest/typing";

    $self->ua->post($typing_url, sub
    {
        my ($ua, $tx) = @_;
        $callback->($tx->res->body) if defined $callback;
    });
}

# Create a new Webhook
# Is non-blocking if $callback is defined
sub create_webhook
{
    my ($self, $channel, $params, $callback) = @_;

    my $name = $params->{'name'};
    my $avatar_file = $params->{'avatar'};

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
        $base64 = b64_encode( $raw_string );
        close(IMAGE);
    }
    # else - no big deal, it's optional.

    # Next, create the JSON object.
    my $json = { 'name' => $name };

    # Add avatar base64 info to it if an avatar file if we can.
    my $type = ( $avatar_file =~ /.png$/ ? 'png' : 'jpeg' ) if defined $avatar_file;
    $json->{'avatar'} = "data:image/$type;base64," . $base64 if defined $base64;

    # Next, call the endpoint
    my $url = $self->base_url . "/channels/$channel/webhooks";
    if ( defined $callback )
    {
        $self->ua->post($url => json => $json => sub
        {
            my ($ua, $tx) = @_;
            $callback->($tx->res->json);
        });
    }
    else
    {
        return $self->ua->post($url => json => $json);
    }
}

sub send_webhook
{
    my ($self, $channel, $hook, $params, $callback) = @_;

    my $id = $hook->{'id'};
    my $token = $hook->{'token'};
    my $url = $self->base_url . "/webhooks/$id/$token";

    if ( ref $params ne ref {} )
    {
        # Received a scalar, convert it to a basic structure using the default avatar and name
        $params = {'content' => $params};
    }

    $self->ua->post($url => json => $params => sub
    {
        my ($ua, $tx) = @_;

        $callback->($tx->res->json) if defined $callback;
    });
}

sub get_channel_webhooks
{
    my ($self, $channel, $callback) = @_;

    die("get_channel_webhooks requires a channel ID") unless (defined $channel);

    my $url = $self->base_url . "/channels/$channel/webhooks";

    $self->ua->get($url => sub
    {
        my ($ua, $tx) = @_;

        $callback->($tx->res->json) if defined $callback;
    });
}

sub get_guild_webhooks
{
    my ($self, $guild, $callback) = @_;

    die("get_guild_webhooks requires a guild ID") unless (defined $guild);

    my $url = $self->base_url . "/guilds/$guild/webhooks";

    $self->ua->get($url => sub
    {
        my ($ua, $tx) = @_;

        $callback->($tx->res->json) if defined $callback;
    });
}

sub add_reaction
{
    my ($self, $channel, $msgid, $emoji, $callback) = @_;

    my $url = $self->base_url . "/channels/$channel/messages/$msgid/reactions/$emoji/\@me";
    my $json;
    
    $self->ua->put($url => {Accept => '*/*'} => json => $json => sub
    {   
        my ($ua, $tx) = @_;
        
        $callback->($tx->res->json) if defined $callback;
    });
}

__PACKAGE__->meta->make_immutable;
1;
