package Mojo::Discord;

our $VERSION = '0.001';

use Moo;
use strictures 2;

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

sub init
{
    my $self = shift;

    $self->guilds({});
    $self->channels({});
    $self->gw(Mojo::Discord::Gateway->new($self));
    $self->rest(Mojo::Discord::REST->new($self));

    # Get Gateway URL
    my $gw_url = $self->gw->gateway;

    # Set up connection
    $self->gw->gw_connect($gw_url);
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

sub get_user
{
    my ($self, $id, $callback) = @_;

    $self->rest->get_user($id, $callback);
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
