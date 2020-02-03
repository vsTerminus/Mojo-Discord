package Mojo::Discord;

use feature 'say';
our $VERSION = '0.001';

use Moo;
use strictures 2;

use Mojo::Discord::Gateway;
use Mojo::Discord::REST;
use Mojo::Log;
use Data::Dumper;

use namespace::clean;

has token       => ( is => 'rw' );
has name        => ( is => 'rw' );
has url         => ( is => 'rw' );
has version     => ( is => 'rw' );
has reconnect   => ( is => 'rw' );
has callbacks   => ( is => 'rw' );
has base_url    => ( is => 'rw', default => 'https://discordapp.com/api' );
has gw          => ( is => 'lazy', builder => sub {
                    my $self = shift;
                    Mojo::Discord::Gateway->new(
                        'token'         => $self->token,
                        'name'          => $self->name,
                        'url'           => $self->url,
                        'version'       => $self->version,
                        'auto_reconnect'=> $self->reconnect,
                        'callbacks'     => $self->callbacks,
                        'base_url'      => $self->base_url,
                        'log'           => $self->log,
                        'rest'          => $self->rest,
                    )});
has rest        => ( is => 'lazy', builder => sub {
                    my $self = shift;
                    Mojo::Discord::REST->new(
                        'token'         => $self->token,
                        'name'          => $self->name,
                        'url'           => $self->url,
                        'version'       => $self->version,
                        'log'           => $self->log,
                    )});
has guilds      => ( is => 'rw', default => sub { {} } );
has channels    => ( is => 'rw', default => sub { {} } );

# Logging
has log         => ( is => 'lazy', builder => sub { 
                    my $self = shift;
                    Mojo::Log->new( 
                        path => $self->logdir . '/' . $self->logfile, 
                        level => $self->loglevel 
                    )});
has logdir      => ( is => 'rw', default => '/var/log/mojo-discord' );
has logfile     => ( is => 'rw', default => 'mojo-discord.log' );
has loglevel    => ( is => 'rw', default => 'debug' );

sub init
{
    my $self = shift;
    $self->log->info('[Discord.pm] [init] New session beginning ' . localtime(time));
    $self->gw->gw_connect();
}

sub connected
{
    my $self = shift;
    return $self->gw->connected;
}

sub resume
{
    my $self = shift;
    $self->log->info('[Discord.pm] [init] Reconnecting and resuming previous session');
    $self->gw->gw_resume('resume' => 1);
}

sub disconnect
{
    my ($self, $reason) = @_;

    $self->gw->gw_disconnect($reason);
}

sub add_user
{
    my ($self, $id) = @_;

    $self->gw->add_user({ id => $id })
}

sub create_dm
{
    my ($self, $id, $callback) = @_;

    $self->rest->create_dm($id, $callback);
}

# Send "acknowledged" DM 
# aka, acknowledge a command by adding a :white_check_mark: reaction to it and then send a DM
# Takes a message ID to react to, a user ID to DM, a message to send, and an optional callback sub.
sub send_ack_dm
{
    my ($self, $message_id, $user_id, $message, $callback) = @_;

    $self->rest->send_ack_dm($message_id, $user_id, $message, $callback);
}

# Works like send_message, but takes a user ID and creates a DM first.
sub send_dm
{
    my ($self, $id, $message, $callback) = @_;

    $self->rest->send_dm($id, $message, $callback);
}

sub get_user
{
    my ($self, $id, $callback) = @_;

    if ( exists $self->gw->users->{$id} )
    {
        $callback ? $callback->( $self->gw->users->{$id} ) : return $self->gw->users->{$id};
    }
    else
    {
        # If we don't have the user stored already then use REST to look them up.
        # todo, make this also return a User hash object instead of JSON.
        $self->rest->get_user($id, $callback);
    }
}

sub get_guilds
{
    my ($self, $user, $callback) = @_;

    $self->rest->get_guilds($user, $callback);
}

sub leave_guild
{
    my ($self, $user, $guild, $callback) = @_;

    $self->rest->leave_guild($user, $guild, $callback);
}

sub set_topic
{
    my ($self, $channel, $topic, $callback) = @_;
    $self->rest->set_topic($channel, $topic, $callback);
}

# Supports hashref or string.
# String for simple messages, hashref if you need to use embeds or tts flag.
sub send_message
{
    my ($self, $channel, $message, $callback) = @_;

    $self->rest->send_message($channel, $message, $callback);
}

sub edit_message
{
    my ($self, $channel, $msgid, $message, $callback) = @_;

    $self->rest->edit_message($channel, $msgid, $message, $callback);
}

sub delete_message
{
    my ($self, $channel, $msgid, $callback) = @_;

    $self->rest->delete_message($channel, $msgid, $callback);
}


sub start_typing
{
    my ($self, $channel, $callback) = @_;

    $self->rest->start_typing($channel, $callback);
}

sub status_update
{
    my ($self, $params) = @_;

    $self->gw->status_update($params);
}

sub create_webhook
{
    my ($self, $channel, $params, $callback) = @_;

    $self->rest->create_webhook($channel, $params, $callback);
}

sub send_webhook
{
    my ($self, $channel, $id, $token, $params, $callback) = @_;

    $self->rest->send_webhook($channel, $id, $token, $params, $callback);
}

sub get_channel_webhooks
{
    my ($self, $channel, $callback) = @_;

    $self->rest->get_channel_webhooks($channel, $callback);
}

sub get_guild_webhooks
{
    my ($self, $guild, $callback) = @_;

    $self->rest->get_guild_webhooks($guild, $callback);
}

# Only get cached webhooks, do not fetch from REST API
sub get_cached_webhooks
{
    my ($self, $channel) = @_;

    return $self->gw->webhooks->{$channel};
}

sub add_reaction
{
    my ($self, $channel, $msgid, $emoji, $callback) = @_;

    $self->rest->add_reaction($channel, $msgid, $emoji, $callback);
}

1;

=head1 NAME

Mojo::Discord - An implementation of the Discord Public API using Mojo

=head1 SYNOPSIS

```perl
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
```

Elsewhere...
```perl
#!/usr/bin/env perl

use v5.10;
use strict;
use warnings;

use Chat::Bot;

my $bot = Chat::Bot->new(
    token       => 'MwMTA5MTg0.CtXwmw.omfoNppFLr',
    logdir      => '/path/to/logs/chatbot',
);

# This should be the last line of your file, because nothing below it will execute.
$bot->start();

```

=head1 DESCRIPTION

L<Mojo::Discord> is a L<Mojo::UserAgent> based L<Discord|https://discordapp.com> API library designed for creating bots (including user-bots). A Discord User or Bot Token is required.

The Discord API is divided into four main parts: OAuth, REST, Gateway, and Guild. The main module is a wrapper that allows you to use the REST and Gateway modules together as part of a single object.

All REST methods can be called with an optional trailing callback argument to run a non-blocking API Query.

Note: This module implements only a subset of the available API calls. Additional features will be added as needed for my other projects, or possibly by request. You may also contribute via github pull request.

=head1 ATTRIBUTES

L<Mojo::Discord> implements the following attributes

=head2 init()

Request the websocket Gateway URL and then establish a new websocket connection to that URL

=head2 resume()

Request the websocket Gateway URL and resume a previous Gateway connection.

The only difference between this and init is that init sends an IDENT packet to start a new connection while this sends a RESUME packet with a sequence number which triggers Discord to re-send everything the bot missed since that sequence number.

=head2 disconnect($reason)

Close the websocket connection, optionally specify a reason as a string parameter.

=head2

=head1 BUGS

Report issues on github

=head1 AUTHOR

Travis Smith <tesmith@cpan.org>

=head1 COPYRIGHT AND LICENSE
This software is Copyright (c) 2017 by Travis Smith.

This is free software, licensed under:

  The MIT (X11) License

=head1 SEE ALSO

L<Mojo::UserAgent>
