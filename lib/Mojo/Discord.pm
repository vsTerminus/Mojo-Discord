package Mojo::Discord;

use feature 'say';
our $VERSION = '0.001';

use Moo;
use strictures 2;

use Mojo::Log;
use Mojo::Discord::Gateway;
use Mojo::Discord::REST;
use Data::Dumper;

use namespace::clean;

has token       => ( is => 'rw' );
has name        => ( is => 'rw' );
has url         => ( is => 'rw' );
has version     => ( is => 'rw' );
has verbose     => ( is => 'rw' );
has reconnect   => ( is => 'rw' );
has callbacks   => ( is => 'rw' );
has base_url    => ( is => 'rw', default => 'https://discordapp.com/api' );
has gw          => ( is => 'rw' );
has rest        => ( is => 'rw' );
has guilds      => ( is => 'rw' );
has channels    => ( is => 'rw' );

# Logging
has log         => ( is => 'rwp' );
has logdir      => ( is => 'rw', default => '/var/log/mojo-discord' );
has logfile     => ( is => 'rw', default => 'mojo-discord.log' );
has loglevel    => ( is => 'rw', default => 'info' );

sub init
{
    my $self = shift;

    $self->_set_log( Mojo::Log->new( path => $self->logdir . '/' . $self->logfile, level => $self->loglevel ) );
    $self->log->info('[Discord.pm] [init] New session beginning ' . localtime(time));

    $self->guilds({});
    $self->channels({});

    $self->rest(Mojo::Discord::REST->new(
        'token'         => $self->token,
        'name'          => $self->name,
        'url'           => $self->url,
        'version'       => $self->version,
        'verbose'       => $self->verbose,
        'log'           => $self->log,
    ));

    $self->gw(Mojo::Discord::Gateway->new(
        'token'         => $self->token,
        'name'          => $self->name,
        'url'           => $self->url,
        'version'       => $self->version,
        'verbose'       => $self->verbose,
        'reconnect'     => $self->reconnect,
        'callbacks'     => $self->callbacks,
        'base_url'      => $self->base_url,
        'log'           => $self->log,
    ));

    # Give the gateway object access to the REST object.
    $self->gw->rest($self->rest);

    # Get Gateway URL
    my $gw_url = $self->gw->gateway;

    # Set up connection
    $self->gw->gw_connect($gw_url);
}

sub connected
{
    my $self = shift;
    return $self->gw->connected;
}

sub resume
{
    my $self = shift;

    # Get Gateway URL
    my $gw_url = $self->{'gw'}->gateway;

    $self->gw->gw_resume($gw_url);
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

1;

=head1 NAME

Mojo::Discord - An implementation of the Discord Public API using Mojo

=head1 SYNOPSIS

code here...

=head1 DESCRIPTION

L<Mojo::Discord> is a L<Mojo::UserAgent> based L<Discord|https://discordapp.com> API library designed for creating bots (including user-bots). A Discord User or Bot Token is required.

The Discord API is divided into three main parts: OAuth, REST, and Gateway. The main module is a wrapper that allows you to use the REST and Gateway modules together as part of a single object.

All REST methods can be called with an optional trailing callback argument to run a non-blocking API Query.

Note: This module implements only a subset of the available API calls. Additional features will be added as needed for my other projects, or possibly by request.

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

Report issues on public bugtracker or github

=head1 AUTHOR

Travis Smith <tesmith@cpan.org>

=head1 COPYRIGHT AND LICENSE
This software is Copyright (c) 2017 by Travis Smith.

This is free software, licensed under:

  The MIT (X11) License

=head1 SEE ALSO

L<Mojo::UserAgent>
