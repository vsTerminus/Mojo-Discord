package Mojo::Discord::REST;
use feature 'say';
our $VERSION = '0.001';

use Moo;
use strictures 2;

extends 'Mojo::Discord';

use Mojo::UserAgent;
use Mojo::Util qw(b64_encode);
use URI::Escape;
use Data::Dumper;
use Carp;

use namespace::clean;

has 'token'                 => ( is => 'ro' );
has 'name'                  => ( is => 'ro', default => 'Mojo::Discord' );
has 'url'                   => ( is => 'rw', required => 1 );
has 'version'               => ( is => 'ro', required => 1 );
has 'base_url'              => ( is => 'ro', default => 'https://discord.com/api' );
has 'agent'                 => ( is => 'lazy', builder => sub { my $self = shift; return $self->name . ' (' . $self->url . ',' . $self->version . ')' } );
has 'ua'                    => ( is => 'lazy', builder => sub 
                                { 
                                    my $self = shift;
                                    my $ua = Mojo::UserAgent->new;
                                    $ua->transactor->name($self->agent);
                                    $ua->inactivity_timeout(120);
                                    $ua->connect_timeout(5);
                                    $ua->on(start => sub {
                                        my ($ua, $tx) = @_;
                                        $tx->req->headers->authorization("Bot " . $self->token);
                                    });
                                    return $ua;
                                });
has 'log'                   => ( is => 'ro' );
has 'rate_buckets'          => ( is => 'rwp', default => sub { {} } );
has 'rate_bucket_ids'       => ( is => 'rwp', default => sub { {} } );

# Return an anonymous hash with the default rate limits for when we don't have any server-provided values yet.
sub _default_rate_limits
{
    my $route = shift;

    my $limit = 5;
    $limit = 25 if $route eq 'GET /guilds'; # Doesn't seem to receive ratelimit headers, so we'll limit it arbitrarily.

    return {
        'limit' => $limit,
        'reset' => time + 4,
        'remaining' => $limit,
        'reset_after' => 4
    };
}

# Every REST call returns rate limit information in the header
# There is a global rate limit, but also a "per-route" limit
# This means we need to interogate the headers on every response.
# See the Discord API docs for more details.
#
# This sub is just responsible for recording the returned rate limits, not to enforce them.
# It overrides the default setter for rate_limits so you can just pass in a Mojo::Header object and not worry about it.
sub _set_route_rate_limits
{
    my ($self, $route, $headers) = @_;

    my $bucket_id = $headers->header('x-ratelimit-bucket');
    return undef unless $bucket_id;

    $self->rate_bucket_ids->{$route} = $bucket_id;
    my $cache = $self->rate_buckets->{$bucket_id};
    
    my $valid = 0; # Boolean to determine whether headers are valid or outdated.

    # Hopefully deal with receiving headers out of order and setting bad values because of it.
    if ( $bucket_id and $cache )
    {
        # Valid iff x-ratelimit-reset == current value and x-ratelimit-limit is <= current value
        $valid = 1 if ( $headers->header('x-ratelimit-reset') == $cache->{'reset'} and
                        $headers->header('x-ratelimit-remaining') <= $cache->{'remaining'} );

        # Valid if x-ratelimit-rest > current value
        $valid = 1 if ( $headers->header('x-ratelimit-reset') > $cache->{'reset'} );
    }
    
    # Assuming we have valid ratelimit headers, update our cache.
    if ( $bucket_id and ( $valid or !defined $cache ) )
    { 
        $self->rate_buckets->{$bucket_id}{'limit'} = $headers->header('x-ratelimit-limit');
        $self->rate_buckets->{$bucket_id}{'reset'} = $headers->header('x-ratelimit-reset');
        $self->rate_buckets->{$bucket_id}{'remaining'} = $headers->header('x-ratelimit-remaining');
        $self->rate_buckets->{$bucket_id}{'reset_after'} = $headers->header('x-ratelimit-reset-after');
    }
    # Else - ignore it, we already have more current information.
}

# We should also be checking the rate limits (if known) for a route before we send a request.
# This returns the time until this bucket is allowed to send another message.
# If we are not rate limited (or don't have rate limits for this route yet), it will return zero.
sub _rate_limited
{
    my ($self, $route, $view_only) = @_;

    my $trunc_route = $route;
    $trunc_route =~ s/((GET|POST|PUT|PATCH|DELETE) \/[a-z]+).*$/$1/i;

    my $bucket_id = $self->rate_bucket_ids->{$route} // $trunc_route;
    my $bucket = $self->rate_buckets->{$bucket_id};

    # If we don't have up to date rate limit info from the server, use a default bucket.
    if ( !defined $bucket or $bucket->{'reset'} < time )
    {
        $self->rate_buckets->{$bucket_id} = _default_rate_limits($trunc_route); 
        $bucket = $self->rate_buckets->{$bucket_id};
    }

    if ( $bucket->{'remaining'} >= 1 )
    {
        # We have quote left, "grant it" by reducing the remaining count."
        $bucket->{'remaining'}--;
    }
    else
    {
        # We don't have quota left. Return the time until they can try again.
        $self->log->warn('[REST.pm] [_rate_limited] Route "' . $route . '" is rate limited. Reset In ' . $bucket->{'reset_after'} . ' seconds');
        return $bucket->{'reset_after'};
    }
    return 0;
}

# Validate the format of any channel, user, guild or similar ID.
# Make sure it's defined, numeric, and positive.
# Returns 1 if it passes everything.
sub _valid_id
{
    my ($self, $s, $id) = @_;

    unless ( defined $s )
    {
        $self->log->warn('[REST.pm] [_valid_id] Received no parameters');
        return undef;
    }

    unless ( defined $id )
    {
        $self->log->warn('[REST.pm] [' . $s . '] $id is undefined');
        return undef;
    }

    unless ( $id =~ /^\d+$/ )
    {
        $self->log->warn('[REST.pm] [' . $s . '] $id (' . $id . ') is not numeric');
        return undef;
    }

    unless ( $id > 0 )
    {
        $self->log->debu('[REST.pm] [' . $s . '] $id (' . $id . ') cannot be a negative number');
        return undef;
    }

    return 1;
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

    my $route = "POST /channels/$dest";
    if ( my $delay = $self->_rate_limited($route) )
    {
        $self->log->warn('[REST.pm] [send_message] Route is rate limited. Trying again in ' . $delay . ' seconds');
        Mojo::IOLoop->timer($delay => sub { $self->send_message($dest, $param, $callback) });
    }
    else
    {
        my $post_url = $self->base_url . "/channels/$dest/messages";

        # Remove this block
        #my $bucket_id = $self->rate_bucket_ids->{$route} // 'POST /channels';
        #my $bucket = $self->rate_buckets->{$bucket_id};
        #my $rate_limits = ' => Bucket: ' . $bucket_id;
        #$rate_limits .= ', Remaining: ' . $bucket->{'remaining'};
        #$rate_limits .= ', Reset: ' . $bucket->{'reset'};
        #$json->{'content'} .= $rate_limits; 
        # End Remove

        $self->ua->post($post_url => {Accept => '*/*'} => json => $json => sub
        {
            my ($ua, $tx) = @_;

            my $headers = $tx->res->headers;
            $self->_set_route_rate_limits($route, $headers);
            
            $callback->($tx->res->json) if defined $callback;
        });
    }
}

sub send_message_content_blocking
{
    my ($self, $dest, $content, $callback) = @_;

    my $json = {
        'content' => $content
    };

    my $route = "POST /channels/$dest";
    if ( my $delay = $self->_rate_limited($route))
    {
        $self->log->warn('[REST.pm] [send_message_content_blocking] Route is rate limited. Trying again in ' . $delay . ' seconds');
        Mojo::IOLoop->timer($delay => sub { $self->send_message_content_blocking($dest, $content, $callback) });
    }
    else
    {
        my $post_url = $self->base_url . "/channels/$dest/messages";
        my $tx = $self->ua->post($post_url => {Accept => '*/*'} => json => $json);

        $self->_set_route_rate_limits($route, $tx->res->headers);

        $callback->($tx->res->json) if defined $callback;
    }
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

    my $route = "PATCH /channels/$dest";
    if ( my $delay = $self->_rate_limited($route))
    {
        $self->log->warn('[REST.pm] [edit_message] Route is rate limited. Trying again in ' . $delay . ' seconds');
        Mojo::IOLoop->timer($delay => sub { $self->edit_message($dest, $param, $callback) });
    }
    else
    {
        my $post_url = $self->base_url . "/channels/$dest/messages/$msgid";
        $self->ua->patch($post_url => {DNT => '1'} => json => $json => sub
        {
            my ($ua, $tx) = @_;

            $self->_set_route_rate_limits($route, $tx->res->headers);

            $callback->($tx->res->json) if defined $callback;
        });
    }
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

    my $route = "DELETE /channels/$dest";
    if ( my $delay = $self->_rate_limited($route))
    {
        $self->log->warn('[REST.pm] [delete_message] Route is rate limited. Trying again in ' . $delay . ' seconds');
        Mojo::IOLoop->timer($delay => sub { $self->delete_message($dest, $param, $callback) });
    }
    else
    {
        my $post_url = $self->base_url . "/channels/$dest/messages/$msgid";
        $self->ua->delete($post_url => {DNT => '1'} => json => $json => sub
        {
            my ($ua, $tx) = @_;

            $self->_set_route_rate_limits($route, $tx->res->headers);

            $callback->($tx->res->json) if defined $callback;
        });
    }
}

sub set_topic
{
    my ($self, $channel, $topic, $callback) = @_;
    my $url = $self->base_url . "/channels/$channel";
    my $json = {
        'topic' => $topic
    };

    my $route = "PATCH /channels/$channel";
    if ( my $delay = $self->_rate_limited($route))
    {
        $self->log->warn('[REST.pm] [set_topic] Route is rate limited. Trying again in ' . $delay . ' seconds');
        Mojo::IOLoop->timer($delay => sub { $self->set_topic($channel, $topic, $callback) });
    }
    else
    {
        $self->ua->patch($url => {Accept => '*/*'} => json => $json => sub
        {
            my ($ua, $tx) = @_;

            $self->_set_route_rate_limits($route, $tx->res->headers);

            $callback->($tx->res->json) if defined $callback;
        });
    }
}

# Send "acknowledged" DM 
# aka, acknowledge a command by adding a :white_check_mark: reaction to it and then send a DM
# Takes a channel ID and message ID to react to, a user ID to DM, a message to send, and an optional callback sub.
sub send_ack_dm
{
    my ($self, $channel_id, $message_id, $user_id, $message, $callback) = @_;

    $self->rest->create_reaction($channel_id, $message_id, "\x{2705}");
    $self->send_dm($user_id, $message, $callback);
}

# Just a shortcut which handles creating the DM for the caller.
sub send_dm
{
    my ($self, $user, $message, $callback) = @_;

    $self->create_dm($user, sub
    {
        my $json = shift;
        my $dm = $json->{'id'};

        $self->log->debug('[REST.pm] [send_dm] Sending DM to user ID ' . $user . ' in DM ID ' . $dm);

        $self->send_message($dm, $message, $callback);
    });
}

sub create_dm
{
    my ($self, $id, $callback) = @_;

    my $url = $self->base_url . '/users/@me/channels';
    my $json = {
        'recipient_id' => $id
    };

    my $route = 'POST /users';
    if ( my $delay = $self->_rate_limited($route))
    {
        $self->log->warn('[REST.pm] [create_dm] Route is rate limited. Trying again in ' . $delay . ' seconds');
        Mojo::IOLoop->timer($delay => sub { $self->create_dm($id, $callback) });
    }
    else
    {
        $self->ua->post($url => {Accept => '*/*'} => json => $json => sub
        {
            my ($ua, $tx) = @_;

            $self->_set_route_rate_limits($route, $tx->res->headers);

            $callback->($tx->res->json) if defined $callback;
        });
    }
}

sub get_user
{
    my ($self, $id, $callback) = @_;

    unless ( $self->_valid_id('get_user', $id) )
    {
        $callback->(undef) if defined $callback;
        return;
    }

    my $route = 'GET /users';
    if ( my $delay = $self->_rate_limited($route))
    {
        $self->log->warn('[REST.pm] [get_user] Route is rate limited. Trying again in ' . $delay . ' seconds');
        Mojo::IOLoop->timer($delay => sub { $self->get_user($id, $callback) });
    }
    else
    {
        my $url = $self->base_url . "/users/$id";
        $self->ua->get($url => sub
        {
            my ($ua, $tx) = @_;

            $self->_set_route_rate_limits($route, $tx->res->headers);

            $callback->($tx->res->json) if defined $callback;
        });
    }
}

sub get_user_p
{
    my ($self, $id) = @_;
    my $promise = Mojo::Promise->new;

    $self->get_user($id, sub { $promise->resolve(shift) });

    return $promise;
};

sub leave_guild
{
    my ($self, $user, $guild, $callback) = @_;

    my $route = 'DELETE /users';
    if ( my $delay = $self->_rate_limited($route))
    {
        $self->log->warn('[REST.pm] [leave_guild] Route is rate limited. Trying again in ' . $delay . ' seconds');
        Mojo::IOLoop->timer($delay => sub { $self->leave_guild($user, $guild, $callback) });
    }
    else
    {
        my $url = $self->base_url . "/users/$user/guilds/$guild";
        $self->ua->delete($url => sub {
            my ($ua, $tx) = @_;

            $self->_set_route_rate_limits($route, $tx->res->headers);

            $callback->($tx->res->body) if defined $callback;
        });
    }
}

sub get_guilds
{
    my ($self, $user, $callback) = @_;

    my $route = 'GET /users';
    if ( my $delay = $self->_rate_limited($route))
    {
        $self->log->warn('[REST.pm] [get_guilds] Route is rate limited. Trying again in ' . $delay . ' seconds');
        Mojo::IOLoop->timer($delay => sub { $self->get_guilds($user, $callback) });
    }
    else
    {
        my $url = $self->base_url . "/users/$user/guilds";

        return $self->ua->get($url => sub
        {
            my ($ua, $tx) = @_;

            $self->_set_route_rate_limits($route, $tx->res->headers);

            $callback->($tx->res->json) if defined $callback;
        });
    }
}

# Tell the channel that the bot is "typing", aka thinking about a response.
sub start_typing
{
    my ($self, $dest, $callback) = @_;

    my $route = "POST /channels/$dest";
    if ( my $delay = $self->_rate_limited($route))
    {
        $self->log->warn('[REST.pm] [start_typing] Route is rate limited. Trying again in ' . $delay . ' seconds');
        Mojo::IOLoop->timer($delay => sub { $self->start_typing($dest, $callback) });
    }
    else
    {
        my $typing_url = $self->base_url . "/channels/$dest/typing";

        $self->ua->post($typing_url, sub
        {
            my ($ua, $tx) = @_;

            $self->_set_route_rate_limits($route, $tx->res->headers);

            $callback->($tx->res->body) if defined $callback;
        });
    }
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


    my $route = "POST /channels/$channel";
    if ( my $delay = $self->_rate_limited($route) )
    {
        $self->log->warn('[REST.pm] [create_webhook] Route is rate limited. Trying again in ' . $delay . ' seconds');
        Mojo::IOLoop->timer($delay => sub { $self->create_webhook($channel, $params, $callback) });
    }
    else
    {
        # Next, call the endpoint
        my $url = $self->base_url . "/channels/$channel/webhooks";
        if ( defined $callback )
        {
            $self->ua->post($url => json => $json => sub
            {
                my ($ua, $tx) = @_;

                $self->_set_route_rate_limits($route, $tx->res->headers);

                $callback->($tx->res->json);
            });
        }
        else
        {
            return $self->ua->post($url => json => $json);
        }
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

    my $route = "POST /webhooks/$id";
    if ( my $delay = $self->_rate_limited($route) )
    {
        $self->log->warn('[REST.pm] [send_webhook] Route is rate limited. Trying again in ' . $delay . ' seconds');
        Mojo::IOLoop->timer($delay => sub { $self->send_webhook($channel, $hook, $params, $callback) });
    }
    else
    {
        $self->ua->post($url => json => $params => sub
        {
            my ($ua, $tx) = @_;

            $self->_set_route_rate_limits($route, $tx->res->headers);

            $callback->($tx->res->json) if defined $callback;
        });
    }
}

sub get_channel_webhooks
{
    my ($self, $channel, $callback) = @_;

    die("get_channel_webhooks requires a channel ID") unless (defined $channel);

    my $route = "GET /channels/$channel";
    if ( my $delay = $self->_rate_limited($route) )
    {
        $self->log->warn('[REST.pm] [get_channel_webhooks] Route is rate limited. Trying again in ' . $delay . ' seconds');
        Mojo::IOLoop->timer($delay => sub { $self->get_channel_webhooks($channel, $callback) });
    }
    else
    {
        my $url = $self->base_url . "/channels/$channel/webhooks";
        $self->ua->get($url => sub
        {
            my ($ua, $tx) = @_;

            $self->_set_route_rate_limits($route, $tx->res->headers);

            $callback->($tx->res->json) if defined $callback;
        });
    }
}

sub get_guild_webhooks
{
    my ($self, $guild, $callback) = @_;

    die("get_guild_webhooks requires a guild ID") unless (defined $guild);

    my $route = "GET /guilds/$guild";
    if ( my $delay = $self->_rate_limited($route) )
    {
        $self->log->warn('[REST.pm] [get_guild_webhooks] Route is rate limited. Trying again in ' . $delay . ' seconds');
        Mojo::IOLoop->timer($delay => sub { $self->get_guild_webhooks($guild, $callback) });
    }
    else
    {
        my $url = $self->base_url . "/guilds/$guild/webhooks";

        $self->ua->get($url => sub
        {
            my ($ua, $tx) = @_;

            $self->_set_route_rate_limits($route, $tx->res->headers);

            $callback->($tx->res->json) if defined $callback;
        });
    }
}

sub create_reaction
{
    my ($self, $channel, $msgid, $emoji, $callback) = @_;

    my $route = "GET /channels/$channel";
    if ( my $delay = $self->_rate_limited($route) )
    {
        $self->log->warn('[REST.pm] [create_reaction] Route is rate limited. Trying again in ' . $delay . ' seconds');
        Mojo::IOLoop->timer($delay => sub { $self->create_reaction($channel, $msgid, $emoji, $callback) });
    }
    else
    {
        my $url = $self->base_url . "/channels/$channel/messages/$msgid/reactions/" . uri_escape_utf8($emoji) . '/@me';

        $self->ua->put($url => sub
        {
            my ($ua, $tx) = @_;
 
            $self->_set_route_rate_limits($route, $tx->res->headers);

            $callback->($tx->res->json) if defined $callback;
        });
    }
}

sub delete_reaction
{
    my ($self, $channel, $msgid, $emoji, $userid, $callback) = @_;

    my $route = "GET /channels/$channel";
    if ( my $delay = $self->_rate_limited($route) )
    {
        $self->log->warn('[REST.pm] [delete_reaction] Route is rate limited. Trying again in ' . $delay . ' seconds');
        Mojo::IOLoop->timer($delay => sub { $self->delete_reaction($channel, $msgid, $emoji, $userid, $callback) });
    }
    else
    {
        my $url = $self->base_url . "/channels/$channel/messages/$msgid/reactions/" . uri_escape_utf8($emoji) . '/' . $userid;

        $self->ua->delete($url => sub
        {
            my ($ua, $tx) = @_;

            $self->_set_route_rate_limits($route, $tx->res->headers);

            $callback->($tx->res->json) if defined $callback;
        });
    }
}

sub get_reactions
{
    my ($self, $channel, $msgid, $emoji, $callback) = @_;

    my $route = "GET /channels/$channel";
    if ( my $delay = $self->_rate_limited($route) )
    {
        $self->log->warn('[REST.pm] [get_reactions] Route is rate limited. Trying again in ' . $delay . ' seconds');
        Mojo::IOLoop->timer($delay => sub { $self->get_reactions($channel, $msgid, $emoji, $callback) });
    }
    else
    {
        # Returns a max. of 25 users by default, query string params 'before', 'after' and 'limit' could be used
        my $url = $self->base_url . "/channels/$channel/messages/$msgid/reactions/" . uri_escape_utf8($emoji);

        $self->ua->get($url => sub
        {
            my ($ua, $tx) = @_;

            $self->_set_route_rate_limits($route, $tx->res->headers);

            $callback->($tx->res->json) if defined $callback;
        });
    }
}

sub delete_all_reactions
{
    my ($self, $channel, $msgid, $emoji, $callback) = @_;

    my $route = "GET /channels/$channel";
    if ( my $delay = $self->_rate_limited($route) )
    {
        $self->log->warn('[REST.pm] [delete_all_reactions] Route is rate limited. Trying again in ' . $delay . ' seconds');
        Mojo::IOLoop->timer($delay => sub { $self->delete_all_reactions($channel, $msgid, $emoji, $callback) });
    }
    else
    {
        my $url = $self->base_url . "/channels/$channel/messages/$msgid/reactions" . ($emoji ? ('/' . uri_escape_utf8($emoji)) : '');

        $self->ua->delete($url => sub
        {
            my ($ua, $tx) = @_;

            $self->_set_route_rate_limits($route, $tx->res->headers);

            $callback->($tx->res->json) if defined $callback;
        });
    }
}

sub get_audit_log
{
    my ($self, $guild_id, $callback) = @_;

    my $route = "GET /guilds/$guild_id";
    if ( my $delay = $self->_rate_limited($route) )
    {
        $self->log->warn('[REST.pm] [get_audit_log] Route is rate limited. Trying again in ' . $delay . ' seconds');
        Mojo::IOLoop->timer($delay => sub { $self->get_audit_log($guild_id, $callback) });
    }
    else
    {
        my $url = $self->base_url . "/guilds/$guild_id/audit-logs";
        
        $self->ua->get($url => sub
        {
            my ($ua, $tx) = @_;

            $self->_set_route_rate_limits($route, $tx->res->headers);

            $callback->($tx->res->json) if defined $callback;
        });
    }
}

sub set_channel_name
{
    my ($self, $channel, $name, $callback) = @_;
    my $url = $self->base_url . "/channels/$channel";
    my $json = {
        'name' => $name
    };

    my $route = "PATCH /channels/$channel";
    if ( my $delay = $self->_rate_limited($route))
    {
        $self->log->warn('[REST.pm] [set_channel_name] Route is rate limited. Trying again in ' . $delay . ' seconds');
        Mojo::IOLoop->timer($delay => sub { $self->set_channel_name($channel, $name, $callback) });
    }
    else
    {
        $self->ua->patch($url => {Accept => '*/*'} => json => $json => sub
        {
            my ($ua, $tx) = @_;

            $self->_set_route_rate_limits($route, $tx->res->headers);

            $callback->($tx->res->json) if defined $callback;
        });
    }
}

sub get_channel
{
	my ($self, $channel, $callback) = @_;
	
	unless ( $self->_valid_id('get_channel_message', $channel) )
	{
		$callback->(undef) if defined $callback;
		return;
	}
	
	my $route = "GET /channels";
	if ( my $delay = $self->_rate_limited($route) )
	{
		$self->log->warn('[REST.pm] [get_channel] Route is rate limited. Trying again in ' . $delay . ' seconds');
		Mojo::IOLoop->timer($delay => sub { $self->get_channel_message($channel, $callback) });
	}
	else
	{
		my $url = $self->base_url . "/channels/$channel";
		$self->ua->get($url => sub
		{
			my ($ua, $tx) = @_;
			
			$self->_set_route_rate_limits($route, $tx->res->headers);
			
			$callback->($tx->res->json) if defined $callback;
		});
	}
}

sub delete_webhook_by_token
{
	my ($self, $id, $token, $callback) = @_;
	
	my $route = "DELETE /webhooks";
	if ( my $delay = $self->_rate_limited($route) )
	{
		$self->log->warn('[REST.pm] [delete_webhook_token] Route is rate limited. Trying again in ' . $delay . ' seconds');
		Mojo::IOLoop->timer($delay => sub { $self->get_channel_message($id, $token, $callback) });
	}
	else
	{
		my $url = $self->base_url . "/webhooks/$id/$token";
		$self->ua->delete($url => sub
		{
			my ($ua, $tx) = @_;
			
			$self->_set_route_rate_limits($route, $tx->res->headers);
			
			$callback->($tx->res->json) if defined $callback;
		});
	}
}

sub create_guild_emoji
{
	my ($self, $guildid, $name, $emojifile, $callback) = @_;
	
	open(IMAGE, $emojifile);
	my $raw_string = do{ local $/ = undef; <IMAGE>; };
	my $base64 = b64_encode( $raw_string );
	close(IMAGE);
    
    my $type = ( $emojifile =~ /.png$/ ? 'png' : 'gif' );
	
	my $json = {
		'name' => $name,
		'image' => "data:image/$type;base64," . $base64,
	};
	
	my $route = "POST /guilds";
	if ( my $delay = $self->_rate_limited($route) )
	{
		$self->log->warn('[[REST.pm] [create_guild_emoji] Route is rate limited. Trying again in ' . $delay . ' seconds');
		Mojo::IOLoop->timer($delay => sub { $self->create_guild_emoji($guildid, $name, $emojifile, $callback) });
	}
	else
	{
		my $url = $self->base_url . "/guilds/$guildid/emojis";
		$self->ua->post($url => {Accept => '*/*'} => json => $json => sub
        {
            my ($ua, $tx) = @_;

            $self->_set_route_rate_limits($route, $tx->res->headers);

            $callback->($tx->res->json) if defined $callback;
        });
    }
}

sub delete_guild_emoji
{
	my ($self, $guildid, $emojiid, $callback) = @_;

	my $route = "DELETE /guilds";
	if ( my $delay = $self->_rate_limited($route) )
	{
		$self->log->warn('[[REST.pm] [delete_guild_emoji] Route is rate limited. Trying again in ' . $delay . ' seconds');
		Mojo::IOLoop->timer($delay => sub { $self->get_channel_message($guildid, $emojiid, $callback) });
	}
	else
	{
		my $url = $self->base_url . "/guilds/$guildid/emojis/$emojiid";
		$self->ua->delete($url => sub
		{
			my ($ua, $tx) = @_;
			
			$self->_set_route_rate_limits($route, $tx->res->headers);
			
			$callback->($tx->res->json) if defined $callback;
		});
	}
}

sub get_webhook_by_token
{
	my ($self, $id, $token, $callback) = @_;
	
	unless ( $self->_valid_id('get_webhook_token', $id) )
	{
		$callback->(undef) if defined $callback;
		return;
	}
	
	my $route = "GET /webhooks";
	if ( my $delay = $self->_rate_limited($route) )
	{
		$self->log->warn('[REST.pm] [get_webhook_token] Route is rate limited. Trying again in ' . $delay . ' seconds');
		Mojo::IOLoop->timer($delay => sub { $self->get_webhook_token($id, $token, $callback) });
	}
	else
	{
		my $url = $self->base_url . "/webhooks/$id/$token";
		$self->ua->get($url => sub
		{
			my ($ua, $tx) = @_;

			$self->_set_route_rate_limits($route, $tx->res->headers);
			
			$callback->($tx->res->json) if defined $callback;
		});
	}
}

1;

=head1 NAME

Mojo::Discord::REST - An implementation of the Discord Public REST API endpoints

=head1 SYNOPSIS

```perl
#!/usr/bin/env perl

use v5.10;
use strict;
use warnings;

my $rest = Mojo::Discord::REST->new(
    'token'         => 'token-string',
    'name'          => 'client-name',
    'url'           => 'my-website',
    'version'       => '1.0',
    'log'           => Mojo::Log->new(
                            path    => '/path/to/logs/rest.log',
                            level   => 'DEBUG',
                        ),
);

$rest->get_user('1234567890', sub { my $json = shift; say $json->{'id'} });
```

=head1 DESCRIPTION

L<Mojo::Discord::REST> wrapper for the Discord REST API endpoints.

It requires a discord token, and some of the calls require you to be connected to a Discord Gateway as well (eg, sending messages)

Typically you would not interact with this module directly, as L<Mojo::Discord> functions as a wrapper for this and related modules.

All calls accept an optional callback parameter, which this module will use to provide return values.

=head1 PROPERTIES

L<Mojo::Discord::REST> requires the following to be passed in on instantiation

=head2 token
    This is a Discord Bot token generated by the Discord API. 

=head2 name
    This name is only used in the Mojo::UserAgent agent name, it does not determine the bot's username.

=head2 url
    A URL relevant to your bot - perhaps a github repo or a public website.

=head2 version
    The version of your client application

=head2 log
    A Mojo::Log object the module can use to write to disk

=head1 ATTRIBUTES

L<Mojo::Discord::REST> provides these attributes beyond what is passed in at creation.

=head2 agent
    The useragent string used by Mojo::UserAgent to identify itself

=head2 ua
    The Mojo::UserAgent object used to make calls to the Discord REST API endpoints

=head1 SUBROUTINES

L<Mojo::Discord::REST> provides the following subs you may want to leverage

=head2 send_message
    Accepts a channel ID, a message to send, and an optional callback sub.
    The message can either be a string of text to send to the channel, or it can be a JSON string of a discord MESSAGE payload. The latter offers you low level control over the message contents.

    ```perl
    $rest->send_message($channel, 'Test message please ignore');
    ```

=head2 edit_message
    Accepts a channel ID, a message ID, an updated message, and an optional callback
    Like send_message, the updated messaage can be either a simple string or it can be a JSON discord MESSAGE payload

=head2 delete_message
    Accepts a channel ID, a message ID, 



=head1 BUGS

Report issues on github

https://github.com/vsTerminus/Mojo-Discord

=head1 CONTRIBUTE

Contributions are welcomed via Github pull request

https://github.com/vsTerminus/Mojo-Discord

=head1 AUTHOR

Travis Smith <tesmith@cpan.org>

=head1 COPYRIGHT AND LICENSE
This software is Copyright (c) 2017-2020 by Travis Smith.

This is free software, licensed under:

  The MIT (X11) License

=head1 SEE ALSO

- L<Mojo::UserAgent>
- L<Mojo::IOLoop>
