package Net::Discord;

use v5.10;
use warnings;
use strict;

use Net::Discord::Gateway;
use Net::Discord::REST;
use Data::Dumper;

sub new
{
    my ($class, %params) = @_;
    my $self = {};

    die("Net::Discord::REST requires a Token.") unless defined $params{'token'};
    die("Net::Discord::REST requires an application name.") unless defined $params{'name'};
    die("Net::Discord::REST requires an application URL.") unless defined $params{'url'};
    die("Net::Discord::REST requires an application version.") unless defined $params{'version'};

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
    my $gw                  = Net::Discord::Gateway->new(%{$self});
    my $rest                = Net::Discord::REST->new(%{$self});

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

1;

