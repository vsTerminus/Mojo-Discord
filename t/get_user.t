use Mojo::Base -strict;

use Test::More;
use Test::Mockify;
use Test::Mockify::Verify qw( WasCalled );
use Test::Mockify::Matcher qw( String );
use Mojolicious::Lite;
use Mojo::AsyncAwait;
use Data::Dumper;

require_ok( 'Mojo::Discord' );

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

app->start();

##########################

my $mock_logger_builder = Test::Mockify->new( 'Mojo::Log', [] );
$mock_logger_builder->mock('warn')->when(String())->thenReturnUndef;
$mock_logger_builder->mock('debug')->when(String())->thenReturnUndef; # suppress debug output
my $mock_logger = $mock_logger_builder->getMockObject();

my $discord = Mojo::Discord->new(
    token       => 'token_string',
    name        => 'bot_name',
    url         => 'bot_url',
    version     => 'bot_version',
    base_url    => '/app',
    logdir      => '.',
    loglevel    => 'warn',
    log         => $mock_logger,
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

async main => sub
{
    my $json = await $discord->get_user_p('1');
    is( $json, '{success: true}', 'discord happy path' );
    is( $rest->rate_limits->{'bucket'}{'remaining'}, 1, 'rate limit "remaining" storage' );
    $json = await $rest->get_user_p('1');
    is( $json, '{success: true}', 'rest happy path' );
    is( $rest->rate_limits->{'bucket'}{'reset_after'}, 1, 'rate limit "reset after" storage' );

    $json = await $discord->get_user_p();
    is( $json, undef, 'discord no args');
    $json = await $rest->get_user_p();
    is( $json, undef, 'rest no args' );

    $json = await $discord->get_user_p('-1');
    is( $json, undef, 'discord negative id' );
    $json = await $rest->get_user_p('-1');
    is( $json, undef, 'rest negative id' );

    $json = await $discord->get_user_p('string');
    is( $json, undef, 'discord string id' );
    $json = await $rest->get_user_p('string');
    is( $json, undef, 'discord string id' );

    # There is no Mojolicious::Lite endpoint for ID = 2
    # So this should only be successful if it uses the cache.
    # And it should fail when called from the $rest object.
    $discord->gw->users->{'2'} = '{cached: true}';
    $json = await $discord->get_user_p('2');
    is( $json, '{cached: true}', 'discord cached id' );
    $json = await $rest->get_user_p('2');
    is( $json, undef, 'rest cached id' );

    # Test rate limiting by checking to see our mock logger was called.
    # No need to call this twice, there is no rate limit logic in Discord.pm
    $rest->rate_limits->{'bucket'}{'remaining'} = 0;
    $rest->rate_limits->{'bucket'}{'reset_after'} = time; # Should allow it to recurse immediately
    $json = await $discord->get_user_p('1');
    ok(WasCalled($mock_logger, 'warn'), 'rate limit "warn" log triggered');
    is($json, '{success: true}', 'rate limit recursed successfully');
};

main()->wait();

done_testing();
