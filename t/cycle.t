use Mojo::Base -strict;

use Test::More;
use Test::Memory::Cycle;

require_ok( 'Mojo::Discord' );

my $discord = Mojo::Discord->new(
    token       => 'token_string',
    name        => 'bot_name',
    url         => 'bot_url',
    version     => 'bot_version',
    base_url    => '/app',
    logdir      => '.',
    loglevel    => 'fatal',
);

memory_cycle_ok($discord, "No Memory Cycles");
weakened_memory_cycle_ok($discord, "No Weakened Memory Cycles");

# Should do more here - connect the $discord object to a Mojolicious::Lite app, do stuff with it, and then check it again.

done_testing();
