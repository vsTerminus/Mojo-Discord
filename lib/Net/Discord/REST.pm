package Net::Discord::REST;

use v5.10;
use warnings;
use strict;

use Mojo::UserAgent;

sub new
{
    my ($class, %params) = @_;
    my $self = {};

    die("Net::Discord::REST requires a Token.") unless defined $params{'token'};
    die("Net::Discord::REST requires an application name.") unless defined $params{'name'};
    die("Net::Discord::REST requires an application URL.") unless defined $params{'url'};
    die("Net::Discord::REST requires an application version.") unless defined $params{'version'};

    # Store the token, application name, url, and version
    $self->{'token'}    = $params{'token'};

    
    # API Vars - Will need to be updated if the API changes
    $self->{'base_url'}     = 'https://discordapp.com/api';
    $self->{'name'}         = $params{'name'};
    $self->{'url'}          = $params{'url'};
    $self->{'version'}      = $params{'version'};
    
    # Other vars
    $self->{'agent'}        = $self->{'name'} . ' (' . $self->{'url'} . ',' . $self->{'version'} . ')';

    my $ua = Mojo::UserAgent->new;
    $ua->transactor->name($self->{'agent'});

    # Make sure the token is added to every request automatically.
    $ua->on(start => sub {
        my ($ua, $tx) = @_;
        $tx->req->headers->authorization("Bot " . $self->{'token'});
    });

    $self->{'ua'} = $ua;

    bless $self, $class;
    return $self;
}

sub send_message
{
    my ($self, $dest, $content) = @_;

    my $post_url = $self->{'base_url'} . "/channels/$dest/messages";
    my $tx = $self->{'ua'}->post($post_url => {Accept => '*/*'} => json => {'content' => $content});
}

# Tell the channel that the bot is "typing", aka thinking about a response.
sub start_typing
{
    my ($self, $dest) = @_;

    my $typing_url = $self->{'base_url'} . "/channels/$dest/typing";

    $self->{'ua'}->post($typing_url);
}

1;

