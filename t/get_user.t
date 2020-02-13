use Mojo::Base -strict;

use Test::More;
use Mock::Quick;
use Mojolicious::Lite;
use Mojo::Promise;

get '/app/users/1' => sub {
    my $c = shift;

    $c->res->headers->header('x-ratelimit-bucket' => 'bucket');
    $c->res->headers->header('x-ratelimit-limit' => 1);
    $c->res->headers->header('x-ratelimit-reset' => time + 1);
    $c->res->headers->header('x-ratelimit-remaining' => 1);
    $c->res->headers->header('x-ratelimit-reset-after' => 1);

    $c->render(json => '{success: true}');
};

get '/app/users/rate_limited' => sub {
};

app->log->level('fatal');
app->start();

##########################

require_ok( 'Mojo::Discord' );

# Take over Mojo::IOLoop->timer with a mock function that just sets the timer_id value
my $timer_id;
my $control = qtakeover 'Mojo::IOLoop' => ( 'timer' => sub { my ($self, $id) = @_; $timer_id = $id } );

my $discord = Mojo::Discord->new(
    token       => 'token_string',
    name        => 'bot_name',
    url         => 'bot_url',
    version     => 'bot_version',
    base_url    => '/app',
    logdir      => '.',
    loglevel    => 'fatal',
);

my $rest = $discord->rest;
$rest->ua->server->app(app);

# There is caching done by the gateway which the $discord object has access to.
# If a user profile is cached, $discord will return that. Otherwise it will ask $rest
# for a new one.
# If the caller goes straight to $rest, that caching isn't an option, 
# it just always requests new data.
# Because this additional logic exists, I'm going to test each call twice; 
# Once from $discord, once from $rest

# Also worth noting, we only need to test the _p functions because they are purely wrappers
# and have no logic or validation of their own.

sub main
{
    my $json;
    $discord->get_user_p('1')->then(sub{ $json = shift })->wait();
    is( $json, '{success: true}', 'discord happy path' );
    is( $rest->rate_limits->{'bucket'}{'remaining'}, 1, 'rate limit "remaining" storage' );
    $rest->get_user_p('1')->then(sub{ $json = shift })->wait();
    is( $json, '{success: true}', 'rest happy path' );
    is( $rest->rate_limits->{'bucket'}{'reset_after'}, 1, 'rate limit "reset after" storage' );

    $discord->get_user_p()->then(sub{ $json = shift })->wait();
    is( $json, undef, 'discord no args');
    $rest->get_user_p()->then(sub{ $json = shift })->wait();
    is( $json, undef, 'rest no args' );

    $discord->get_user_p('-1')->then(sub{ $json = shift })->wait();
    is( $json, undef, 'discord negative id' );
    $rest->get_user_p('-1')->then(sub{ $json = shift })->wait();
    is( $json, undef, 'rest negative id' );

    $discord->get_user_p('string')->then(sub{ $json = shift })->wait();
    is( $json, undef, 'discord string id' );
    $rest->get_user_p('string')->then(sub{ $json = shift })->wait();
    is( $json, undef, 'discord string id' );

    # There is no Mojolicious::Lite endpoint for ID = 2
    # So this should only be successful if it uses the cache.
    # And it should fail when called from the $rest object.
    $discord->gw->users->{'2'} = '{cached: true}';
    $discord->get_user_p('2')->then(sub{ $json = shift })->wait();
    is( $json, '{cached: true}', 'discord cached id' );
    $rest->get_user_p('2')->then(sub{ $json = shift })->wait();
    is( $json, undef, 'rest cached id' );

    # Test rate limiting by checking to see if our mocked IOLoop->timer sub was called
    # No need to call this twice, there is no rate limit logic in Discord.pm
    $rest->rate_limits->{'bucket'}{'remaining'} = 0;
    $rest->rate_limits->{'bucket'}{'reset_after'} = time+30;
    $discord->get_user_p('1');  # Don't need to wait, we've replaced Mojo::IOLoop->timer with a mock.
    is($timer_id, 1, 'rate limited timer called correctly' );
}

main();

done_testing();
