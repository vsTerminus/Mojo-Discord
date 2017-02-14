package Mojo::Discord::Auth;

our $VERSION = '0.001';

use Mojo::Base -base;

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

has ['id', 'secret', 'name', 'url', 'version', 'code', 'refresh_token'];
has base_url        => 'https://discordapp.com/api';
has token_url       => sub { shift->base_url . '/oauth2/token'; };
has agent           => sub { my $self = shift; $self->name . ' (' . $self->url . ',' . $self->version . ')'; };
has grant_type      => sub { defined shift->code ? 'authorization_code' : 'refresh_token' };
has ua              => sub { Mojo::UserAgent->new };

# Custom Constructor to set grant type and agent name
#sub new 
#{
#    my $self = shift->SUPER::new(@_);
#   
#    $self->{'ua'}->transactor->name($self->{'agent'});
#     
#    return $self;
#}


#sub new
#{
#    my ($class, %params) = @_;
#
#    die("Mojo::Discord::Auth requires an Authorization Code or Refresh Token.") unless defined $params{'code'} or defined $params{'refresh_token'};
#    die("Mojo::Discord::Auth requires an Application ID.") unless defined $params{'id'};
#    die("Mojo::Discord::Auth requires an Application Secret.") unless defined $params{'secret'};
#    die("Mojo::Discord::Auth requires an Application Name.") unless defined $params{'name'};
#    die("Mojo::Discord::Auth requires an Application URL.") unless defined $params{'url'};
#    die("Mojo::Discord::Auth requires an Application Version.") unless defined $params{'version'};
#
#    my $self = {
#        'app' => {
#            'id'                => $params{'id'},
#            'secret'            => $params{'secret'},
#            'name'              => $params{'name'},
#            'url'               => $params{'url'},
#            'version'           => $params{'version'},
#            'useragent'         => $params{'name'} . ' (' . $params{'url'} . ',' . $params{'version'} . ')',
#        },
#        'api' => {
#            'base_url'          => 'https://discordapp.com/api',
#            'token_url'         => 'https://discordapp.com/api/oauth2/token',
#        },
#    };
#
#    if ( defined $params{'code'} )
#    {
#        $self->{'auth'}{'code'}         = $params{'code'};
#        $self->{'api'}{'grant_type'}    = 'authorization_code';
#    }
#    elsif ( defined $params{'refresh_token'} )
#    {
#        $self->{'auth'}{'refresh_token'} = $params{'refresh_token'};
#        $self->{'api'}{'grant_type'}    = 'refresh_token';
#    }
#
#    # Create the UserAgent object
#    my $ua = Mojo::UserAgent->new;
#    $ua->transactor->name($self->{'app'}{'useragent'});
#
#    # Store the UserAgent for use by other functions in this module.
#    $self->{'ua'} = $ua;
#
#    bless $self, $class;
#    return $self;
#}

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

