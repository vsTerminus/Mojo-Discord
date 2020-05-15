package Mojo::Discord::Auth;
use feature 'say';
our $VERSION = '0.001';

use Moo;
use strictures 2;

extends 'Mojo::Discord';

use Mojo::UserAgent;
use Mojo::JSON qw(decode_json);
use Data::Dumper;

########################
# This module handles some of the OAuth2 stuff for Discord
# 
# For now it really doesn't do much other than take an Auth Code and request a Token.
# You also have to pass in the usual name/url/version for the application's UserAgent string,
# and for this module it also requires the Application's ID and Secret, as well as the Auth Callback URL
########################

has id                  => ( is => 'ro', required => 1 );
has secret              => ( is => 'ro', required => 1 );
has name                => ( is => 'rw', required => 1 );
has url                 => ( is => 'rw', required => 1 );
has version             => ( is => 'ro', required => 1 );
has code                => ( is => 'rw' );
has refresh_token       => ( is => 'ro' );
has verbose             => ( is => 'rw' );
has base_url            => ( is => 'ro', default => 'https://discord.com/api' );
has token_url           => ( is => 'ro', default => sub { shift->base_url . '/oauth2/token' } );
has agent               => ( is => 'rw' );
has grant_type          => ( is => 'rw', default => sub { defined shift->code? 'authorization_code' : 'refresh_token' } );
has ua                  => ( is => 'rw', default => sub { Mojo::UserAgent->new } );

sub BUILD
{
    my $self = shift;

    $self->agent( $self->name . ' (' . $self->url . ',' . $self->version . ')' );
    $self->ua->transactor->name($self->agent);
}


sub request_token
{
    my ($self) = @_;
    my $token_url = $self->token_url;
    my $args = {
        'client_id'         => $self->id,
        'client_secret'     => $self->secret,
        'redirect_uri'      => $self->url,   # This isn't used, it just has to be in the request.
        'grant_type'        => $self->grant_type,
    };
        
    if ( defined $self->code )
    {
        $args->{'code'}             = $self->code;
    }
    elsif ( defined $self->refresh_token )
    {
        $args->{'refresh_token'}    = $self->refresh_token;
    }

    # Send the POST to the Token endpoint
    say "Token URL: $token_url";
    my $tx = $self->ua->post($token_url => {Accept => '*/*'} => form => $args);

    # Extract the JSON string with our results
    my $result = $tx->res->content->asset->{'content'};

    say  Dumper($result);

    # Return a perl hashref instead of a JSON string
    return decode_json($result);
}

1;

