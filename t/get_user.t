use Mojo::Base -strict;

use Test::More;
use Mojolicious::Lite;
use Mojo::AsyncAwait;
use Data::Dumper;

require_ok( 'Mojo::Discord' );

get '/app/users/1' => sub {
    my $c = shift;
    my $user_id = $c->param('user_id');
    $c->render(json => '{success: true}');
};

get '/app/users/rate_limited' => sub {
};

app->start();

##########################

my $discord = Mojo::Discord->new(
    token       => 'token_string',
    name        => 'bot_name',
    url         => 'bot_url',
    version     => 'bot_version',
    base_url    => '/app',
    logdir      => 'log',
    loglevel    => 'fatal');

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
    $json = await $rest->get_user_p('1');
    is( $json, '{success: true}', 'rest happy path' );

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
};

main()->wait();

done_testing();
