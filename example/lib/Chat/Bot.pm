package Chat::Bot;
use feature 'say';

use Moo;
use strictures 2;
use Mojo::Discord;
use namespace::clean;

has token       => ( is => 'ro' );
has name        => ( is => 'ro', default => 'Mojo::Discord Bot' );
has url         => ( is => 'ro', default => 'https://mywebsite.com' );
has version     => ( is => 'ro', default => '1.0' );
has reconnect   => ( is => 'rw', default => 1 );
has loglevel    => ( is => 'ro', default => 'info' );
has logdir      => ( is => 'ro' );

has discord     => ( is => 'lazy', builder => sub {
    my $self = shift;
    Mojo::Discord->new(
        token       => $self->token,
        name        => $self->name,
        url         => $self->url,
        version     => $self->version,
        reconnect   => $self->reconnect,
        loglevel    => $self->loglevel,
        logdir      => $self->logdir,
    )
});

sub start
{
    my $self = shift;

    # Before we start the bot we need to subscribe to Discord Gateway Events that we care about
    # In thie case we want to know when the bot is connected ('READY') and  someone 
    # sends a message ('MESSAGE_CREATE'). See the Discord API docs for a full list
    # of events it can emit.
    
    $self->discord->gw->on('READY' => sub {
        my ($gw, $hash) = @_;

        say localtime(time) . ' Connected to Discord.';
    });

    $self->discord->gw->on('MESSAGE_CREATE' => sub {
        my ($gw, $hash) = @_;

        # Extract some information from the payload that we care about
        # See the Discord API docs for full payload structures,
        # or use Data::Dumper to print the structure of $hash to the screen and look at it yourself.
        my $msg = $hash->{'content'};
        my $channel_id = $hash->{'channel_id'};
        my $author_id = $hash->{'author'}{'id'};
        my $message_id = $hash->{'id'};

        # Print the discord user's ID and the message content
        say localtime(time) . ' ' . $author_id . "\t" . $msg;

        # If the message is "ping" reply with "pong"
        $self->discord->send_message($channel_id, 'pong') if ( lc $msg eq 'ping' );

        # If the message is "foo" reply via DM with "bar"
        $self->discord->send_dm($author_id, 'bar') if ( lc $msg eq 'foo' );
        
        # If the message is "test", acknowledge the message and reply via DM with "success!"
        $self->discord->send_ack_dm($channel_id, $message_id, $author_id, 'success!') if ( lc $msg eq 'test' );
    });

    # Start the connection
    $self->discord->init();

    # Start the IOLoop (unless it is already running)
    # This allows the application to go into a non-blocking wait loop
    # where future actions will be drive by the events emitted by Discord.
    # Nothing below this line will execute until the IOLoop stops (which for most bots is never).
    Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
}

1;


