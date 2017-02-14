package Mojo::Discord;

use v5.10;
use warnings;
use strict;

use Mojo::Discord::Gateway;
use Mojo::Discord::REST;
use Data::Dumper;

sub new
{
    my ($class, %params) = @_;
    my $self = {};

    die("Mojo::Discord::REST requires a Token.") unless defined $params{'token'};
    die("Mojo::Discord::REST requires an application name.") unless defined $params{'name'};
    die("Mojo::Discord::REST requires an application URL.") unless defined $params{'url'};
    die("Mojo::Discord::REST requires an application version.") unless defined $params{'version'};

    # Store the token, application name, url, and version
    $self->{'token'}        = $params{'token'};
    $self->{'name'}         = $params{'name'};
    $self->{'url'}          = $params{'url'};
    $self->{'version'}      = $params{'version'};
    $self->{'verbose'}      = $params{'verbose'} if defined $params{'verbose'};

    # Store the reconnect setting
    $self->{'reconnect'}    = $params{'reconnect'} if defined $params{'reconnect'};

    # Store the callbacks if they exist
    $self->{'callbacks'}    = $params{'callbacks'} if exists $params{'callbacks'};

    # API Vars - Will need to be updated if the API changes
    $self->{'base_url'}     = 'https://discordapp.com/api';

    # Create the Gateway and REST objects
    my $gw                  = Mojo::Discord::Gateway->new(%{$self});
    my $rest                = Mojo::Discord::REST->new(%{$self});

    $self->{'gw'}           = $gw;
    $self->{'rest'}         = $rest;

    bless $self, $class;
    return $self;
}

sub init
{
    my $self = shift;

    # Get Gateway URL
    my $gw_url = $self->{'gw'}->gateway;

    # Set up connection
    $self->{'gw'}->gw_connect($gw_url);
}

sub resume
{
    my $self = shift;
    
    # Get Gateway URL
    my $gw_url = $self->{'gw'}->gateway;

    $self->{'gw'}->gw_resume($gw_url);
}

sub disconnect
{
    my ($self, $reason) = @_;

    $self->{'gw'}->gw_disconnect($reason);
}

sub get_user
{
    my ($self, $id, $callback) = @_;

    $self->{'rest'}->get_user($id, $callback);
}

sub get_guilds
{
    my ($self, $user, $callback) = @_;
    
    $self->{'rest'}->get_guilds($user, $callback);
}

sub leave_guild
{
    my ($self, $user, $guild, $callback) = @_;

    $self->{'rest'}->leave_guild($user, $guild, $callback);
}

# Supports hashref or string.
# String for simple messages, hashref if you need to use embeds or tts flag.
sub send_message
{
    my ($self, $channel, $message, $callback) = @_;

    $self->{'rest'}->send_message($channel, $message, $callback);
}

sub start_typing
{
    my ($self, $channel, $callback) = @_;

    $self->{'rest'}->start_typing($channel, $callback);
}

sub status_update
{
    my ($self, $params) = @_;
    
    $self->{'gw'}->status_update($params);
}

sub create_webhook
{
    my ($self, $channel, $params, $callback) = @_;

    $self->{'rest'}->create_webhook($channel, $params, $callback);
}

sub send_webhook
{
    my ($self, $channel, $id, $token, $params, $callback) = @_;

    $self->{'rest'}->send_webhook($channel, $id, $token, $params, $callback);
}

sub get_channel_webhooks
{
    my ($self, $channel, $callback) = @_;

    $self->{'rest'}->get_channel_webhooks($channel, $callback);
}

sub get_guild_webhooks
{
    my ($self, $guild, $callback) = @_;

    $self->{'rest'}->get_guild_webhooks($guild, $callback);
}

1;

