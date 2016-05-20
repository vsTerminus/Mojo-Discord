package Net::Discord::Auth;

use v5.10;
use warnings;
use strict;

use Mojo::UserAgent;
use Mojo::JSON qw(decode_json);

########################
# This module handles some of the OAuth2 stuff for Discord
# 
# For now it really doesn't do much other than take an Auth Code and request a Token.
# You also have to pass in the usual name/url/version for the application's UserAgent string,
# and for this module it also requires the Application's ID and Secret, as well as the Auth Callback URL
########################

sub new
{
    my ($class, $params) = @_;

    die("Net::Discord::Auth requires an Authorization Code.") unless defined $params->{'code'};
    die("Net::Discord::Auth requires an Application ID.") unless defined $params->{'id'};
    die("Net::Discord::Auth requires an Application Secret.") unless defined $params->{'secret'};
    die("Net::Discord::Auth requires an Application Name.") unless defined $params->{'name'};
    die("Net::Discord::Auth requires an Application URL.") unless defined $params->{'url'};
    die("Net::Discord::Auth requires an Application Version.") unless defined $params->{'version'};

    my $self = {
        'auth' => {
            'code'              => $params->{'code'},
        },
        'app' => {
            'id'                => $params->{'id'},
            'secret'            => $params->{'secret'},
            'name'              => $params->{'name'},
            'url'               => $params->{'url'},
            'version'           => $params->{'version'},
            'useragent'         => $params->{'name'} . ' (' . $params->{'url'} . ',' . $params->{'version'} . ')',
        },
        'api' => {
            'base_url'          => 'https://discordapp.com/api',
            'token_url'         => 'https://discordapp.com/api/oauth2/token',
            'grant_type'        => 'authorization_code',
        },
    };

    # Create the UserAgent object
    my $ua = Mojo::UserAgent->new;
    $ua->transactor->name($self->{'app'}{'useragent'});

    # Store the UserAgent for use by other functions in this module.
    $self->{'ua'} = $ua;

    bless $self, $class;
    return $self;
}

sub request_token
{
    my ($self) = @_;
    my $token_url = $self->{'api'}{'token_url'};
    my $args = {
        'client_id'         => $self->{'app'}{'id'},
        'client_secret'     => $self->{'app'}{'secret'},
        'grant_type'        => $self->{'api'}{'grant_type'},
        'code'              => $self->{'auth'}{'code'},
        'redirect_uri'      => $self->{'app'}{'url'},   # This isn't used, it just has to be in the request.
    };

    # Send the POST to the Token endpoint
    my $tx = $self->{'ua'}->post($token_url => {Accept => '*/*'} => form => $args);

    # Extract the JSON string with our results
    my $result = $tx->res->content->asset->{'content'};

    # Return a perl hashref instead of a JSON string
    return decode_json($result);
}

1;

