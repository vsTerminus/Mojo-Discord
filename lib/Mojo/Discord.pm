package Mojo::Discord;

our $VERSION = '0.001';

use Mojo::Base -base;

use Mojo::Discord::Gateway;
use Mojo::Discord::REST;
use Data::Dumper;

has ['token', 'name', 'url', 'version', 'verbose', 'reconnect', 'callbacks'];
has base_url    => 'https://discordapp.com/api';
has gw          => sub { Mojo::Discord::Gateway->new(shift) };
has rest        => sub { Mojo::Discord::REST->new(shift) };

sub init
{
    my $self = shift;

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
